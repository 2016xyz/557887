# Jasmin C2 — 集群部署指南

## 架构

```
Client → Nginx(8080/5000) → PHP×N / Python×N
                ↓                    ↓
              Redis ←── Session ──→ MySQL
```

## 快速启动

```bash
cd docker
export GIT_TOKEN=your_token
docker compose -f docker-compose.cluster.yml up -d --build
```

## 扩容

```bash
# PHP扩到4副本, Python扩到3副本
docker compose -f docker-compose.cluster.yml up -d --scale php=4 --scale python=3
```

## 组件说明

| 组件 | 作用 | 可扩展 |
|------|------|--------|
| Nginx | 负载均衡, 反代 | 单实例 |
| Redis | Session共享 | 单实例(可换Sentinel) |
| MySQL | 数据库 | 单实例(可换主从) |
| PHP | Web后台 | ✅ 水平扩展 |
| Python | API后台 | ✅ 水平扩展 |

## 共享存储

- `shared_payloads` — 载荷+密钥, PHP和Python共享
- `shared_passwords` — 受害者密码文件

生产环境建议替换为NFS/MinIO/S3。

## 环境变量

通过 `.env` 文件或命令行设置:

```env
MYSQL_ROOT_PASSWORD=xxx
MYSQL_DATABASE=jasmin_db
MYSQL_USER=jasminadmin
MYSQL_PASSWORD=xxx
HANDSHAKE_SECRET=xxx
GIT_TOKEN=xxx
```

## 端口

- 8080 → PHP后台 (通过Nginx)
- 5000 → Python后台 (通过Nginx)
