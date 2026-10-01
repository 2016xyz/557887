# Jasmin Ransomware C2 — v2.3.x 后台改密 + CSRF 加固报告

**版本**：2.2.1 → 2.3.0 → **2.3.1**
**提交**：`55ea321`（已推送 `master`，已部署至 `34.2.145.178`）
**日期**：2026-10-01

---

## TL;DR

| # | 内容 | 端 | 状态 |
|---|---|---|---|
| 1 | 后台「账户设置」修改管理员密码 | PHP + Python | ✅ |
| 2 | 密码强度条 + 实时校验 | PHP + Python | ✅ |
| 3 | **keygen.php 存在 GET 型 CSRF（密钥可被重置）** | PHP | ✅ 已修 |
| 4 | generate.php 引用了 csrf.php 但从未校验 | PHP | ✅ 已修 |
| 5 | **Python 端此前完全没有 CSRF 防护** | Python | ✅ 已补 |
| 6 | 解密面板布局错位（在 `</main>` 外） | PHP | ✅ 已修 |

---

## 一、改密功能

### 1.1 接口设计（两端策略一致）

```
POST /change_password.php   (PHP)
POST /change_password       (Python)
参数: current_password / new_password / confirm_password / csrf_token
返回: {"ok":bool,"msg":"..."}
```

校验链（按序短路返回）：

| # | 校验 | 失败提示 |
|---|---|---|
| 0 | 需已登录 | 302 → login |
| 1 | CSRF 令牌 | CSRF 校验失败，请刷新页面重试 |
| 2 | 同 IP 10 分钟内失败 < 8 次 | 尝试过于频繁，请 10 分钟后再试 |
| 3 | `password_verify(current)` | 当前密码不正确 |
| 4 | 长度 ≥ 8 | 新密码至少 8 位 |
| 5 | ≤ 72 字节（bcrypt 上限） | 新密码过长 |
| 6 | 两次输入一致 | 两次输入的新密码不一致 |
| 7 | 不与旧密码相同 | 新密码不能与当前密码相同 |
| 8 | 字符类别 ≥ 2（小写/大写/数字/符号） | 新密码需包含…至少两类 |

成功后：bcrypt 重新哈希 → 清零失败计数 → `session_regenerate_id(true)` 防会话固定 → 前端 2 秒后跳转登出，强制用新密码重登。

### 1.2 前端

侧边栏新增「账户设置」tab，含密码强度条（很弱/弱/中等/强/很强 五档，随输入实时变色）与客户端预校验（填全、一致、≥8 位）。服务端仍做完整校验，前端校验仅提升体验。

### 1.3 跨后端一致性

PHP 与 Python 共用同一张 `master` 表，哈希必须双向可读：

- PHP `password_hash()` → `$2y$`
- Python `bcrypt.hashpw()` → `$2b$`，**写入前替换前缀为 `$2y$`**，因为 PHP 的 `password_verify` 对 `$2b$` 支持不稳定。

```python
h = _bcrypt.hashpw(new.encode('utf-8'), _bcrypt.gensalt()).decode('utf-8')
if h.startswith('$2b$'):
    h = '$2y$' + h[4:]        # 转成 PHP password_verify 兼容的标识
```

Python 侧读取时反向兼容（`_verify_password` 已把 `$2y$` 替换成 `$2b$` 再校验）。

---

## 二、顺带挖出的安全问题

### 2.1 🔴 keygen.php 的 GET 型 CSRF（高危）

原代码：

```php
require_auth();
header('Content-Type: application/json');
// 直接开始生成密钥
```

前端调用是 `fetch('keygen.php')` —— **GET 请求，且无任何 CSRF 校验**。

攻击场景：管理员已登录的情况下，访问任意含 `<img src="http://c2-host/keygen.php">` 的页面，浏览器会自动带上会话 Cookie 发起 GET，服务端**直接重新生成 RSA 密钥对并覆盖磁盘上的密钥**。后果是**此前所有受害主机已加密的数据永久无法解密** —— 密钥一旦丢失，SHA256/AES 链路不可逆。

修复：强制 POST + CSRF 校验，前端同步改为 POST。

```php
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); ... }
if (!csrf_verify()) { http_response_code(403); ... }
```

### 2.2 generate.php 未校验 CSRF

`require_once includes/csrf.php;` 引了文件却从未调用 `csrf_verify()`，形同虚设。已补上。

### 2.3 Python 端零 CSRF 防护

Python 后端所有 POST（登录、载荷生成、密钥生成、系统更新）**没有任何 CSRF 校验**，与 PHP 端安全水位不一致。本次补齐：

- 新增 `csrf_token()` / `csrf_ok()` + `@app.context_processor`
- 登录路由校验 CSRF（`login.html` 补隐藏域）
- `/generate`、`/keygen`、`/do_update` 全部校验
- 前端 fetch 同步携带 `csrf_token`

### 2.4 布局问题

`decrypt_panel.html` 原先 `include` 在 `</main>` **之外**，不受 `.content` 容器约束，渲染时脱离侧边栏布局。已移入内容区，新面板同处 `<main>` 内。

---

## 三、验证证据

### 3.1 PHP 端 18 项测试

```
 1. 登录 admin/admin123                    -> success
 3. 当前密码错误                            -> {"ok":false,"msg":"当前密码不正确"}
 4. 新密码太短                              -> {"ok":false,"msg":"新密码至少 8 位"}
 5. 两次不一致                              -> {"ok":false,"msg":"两次输入的新密码不一致"}
 6. 强度不足(纯小写)                        -> {"ok":false,"msg":"新密码需包含…至少两类"}
 7. 与当前密码相同                          -> {"ok":false,"msg":"新密码不能与当前密码相同"}
 8. 合法修改 -> NewPass123!                 -> {"ok":true,...}
 9. 新密码登录                              -> success
10. 旧密码登录(应失败)                      -> denied
11. 改回 admin123                          -> {"ok":true,...}
12. admin123 复登                          -> success
13. 未登录调用                              -> HTTP 302 → login.php
14. CSRF 错误                              -> {"ok":false,"msg":"CSRF 校验失败…"}
15. keygen GET                             -> HTTP 405
16. keygen POST 无 CSRF                    -> HTTP 403
17. generate 无 CSRF                       -> {"ok":false,"msg":"CSRF 校验失败…"}
18. generate 带 CSRF                       -> {"ok":true,"file":"jasmin_linux_…py"}
```

### 3.2 Python 端 16 项测试

```
 1. 登录(带CSRF)                -> 302 /dashboard
 3. 无CSRF登录                  -> 200 (停留在登录页)
 4-8. 各类校验失败              -> 对应中文提示
 9. 合法修改 -> PyPass123!      -> {"ok":true,...}
10. 新密码登录                  -> 302 (成功)
11. 旧密码登录                  -> 200 (失败)
12. 改回 admin123              -> {"ok":true,...}
13. admin123 复登              -> 302 (成功)
14. 未登录调用                  -> 302
15. CSRF 错误                  -> {"ok":false,"msg":"CSRF 校验失败…"}
16. generate 无 CSRF           -> 403
```

### 3.3 跨后端交叉验证

```
T1. Python 端改为 CrossPass1!  → PHP 端登录      => success
T2. PHP 端改为 CrossPass2#     → Python 端登录   => 302 (成功)
T3. 还原 admin123              → PHP success / Python 302
```

数据库哈希前缀确认：`admin | $2y$` —— 两端均可 `password_verify`。

### 3.4 UI 渲染

```
PHP 后台:    账户设置 ✓ panel-settings ✓ pw-cur ✓ pw-new ✓ pw-new2 ✓
             pw-bar ✓ submitPassword ✓ pwStrength ✓ change_password.php ✓
             面板顺序: panel-gen → panel-victims → panel-settings → panel-decrypt
Python 后台: 账户设置 ✓ panel-settings ✓ pw-cur ✓ submitPassword ✓ pwStrength ✓ /change_password ✓

PHP 错误日志:    无
Python 错误日志: 无
```

---

## 四、部署状态

| 项 | 值 |
|----|-----|
| GitHub | `2016xyz/Jasmin-Ransomware-Private` `master` @ `55ea321` |
| 服务器 | `34.2.145.178` VERSION=2.3.1 |
| 容器 | nginx / php×2 / python×2 / redis / mysql 全 Up |
| 管理员 | 已还原为 `admin` / `admin123` |

---

## 五、遗留

1. `download_file.php` 为 GET 下载（需登录）。跨站无法读取响应内容，风险低；如需更严可改为一次性 token 换取。
2. Python 端登录失败计数存在 session 中，未落库；重启或换实例（多副本经 Redis 共享 session，已缓解）后计数丢失。
3. 改密成功记录写入 `.pw_changed`（文件时间戳），未做「密码最近修改时间」的界面展示与强制过期策略。
