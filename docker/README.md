# Docker 部署指南

## 一键启动

```bash
cd docker

# 设置GitHub Token（私有仓库检查更新需要）
export GIT_TOKEN=ghp_your_token_here

docker-compose up -d
```

## 服务说明

| 服务 | 端口 | 说明 |
|------|------|------|
| PHP 后台 | http://localhost:8080 | 首次访问自动跳转安装引导 |
| Python 后台 | http://localhost:5000 | 首次访问自动跳转安装引导 |
| MySQL | localhost:3306 | user: jasminadmin / pass: jasmin_secure_pw |

## 安装引导

两个后台首次访问都会进入4步安装向导：

1. **环境检测** — 自动检查依赖
2. **数据库配置** — Docker内填写: 主机=`db`, 端口=`3306`, 用户=`jasminadmin`, 密码=`jasmin_secure_pw`, 库名=`jasmin_db`
3. **创建管理员** — 设置用户名和密码
4. **完成** — 跳转登录

## 常用命令

```bash
# 启动
docker-compose up -d

# 查看日志
docker-compose logs -f

# 停止
docker-compose down

# 重建 (代码更新后)
docker-compose up -d --build

# 清除数据重新安装
docker-compose down -v
docker-compose up -d
```

## 数据持久化

| 卷 | 说明 |
|----|------|
| mysql_data | MySQL 数据 |
| php_payloads | PHP版生成的载荷 |
| php_passwords | PHP版受害者密钥文件 |
| py_payloads | Python版生成的载荷 |

## 注意事项

- MySQL 使用 healthcheck，PHP/Python 容器会等 MySQL 就绪后再启动
- 首次启动需等 MySQL 初始化（约10-20秒）
- 不再自动导入 SQL schema，由安装引导自动建表
- 删除卷 `docker-compose down -v` 可完全重置
