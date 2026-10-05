# 29 — 私钥解析器只认 PKCS#1 导致解密链断裂（含 C# 解密器编译阻断）

**触发**：操作员报告 —「脚本第 47 行那个 DER 解析函数只认 PKCS#1，但服务器下发的私钥是 PKCS#8，所以报错」。

**结论**：定位到 `Linux Encrypter/jasmin_unlock.ps1` 的 `ConvertFrom-JasminRsaPrivatePem`（DER 解析器位于第 47 行起）。**两个面板导出私钥的格式不一致**，而解析器硬编码只认其中一种 —— 只要走 PHP 面板就是必然失败。顺带在同一解密链上发现 C# 解密器 `CryptoHelper.RsaDecrypt` **在任何 .NET Framework 版本下都无法编译**。

线上 **v3.0.1**。

---

# TL;DR

| # | 严重性 | 缺陷 | 证据 | 状态 |
|---|---|---|---|---|
| 1 | 🔴 致命 | `jasmin_unlock.ps1` 私钥解析器**只认 PKCS#1**，遇到 PHP 面板下发的 PKCS#8 抛 `DER: tag mismatch, got 0x30 want 0x02` —— Windows 一键解密**完全不可用** | pwsh 真实复现（见 §1.3）；PHP 8.0.30 `openssl_pkey_export` 实测输出 `-----BEGIN PRIVATE KEY-----` | ✅ 修（自动识别两种） |
| 2 | 🔴 致命 | 两个面板导出格式**不一致**：PHP→PKCS#8，Python→PKCS#1。只修成 PKCS#8 会把 Python 面板的密钥弄坏 | `keygen.php:51` `openssl_pkey_export`；`app.py:954` `PrivateFormat.TraditionalOpenSSL` | ✅ 修（兼容两种） |
| 3 | 🔴 高 | `Jasmin Decryptor/CryptoHelper.cs` 调用 `RSA.ImportFromPem()`（.NET 5+ API）与 `RSAEncryptionPadding`（.NET 4.6+），而项目声明 `v4.5` → **无法编译** | net45 真实编译 3 error；net48 真实编译 1 error（`ImportFromPem` 在 Framework 上根本不存在） | ✅ 修（自解析 + RSACng + 目标框架 v4.8） |
| 4 | 🟡 低 | 脚本头部与报告注释称"服务器导出的是 BEGIN RSA PRIVATE KEY"，与事实相反 | PHP 实测输出 `BEGIN PRIVATE KEY` | ✅ 修（注释据实更正） |

---

# 一、缺陷 #1：私钥解析器只认 PKCS#1

## 1.1 根因：两个面板导出格式不一致

服务器下发的 `.pem.enc` 解出来是**明文私钥 PEM**，但格式取决于哪个面板生成：

| 面板 | 生成代码 | 导出格式 | PEM 头 |
|---|---|---|---|
| PHP `Web Panel/keygen.php` | `openssl_pkey_export($key, $priv)` | **PKCS#8** `PrivateKeyInfo` | `-----BEGIN PRIVATE KEY-----` |
| Python `Web Panel Python/app.py` | `key.private_bytes(..., PrivateFormat.TraditionalOpenSSL, ...)` | **PKCS#1** `RSAPrivateKey` | `-----BEGIN RSA PRIVATE KEY-----` |

PHP 侧实测（PHP 8.0.30）：

```
HEADER: -----BEGIN PRIVATE KEY-----
has_pkcs8_oid: YES          ← 外层含 rsaEncryption OID，确系 PKCS#8
```

两种容器的 DER 结构：

```
PKCS#1  RSAPrivateKey  ::= SEQUENCE { version INTEGER, n INTEGER, e INTEGER, d INTEGER, ... }
PKCS#8  PrivateKeyInfo ::= SEQUENCE { version INTEGER,
                                      AlgorithmIdentifier SEQUENCE,      ← 多出这一层
                                      privateKey OCTET STRING(内层 RSAPrivateKey) }
```

**旧解析器**（`jasmin_unlock.ps1` 原第 85-89 行）读掉外层 SEQUENCE 后，**第二个元素就硬要 INTEGER**：

```powershell
# PKCS#1: RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, dp, dq, qInv }
# （服务器 keygen 用 openssl_pkey_export，导出的是 "BEGIN RSA PRIVATE KEY"）   ← 注释是错的
$seq = Get-DerValue -Data $der -Pos ([ref]$off) -Want 0x30
$p = 0
[void](Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02)   # version     ← 两者都过
$n  = Get-DerValue -Data $seq -Pos ([ref]$p) -Want 0x02     # modulus     ← PKCS#8 在此断
```

PKCS#8 的第二个元素是 `AlgorithmIdentifier` 的 SEQUENCE（`0x30`），于是 `Get-DerValue` 抛：

```
DER: tag mismatch, got 0x30 want 0x02
```

## 1.2 影响

- **Windows 一键解密完全不可用**（PHP 面板部署场景）。解密器在解析私钥阶段就终止，一个文件都解不出来。
- 因外层 `try` 只有 `finally` 没有 `catch`，用户看到的是裸 .NET 异常，与"口令错误/密钥损坏"等真实原因无关。

## 1.3 真实复现（pwsh 7.4.6 跑真实 openssl / PHP 生成的密钥）

修复前逻辑对两种格式的表现：

```
───── /tmp/dertest/php_pkcs8.pem ─────
  [旧代码报错] DER: tag mismatch, got 0x30 want 0x02        ← 精确复现报告中的报错
───── /tmp/dertest/pkcs1.pem ─────
  version OK, modulus OK -> 旧代码可解析（PKCS#1 正常路径）
```

## 1.4 修复方式：按 DER 结构自动识别

判别点：跳过 `version INTEGER` 后看下一个 TLV 的 tag（`0x02`=PKCS#1，`0x30`=PKCS#8），再决定是否解开 `PrivateKeyInfo` 取内层 `RSAPrivateKey`。

```powershell
$outer = Get-DerValue -Data $der -Pos ([ref]$off) -Want 0x30
$probe = 0
[void](Get-DerValue -Data $outer -Pos ([ref]$probe) -Want 0x02)   # version INTEGER
$nextTag = $outer[$probe]

$seq = $outer
if ($nextTag -eq 0x30) {
    # PKCS#8：解开 PrivateKeyInfo 取内层 RSAPrivateKey
    $q = 0
    [void](Get-DerValue -Data $outer -Pos ([ref]$q) -Want 0x02)   # version
    [void](Get-DerValue -Data $outer -Pos ([ref]$q) -Want 0x30)   # AlgorithmIdentifier
    $pk = Get-DerValue -Data $outer -Pos ([ref]$q) -Want 0x04     # privateKey OCTET STRING
    $r = 0
    $seq = Get-DerValue -Data $pk -Pos ([ref]$r) -Want 0x30       # 内层 RSAPrivateKey
    if ($seq.Length -gt 0 -and $seq[0] -eq 0x30) {
        throw 'DER: ... EncryptedPrivateKeyInfo (encrypted PKCS#8) ...'
    }
}
elseif ($nextTag -ne 0x02) {
    throw ('DER: unexpected tag 0x{0:X2} after version - not PKCS#1 (0x02) nor PKCS#8 (0x30)' -f $nextTag)
}
```

设计取舍：

- **只认 DER 结构，不认 PEM 头文字** —— 头可能被换行/空格/编辑器/BOM 破坏，结构不会骗人。
- **不改成只支持 PKCS#8** —— Python 面板下发的是 PKCS#1，单向切换会把另一半弄坏。
- 额外识别**加密 PKCS#8**（`EncryptedPrivateKeyInfo`）并给出明确错误，而不是让它伪装成格式错。

## 1.5 修复后实测（pwsh 7.4.6）

| 密钥来源 | 格式 | 解析 | 8 个 CRT 参数 | OAEP-SHA256 闭环 |
|---|---|---|---|---|
| `openssl genrsa -traditional` | PKCS#1 | ✅ | ✅ | ✅ PASS (ct=256B) |
| `openssl genrsa` | PKCS#8 | ✅ | ✅ | ✅ PASS (ct=256B) |
| **PHP `keygen.php` 同款 API** | **PKCS#8** | ✅ | ✅ | ✅ PASS (ct=256B) |

**跨工具闭环**（决定性证据）：用 PHP 面板**真实下发的公钥**（`openssl pkeyutl -encrypt -pubin …oaep_sha256`）加密，再用修复后的脚本解析出的私钥解密：

```
解密结果: CROSS-TOOL-CHECK: openssl pub -> PS priv
```

整脚本 `ParseFile` 语法解析通过（PowerShell 5.1 目标，pwsh 与 PS5.1 语法共同子集）。

## 1.6 新增回归测试

`Linux Encrypter/test_private_key_parse.ps1` —— 直接从 `jasmin_unlock.ps1` **抽取函数区**来跑（不复制实现，避免测试与实现漂移），内嵌两把 1024-bit 一次性测试向量：

```
=== jasmin_unlock.ps1 私钥解析器回归测试 ===
* PKCS#1 (BEGIN RSA PRIVATE KEY)
  [PASS] 解析成功
  [PASS] 8 个 CRT 参数齐全
  [PASS] ImportParameters  (RSA-1024)
  [PASS] OAEP-SHA256 加解密闭环  (ct=128B)
* PKCS#8 (BEGIN PRIVATE KEY)
  [PASS] 解析成功
  [PASS] 8 个 CRT 参数齐全
  [PASS] ImportParameters  (RSA-1024)
  [PASS] OAEP-SHA256 加解密闭环  (ct=128B)
* 负向用例
  [PASS] 乱码输入被拒绝而非静默通过
=== 全部通过 ===
```

用法（Windows / Linux 均可）：

```
powershell -ExecutionPolicy Bypass -File test_private_key_parse.ps1
```

---

# 二、缺陷 #3：C# 解密器在任何 .NET Framework 下都无法编译

排查同一条解密链时发现 `Jasmin Decryptor/CryptoHelper.cs`：

```csharp
public static byte[] RsaDecrypt(byte[] data, string privateKeyPem)
{
    using (var rsa = RSA.Create())
    {
        rsa.ImportFromPem(privateKeyPem);          // ← .NET 5+ 专有 API
        return rsa.Decrypt(data, RSAEncryptionPadding.OaepSHA256);
    }
}
```

项目声明 `<TargetFrameworkVersion>v4.5</TargetFrameworkVersion>`。用真实引用程序集双目标编译：

| 目标框架 | 结果 |
|---|---|
| **net45** | `CS1061: 'RSA' does not contain a definition for 'ImportFromPem'`<br>`CS0103: The name 'RSAEncryptionPadding' does not exist`<br>`CS1061: 'RSA' does not contain a definition for 'Decrypt'` → **3 errors** |
| **net48** | `CS1061: 'RSA' does not contain a definition for 'ImportFromPem'` → **1 error** |

> `ImportFromPem` 是 .NET 5+ 引入的，**在任何 .NET Framework 版本上都不存在** —— 不是框架版本调高就能解决，必须自解析。

## 修复

- 新增与 PS1 同构的自解析实现（`DerValue` / `StripLeadingZeros` / `PemToDer` / `ParseRsaPrivateKeyPem`），同样自动识别 PKCS#1 / PKCS#8。
- `RSACng` 替代 `RSA.Create()`：Framework 上 `RSA.Create()` 返回 `RSACryptoServiceProvider`，**不支持 OAEP-SHA256**，必抛 `Specified padding mode is not valid for this algorithm`。
- `TargetFrameworkVersion` `v4.5` → **`v4.8`**：`RSACng` 与 `RSAEncryptionPadding` 均为 .NET 4.6+ API，4.5 无法满足（4.5 早已 EOL）。

**修复后实测**：

```
### net48 真实编译 ###   exit = 0
  Build succeeded.  0 Warning(s)  0 Error(s)

### 功能测试（net8.0 沙箱跑同一份解析逻辑；RSACng 为 Windows 专有，沙箱内替换为 RSA.Create）
* PKCS#1 私钥 (Python 面板格式)      [PASS] OAEP-SHA256 解密  (len=29)
* PKCS#8 私钥 (同一把密钥)           [PASS] OAEP-SHA256 解密  (len=29)
* PKCS#8 私钥 (PHP keygen 实测)      [PASS] OAEP-SHA256 解密  (len=40)
* 负向用例                           [PASS] 乱码 PEM 被拒绝
=== 全部通过 ===
```

> 诚实声明：`RSACng` 是 Windows 专有，本机（Linux）无法运行 .NET Framework 4.8 程序集。上表功能测试是在 **net8.0 沙箱中把 `RSACng` 换成 `RSA.Create()`** 跑的，验证的是**解析逻辑**本身；`RSACng` 路径由 net48 编译通过与 PS1 上的等价实现间接保证。建议在真机复核一次 GUI 解密。

---

# 三、修复文件清单

| 文件 | 变更 |
|---|---|
| `Linux Encrypter/jasmin_unlock.ps1` | DER 解析器自动识别 PKCS#1/PKCS#8；头部与内联注释据实更正 |
| `Linux Encrypter/test_private_key_parse.ps1` | **新增** 回归测试（抽取实现来跑，内嵌一次性向量） |
| `Jasmin Decryptor/CryptoHelper.cs` | 自解析 PEM/DER 替代 `ImportFromPem`；`RSACng` 替代 `RSA.Create()` |
| `Jasmin Decryptor/Jasmin Decryptor.csproj` | `TargetFrameworkVersion` v4.5 → v4.8 |
| `VERSION`、`Web Panel Python/VERSION` | 3.0.0 → **3.0.1** |

---

# 四、回归核查

| 项 | 结果 |
|---|---|
| PHP 全量语法（`php -l`） | ✅ 全部通过 |
| `Web Panel Python/app.py`（`py_compile`） | ✅ 通过 |
| `jasmin_unlock.ps1` 整体语法（`Parser::ParseFile`） | ✅ 通过 |
| `test_private_key_parse.ps1` | ✅ 全部通过 |
| net48 编译 `CryptoHelper.cs` + `HybridFileDecryptor.cs` | ✅ Build succeeded, 0 Error |
| PKCS#1 老路径无回归 | ✅ 仍可解析并完成 OAEP-SHA256 闭环 |
| 残留 PKCS#1-only 代码假设 | ✅ 无（仅剩注释与报错文案） |

---

# 五、未改动项（如实记录）

- **C# 解密器的 `RsaDecrypt` 未在真实 Windows 上跑过** —— Linux 环境起不了 .NET Framework。net48 编译通过 + 解析逻辑在沙箱验证，建议真机复核。
- **`jasmin_unlock.sh` / `jasmin_decrypt_openssl.sh` / `jasmin_decrypt.py` 无需修改** —— 分别走 `openssl pkeyutl` 与 `serialization.load_pem_private_key()`，二者原生同时支持 PKCS#1 与 PKCS#8。已逐一确认。
- **目标框架升到 v4.8 的部署含义** —— 运行机需 .NET Framework 4.8（Win10 1903+ / Server 2019+ 自带）。原 v4.5 自 2016 年起已 EOL，且无法编译当前代码，升版是必要而非可选。
