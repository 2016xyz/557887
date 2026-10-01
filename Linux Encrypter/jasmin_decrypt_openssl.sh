#!/bin/sh
# Jasmin 解密脚本 (纯 openssl 实现，无需 cryptography / pip / 编译)
# 用法: sh jasmin_decrypt_openssl.sh <私钥.pem> [目录1 目录2 ...]
#
# 文件格式: [SHA256 32B][AES-256-CBC密文][RSA-OAEP加密的key+iv][4B 长度(小端)]
# 关键: 强制 C locale，否则二进制↔十六进制转换会被 UTF-8 污染
export LC_ALL=C
export LANG=C

PRIV="$1"
if [ -z "$PRIV" ] || [ ! -f "$PRIV" ]; then
    echo "用法: $0 <私钥.pem> [目录...]"
    exit 1
fi
shift

if ! command -v openssl >/dev/null 2>&1; then
    echo "[!] 缺少 openssl 命令"
    exit 1
fi
if ! command -v od >/dev/null 2>&1; then
    echo "[!] 缺少 od 命令"
    exit 1
fi

DIRS="$*"
[ -n "$DIRS" ] || DIRS="/home /root /var /opt /tmp /srv"

TD="/tmp/.jdec_$$"
mkdir -p "$TD" || exit 1
trap 'rm -rf "$TD"' EXIT INT TERM

OK=0
FAIL=0

decrypt_one(){
    F="$1"
    SZ=$(wc -c < "$F" 2>/dev/null)
    [ -n "$SZ" ] || return 1
    # 最小长度: 32(sha)+16(1个AES块)+256(RSA-2048)+4 = 308
    [ "$SZ" -ge 308 ] || return 1

    # 末尾4字节 = RSA块长度（小端）
    EK_LEN=$(tail -c 4 "$F" | od -An -tu1 | awk '{print $1+$2*256+$3*65536+$4*16777216}')
    [ -n "$EK_LEN" ] || return 1
    [ "$EK_LEN" -ge 128 ] || return 1
    [ "$EK_LEN" -le 512 ] || return 1

    EK_START=$((SZ - 4 - EK_LEN))
    [ "$EK_START" -gt 32 ] || return 1
    CT_LEN=$((EK_START - 32))
    [ "$CT_LEN" -ge 16 ] || return 1

    # 切分: 头部摘要 / 密文 / RSA块（用 tail+head 高效定位，避免 dd bs=1 逐字节）
    head -c 32 "$F" > "$TD/hash"
    tail -c "+33" "$F" | head -c "$CT_LEN" > "$TD/ct"
    tail -c "+$((EK_START + 1))" "$F" | head -c "$EK_LEN" > "$TD/ek"

    # RSA-OAEP 解出 key(32B)+iv(16B)
    if ! openssl pkeyutl -decrypt -inkey "$PRIV" \
            -in "$TD/ek" -out "$TD/kiv" \
            -pkeyopt rsa_padding_mode:oaep \
            -pkeyopt rsa_oaep_md:sha256 \
            -pkeyopt rsa_mgf1_md:sha256 2>/dev/null; then
        return 1
    fi
    [ "$(wc -c < "$TD/kiv")" -eq 48 ] || return 1

    head -c 32 "$TD/kiv" > "$TD/k"
    tail -c 16 "$TD/kiv" > "$TD/iv"

    KH=$(od -An -tx1 -v "$TD/k" | tr -d ' \n')
    IH=$(od -An -tx1 -v "$TD/iv" | tr -d ' \n')
    [ -n "$KH" ] || return 1
    [ -n "$IH" ] || return 1

    # AES-256-CBC 解密（openssl 自动去除 PKCS7 padding）
    if ! openssl enc -d -aes-256-cbc -nosalt \
            -in "$TD/ct" -out "$TD/plain" \
            -K "$KH" -iv "$IH" 2>/dev/null; then
        return 1
    fi

    # SHA256 完整性校验
    OH=$(od -An -tx1 -v "$TD/hash" | tr -d ' \n')
    NH=$(openssl dgst -sha256 -binary "$TD/plain" | od -An -tx1 -v | tr -d ' \n')
    if [ "$OH" != "$NH" ]; then
        echo "[!] INTEGRITY FAIL: $F"
        return 1
    fi

    OUT=$(printf '%s' "$F" | sed 's/\.jasmin$//')
    mv -f "$TD/plain" "$OUT" || return 1
    rm -f "$F"
    echo "[+] $OUT"
    return 0
}

for D in $DIRS; do
    [ -d "$D" ] || continue
    find "$D" -type f -name '*.jasmin' 2>/dev/null > "$TD/list"
    while IFS= read -r F; do
        [ -n "$F" ] || continue
        if decrypt_one "$F"; then
            OK=$((OK + 1))
        else
            FAIL=$((FAIL + 1))
            echo "[-] 失败: $F"
        fi
    done < "$TD/list"
done

echo ""
echo "=== 完成: $OK 个已解密, $FAIL 个失败 ==="
[ "$FAIL" -eq 0 ]
