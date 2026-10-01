#!/bin/sh
# Jasmin 加密环境诊断 —— 一键定位「加密 0/N 全部失败」的原因
# 用法: sh jasmin_diagnose.sh [目标目录，默认 /tmp /home /root /var /opt /srv]
# 加密需要为每个被加密文件额外生成一个等大的 .jasmin，
# 因此目标目录所在分区必须拥有 >= 待加密数据总量的空闲空间与 inode。

DIRS="$*"
[ -n "$DIRS" ] || DIRS="/tmp /home /root /var /opt /srv"

echo "════════ Jasmin 加密环境诊断 ════════"
echo "时间: $(date 2>/dev/null)"
echo "用户: $(id 2>/dev/null)"
echo ""

# ── 1. 各分区空间与 inode ──
echo "──── 1. 空间 / inode ────"
SEEN=""
for d in $DIRS; do
    [ -d "$d" ] || continue
    T=$(df -P "$d" 2>/dev/null | awk 'NR==2{print $6}')
    case " $SEEN " in *" $T "*) continue;; esac
    SEEN="$SEEN $T"
    echo "分区: $T   (来自 $d)"
    df -h "$T" 2>/dev/null | awk 'NR==1{print "  "$0} NR==2{print "  "$0}'
    df -i "$T" 2>/dev/null | awk 'NR==2{printf "  inode: 已用 %s / 总计 %s (%s)\n",$3,$2,$5}'
    # 阈值判断
    avail=$(df -P "$d" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$avail" ] && [ "$avail" -lt 1048576 ] 2>/dev/null; then
        echo "  ★ 警告: 可用空间不足 1GB，加密会大量失败"
    fi
    iuse=$(df -i "$d" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    if [ -n "$iuse" ] && [ "$iuse" -gt 90 ] 2>/dev/null; then
        echo "  ★ 警告: inode 使用率 $iuse%，无法为新 .jasmin 分配 inode"
    fi
    echo ""
done

# ── 2. 挂载参数（只读检测） ──
echo "──── 2. 挂载参数（是否只读） ────"
mount 2>/dev/null | grep -E "^/|overlay|tmpfs" | while IFS= read -r l; do
    case "$l" in
        *" ro,"*|*"(ro"*) echo "  ★ 只读: $l";;
    esac
done
echo "  (以上若无 ★ 则无只读挂载)"
echo ""

# ── 3. 就地可写实测 ──
echo "──── 3. 就地可写实测（关键） ────"
for d in $DIRS; do
    [ -d "$d" ] || continue
    f="$d/.__jasmin_wtest_$$"
    if (echo test > "$f") 2>/dev/null; then
        if [ "$(cat "$f" 2>/dev/null)" = "test" ]; then
            echo "  ✓ $d 可创建并可写"
        else
            echo "  ★ $d 文件创建成功但内容读回异常（可能是只读层/覆盖文件系统）"
        fi
        rm -f "$f" 2>/dev/null
    else
        echo "  ★ $d 无法创建文件（只读 / 空间满 / inode 满 / 权限不足）"
    fi
done
echo ""

# ── 4. 大文件写入实测(1MB) ──
echo "──── 4. 1MB 写入实测 ────"
for d in $DIRS; do
    [ -d "$d" ] || continue
    f="$d/.__jasmin_bigtest_$$"
    if dd if=/dev/zero of="$f" bs=1024 count=1024 2>/dev/null; then
        echo "  ✓ $d 可写入 1MB"
    else
        echo "  ★ $d 无法写入 1MB —— 空间不足或配额超限"
    fi
    rm -f "$f" 2>/dev/null
done
echo ""

# ── 5. 权限与配额 ──
echo "──── 5. 权限 / 配额 / 资源限制 ────"
echo "  ulimit -n (打开文件数): $(ulimit -n 2>/dev/null)"
if command -v quota >/dev/null 2>&1; then
    quota -s 2>/dev/null | head -5 || echo "  (无配额信息)"
else
    echo "  (系统无 quota 命令)"
fi
echo ""

# ── 6. 目标数据量 ──
echo "──── 6. 目标数据规模（决定需要多少额外空间） ────"
for d in $DIRS; do
    [ -d "$d" ] || continue
    n=$(find "$d" -type f 2>/dev/null | wc -l)
    s=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
    echo "  $d: $n 个文件, 合计 $s"
    echo "      → 加密需要额外约 $s 的空闲空间与 $n 个 inode"
done
echo ""

echo "════════ 诊断结束 ════════"
echo "若上面出现 ★，即为加密大面积失败的原因。"
echo "若无 ★ 但加密仍失败，请重新生成载荷运行 —— 新版会把真实 errno 与原因直接打印出来。"
