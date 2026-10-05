# ════════════════════════════════════════════════════════════════════════
#  jasmin_unlock.ps1 私钥解析器回归测试
# ════════════════════════════════════════════════════════════════════════
#  背景：ConvertFrom-JasminRsaPrivatePem 曾只支持 PKCS#1，而 PHP 面板
#        (keygen.php → openssl_pkey_export) 下发的是 PKCS#8，导致
#          "DER: tag mismatch, got 0x30 want 0x02"
#        解密器在真实环境下完全不可用。
#
#  本测试直接【抽取 jasmin_unlock.ps1 中的函数体】来跑，不复制实现 —— 
#  避免测试与实现各自漂移。
#
#  用法（Windows PowerShell 5.1 / PowerShell 7 / pwsh on Linux 均可）：
#     powershell -ExecutionPolicy Bypass -File test_private_key_parse.ps1
#  退出码：0=全部通过，1=存在失败
# ════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = 'Stop'

$SCRIPT = Join-Path $PSScriptRoot 'jasmin_unlock.ps1'
if (-not (Test-Path -LiteralPath $SCRIPT)) { Write-Host "[X] 找不到 $SCRIPT"; exit 1 }

# ── 抽取 DER 解析函数区（Get-DerValue ... ConvertFrom-JasminRsaPrivatePem 结束）──
$src   = [IO.File]::ReadAllText($SCRIPT)
$begin = $src.IndexOf('function Get-DerValue {')
$end   = $src.IndexOf('# ── 遍历器')
if ($begin -lt 0 -or $end -lt 0 -or $end -le $begin) {
    Write-Host '[X] 无法从 jasmin_unlock.ps1 抽取解析函数区（文件结构已变？）'
    exit 1
}
Invoke-Expression $src.Substring($begin, $end - $begin)

# ── 一次性测试向量（1024-bit 临时密钥，仅供解析测试，不含任何真实资产）──
$PKCS1 = @'
-----BEGIN RSA PRIVATE KEY-----
MIICXgIBAAKBgQC3yz2AamCtpX68rPJEJZEM50mcYBpx7HLT4lz46X2x0A/FcHEo
//S0Tsuy5sbUgA3GwbKGq5EXGMJ2r7QGdE8X6H3M/A9I7O5qJCWdFLs6mBcVRYZJ
QavxQBkKYHrIMl0pg0N7k+QVQbyJxOq3AIFX2MrCLvLgEsduDyefsStU4QIDAQAB
AoGBALKvKhzFzzYjFmMSdPph13JHDh60pCEr8rsicKciQax0jlCyr6FfrqT5kjpc
+OMxl7MrL4iUFhvxW2YODiTUQOti/HfOCKf1M7vIo4dGb+a1jHU0lBbD1JVuM0tu
jL4FO2a8nlChsUuXMxa/Se5/APR2Hh6Mfm+6GCpR+WO6+vgBAkEA7ZWyxtRMm44p
Pz+lRK4OrMunIsiDMFse+dIU+TJHYH4Pr2gaxftsY6C/88ZTVq9wa/AOhbGqrIPE
h2q8y8NcQQJBAMYKMOYi6AtOIPuHo+tUBcFgFENq6lRWNlxv3LruVuOiBWFkGRS2
YOvWxvmMH8X2pVCEjjZBMhYrBdlJQKf6UKECQQDGFaa9sanBlDB9pGH1ti1UEmPi
U01V1tMntOl5r1rlb5VCSMjxwqNnGVKRPAyl3JYd2EMzYqMLPL1xriOEu/hBAkBR
Y6LREgt3ifZ4KTiu4Gs1G/1375q6amwQ9VAr6wP+rXm0muTL5GBUzIId0P7F5yXt
v2yK06R4A9p1gGt4HaHBAkEAtpMncVjxMRv2xtNjzxTYH5nmOvLXEsRz41RIPcL1
Y7vFqMEd1+7JbjxlKLc+p9CRgHQj/CZCtb0BbwtnnQU81g==
-----END RSA PRIVATE KEY-----
'@
$PKCS8 = @'
-----BEGIN PRIVATE KEY-----
MIICeAIBADANBgkqhkiG9w0BAQEFAASCAmIwggJeAgEAAoGBALfLPYBqYK2lfrys
8kQlkQznSZxgGnHsctPiXPjpfbHQD8VwcSj/9LROy7LmxtSADcbBsoarkRcYwnav
tAZ0Txfofcz8D0js7mokJZ0UuzqYFxVFhklBq/FAGQpgesgyXSmDQ3uT5BVBvInE
6rcAgVfYysIu8uASx24PJ5+xK1ThAgMBAAECgYEAsq8qHMXPNiMWYxJ0+mHXckcO
HrSkISvyuyJwpyJBrHSOULKvoV+upPmSOlz44zGXsysviJQWG/FbZg4OJNRA62L8
d84Ip/Uzu8ijh0Zv5rWMdTSUFsPUlW4zS26MvgU7ZryeUKGxS5czFr9J7n8A9HYe
Hox+b7oYKlH5Y7r6+AECQQDtlbLG1Eybjik/P6VErg6sy6ciyIMwWx750hT5Mkdg
fg+vaBrF+2xjoL/zxlNWr3Br8A6Fsaqsg8SHarzLw1xBAkEAxgow5iLoC04g+4ej
61QFwWAUQ2rqVFY2XG/cuu5W46IFYWQZFLZg69bG+YwfxfalUISONkEyFisF2UlA
p/pQoQJBAMYVpr2xqcGUMH2kYfW2LVQSY+JTTVXW0ye06XmvWuVvlUJIyPHCo2cZ
UpE8DKXclh3YQzNiows8vXGuI4S7+EECQFFjotESC3eJ9ngpOK7gazUb/Xfvmrpq
bBD1UCvrA/6tebSa5MvkYFTMgh3Q/sXnJe2/bIrTpHgD2nWAa3gdocECQQC2kydx
WPExG/bG02PPFNgfmeY68tcSxHPjVEg9wvVju8WowR3X7sluPGUotz6n0JGAdCP8
JkK1vQFvC2edBTzW
-----END PRIVATE KEY-----
'@

$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host ("  [PASS] " + $name + $(if ($detail) { "  ($detail)" } else { '' })) -ForegroundColor Green }
    else     { Write-Host ("  [FAIL] " + $name + "  $detail") -ForegroundColor Red; $script:fail++ }
}

# 跨平台取一个「支持 OAEP-SHA256 的 RSA 实现」：Windows 上优先 RSACng（与脚本一致）
function New-RsaImpl {
    # Windows 上用 RSACng（与 jasmin_unlock.ps1 主流程一致）；其余平台回退 RSA::Create()。
    # 不用 $IsWindows —— PowerShell 5.1 无此变量。
    try { return (New-Object System.Security.Cryptography.RSACng) }
    catch { return [System.Security.Cryptography.RSA]::Create() }
}

Write-Host ''
Write-Host '=== jasmin_unlock.ps1 私钥解析器回归测试 ===' -ForegroundColor Cyan

foreach ($case in @(
    @{ Name = 'PKCS#1 (BEGIN RSA PRIVATE KEY)'; Pem = $PKCS1 },
    @{ Name = 'PKCS#8 (BEGIN PRIVATE KEY)';     Pem = $PKCS8 }
)) {
    Write-Host ("* " + $case.Name)
    try {
        $ps = ConvertFrom-JasminRsaPrivatePem -Pem $case.Pem
    } catch {
        Check '解析' $false $_.Exception.Message
        continue
    }
    Check '解析成功' $true

    $hasAll = ($null -ne $ps.Modulus) -and ($null -ne $ps.Exponent) -and ($null -ne $ps.D) -and
              ($null -ne $ps.P) -and ($null -ne $ps.Q) -and
              ($null -ne $ps.DP) -and ($null -ne $ps.DQ) -and ($null -ne $ps.InverseQ)
    Check '8 个 CRT 参数齐全' $hasAll

    $rsa = New-RsaImpl
    try { $rsa.ImportParameters($ps) } catch { Check 'ImportParameters' $false $_.Exception.Message; continue }
    Check 'ImportParameters' $true ("RSA-" + $rsa.KeySize)

    # 真实 OAEP-SHA256 闭环：证明解析出的密钥材料可用（而非只是"结构对"）
    $msg  = [Text.Encoding]::UTF8.GetBytes('jasmin-parser-selftest')
    $ct   = $rsa.Encrypt($msg, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
    $pt   = $rsa.Decrypt($ct, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
    Check 'OAEP-SHA256 加解密闭环' ([Text.Encoding]::UTF8.GetString($pt) -ceq 'jasmin-parser-selftest') ("ct=" + $ct.Length + "B")
}

Write-Host '* 负向用例'
$threw = $false
try { [void](ConvertFrom-JasminRsaPrivatePem -Pem "-----BEGIN PRIVATE KEY-----`nAAAA`n-----END PRIVATE KEY-----") }
catch { $threw = $true }
Check '乱码输入被拒绝而非静默通过' $threw

Write-Host ''
if ($fail -eq 0) { Write-Host '=== 全部通过 ===' -ForegroundColor Green; exit 0 }
else { Write-Host ("=== 失败 " + $fail + " 项 ===") -ForegroundColor Red; exit 1 }
