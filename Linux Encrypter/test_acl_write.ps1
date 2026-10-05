# ════════════════════════════════════════════════════════════════════════
#  jasmin_unlock.ps1 受保护目录写入（ACL）回归测试 —— 需在 Windows 上运行
# ════════════════════════════════════════════════════════════════════════
#  背景：C:\ProgramData\Microsoft\Diagnosis\DownloadedSettings\ 这类目录由 SYSTEM
#        持有、ACL 只给 Administrators 只读(RX)。加密端以 SYSTEM 运行能写进去，
#        手工以 Administrator 解密则报：
#          Exception calling "WriteAllBytes" with "2" argument(s):
#          "Access to the path 'C:\...\xxx.json' is denied."
#        修复后：写失败 -> takeown + icacls 拿回该目录所有权与写权限 -> 重试。
#
#  本测试用 icacls 造出一个"管理员无写权限"的目录来【真实复现】该场景，再断言
#  修复逻辑能自愈；同时断言"未提权时不谎报成功、且不删除 .jasmin 密文"。
#
#  用法（必须以管理员身份运行，否则无法造 ACL，也无法修 ACL）：
#     powershell -ExecutionPolicy Bypass -File test_acl_write.ps1
#  退出码：0=全部通过，1=存在失败
# ════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = 'Stop'

$SCRIPT = Join-Path $PSScriptRoot 'jasmin_unlock.ps1'
if (-not (Test-Path -LiteralPath $SCRIPT)) { Write-Host "[X] 找不到 $SCRIPT"; exit 1 }

# ── 抽取被测函数（Test-IsElevated / Repair-PathAcl / Write-RestoredFile）──
$src   = [IO.File]::ReadAllText($SCRIPT)
$begin = $src.IndexOf('function Test-IsElevated {')
$end   = $src.IndexOf('# ── 遍历器')
if ($begin -lt 0 -or $end -le $begin) { Write-Host '[X] 无法抽取函数区（文件结构已变？）'; exit 1 }
Invoke-Expression $src.Substring($begin, $end - $begin)

$fail = 0
function Chk([string]$n, [bool]$ok, [string]$d = '') {
    if ($ok) { Write-Host ("  [PASS] " + $n + $(if ($d) { "  ($d)" } else { '' })) -ForegroundColor Green }
    else     { Write-Host ("  [FAIL] " + $n + "  $d") -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== jasmin_unlock.ps1 受保护目录写入回归测试 ===' -ForegroundColor Cyan

$root = Join-Path $env:TEMP ('jasmin_acl_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $root | Out-Null
# 测试用的 "只读目录"：拒绝 Administrators 的写入数据/追加数据（复现 Diagnosis 目录形态）
$locked = Join-Path $root 'locked'
New-Item -ItemType Directory -Force -Path $locked | Out-Null

try {
    # ── 1) 造场景：目录对 Administrators 拒写 ──
    Write-Host '* 1) 构造"管理员无写权限"的目录（icacls /deny）'
    & icacls.exe "$locked" /deny '*S-1-5-32-544:(WD,AD)' 2>$null | Out-Null
    $probe = Join-Path $locked 'probe.txt'
    $denied = $false
    try { [IO.File]::WriteAllBytes($probe, [byte[]](1, 2, 3)) } catch { $denied = $true }
    Chk '目录确实拒绝了写入（场景构造成功）' $denied
    if (-not $denied) {
        Write-Host '  [!] 未能构造拒绝场景（可能未提权）—— 后续断言不具意义，直接失败收尾' -ForegroundColor Yellow
        $fail++
    }

    # ── 2) 未提权的行为：必须明确报错、不谎报成功、不产生明文 ──
    Write-Host '* 2) 未提权分支（函数内用桩模拟非管理员）'
    $realIsElev = ${function:Test-IsElevated}
    Set-Item function:Test-IsElevated -Value { return $false }
    $w1 = Write-RestoredFile -Path (Join-Path $locked 't1.txt') -Bytes ([Text.Encoding]::UTF8.GetBytes('x'))
    Chk 'ok=$false（未谎报成功）' ($w1.ok -eq $false)
    Chk 'note 指出需管理员权限' ($w1.note -match 'NOT elevated')
    Chk '未落地任何明文' (-not (Test-Path -LiteralPath (Join-Path $locked 't1.txt') -PathType Leaf))
    Set-Item function:Test-IsElevated -Value $realIsElev

    # ── 3) 提权后的自愈路径（真实执行 takeown + icacls）──
    Write-Host '* 3) 提权分支：真实 takeown + icacls 后重试写入'
    $t3 = Join-Path $locked 't3.txt'
    $w2 = Write-RestoredFile -Path $t3 -Bytes ([Text.Encoding]::UTF8.GetBytes('recovered'))
    Chk 'ok=$true（ACL 自愈成功）' ($w2.ok -eq $true) $w2.note
    Chk 'note 标注走了 ACL 修复' ($w2.note -match 'ACL repaired')
    Chk '明文内容正确' ((Test-Path $t3) -and ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($t3)) -eq 'recovered'))

    # ── 4) 只读属性文件 ──
    Write-Host '* 4) 已存在且只读的目标文件'
    $t4 = Join-Path $root 'ro.txt'
    [IO.File]::WriteAllBytes($t4, [Text.Encoding]::UTF8.GetBytes('old'))
    [IO.File]::SetAttributes($t4, [IO.FileAttributes]::ReadOnly)
    $w3 = Write-RestoredFile -Path $t4 -Bytes ([Text.Encoding]::UTF8.GetBytes('new'))
    Chk 'ok=$true' ($w3.ok -eq $true)
    Chk '只读位已清除且内容更新' ((-not ([IO.File]::GetAttributes($t4) -band [IO.FileAttributes]::ReadOnly)) -and
                                  ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($t4)) -eq 'new'))

    # ── 5) 关键安全属性：写入失败绝不删除 .jasmin 密文 ──
    Write-Host '* 5) 安全属性：写不出明文时不删密文'
    Set-Item function:Test-IsElevated -Value { return $false }
    Set-Item function:Repair-PathAcl      -Value { param([string]$TargetPath) return 'stub' }
    $enc = Join-Path $locked 'data.txt.jasmin'
    [IO.File]::WriteAllBytes($enc, [byte[]](9, 9, 9))
    $w4 = Write-RestoredFile -Path (Join-Path $locked 'data.txt') -Bytes ([Text.Encoding]::UTF8.GetBytes('plain'))
    Chk '写入失败（ok=$false）' ($w4.ok -eq $false)
    Chk '密文 .jasmin 仍然存在（未丢数据）' (Test-Path -LiteralPath $enc -PathType Leaf)
}
finally {
    # 清理：先摘掉 deny，再删树
    & icacls.exe "$locked" /remove:d '*S-1-5-32-544' 2>$null | Out-Null
    & takeown.exe /f "$root" /r /d y 2>$null | Out-Null
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host '=== 全部通过 ===' -ForegroundColor Green; exit 0 }
else { Write-Host ("=== 失败 " + $fail + " 项 ===") -ForegroundColor Red; exit 1 }
