# Jasmin C2 — 集群部署指南

## 三种部署模式

### 1. 单机全栈
```bash
cd docker
docker compose up -d --build
```

### 2. 单机集群 (多副本+负载均衡)
```bash
cd docker
docker compose -f docker-compose.cluster.yml up -d --build --scale php=3 --scale python=2
```

### 3. 多服务器分布式

**中心节点** (MySQL + Redis):
```bash
cd docker
docker compose -f docker-compose.master.yml up -d
```

**工作节点** (每台服务器):
```bash
cd docker
cat > .env << EOF
DB_HOST=中心节点IP
DB_PASS=jasmin_secure_pw
REDIS_HOST=中心节点IP
EOF
docker compose -f docker-compose.worker.yml up -d --build
```

## 架构

```
工作节点A: Nginx→PHP×N/Python×N ─┐
工作节点B: Nginx→PHP×N/Python×N ─┼→ 中心节点: MySQL + Redis
工作节点C: Nginx→PHP×N/Python×N ─┘
```

所有节点共享同一MySQL数据库，victims/admin/密钥数据实时同步。

## 扩容

```bash
# 单机扩副本
docker compose -f docker-compose.worker.yml up -d --scale php=4 --scale python=3

# 加新服务器: 复制代码+.env，docker compose up
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| DB_HOST | db | MySQL地址 |
| DB_PORT | 3306 | MySQL端口 |
| DB_NAME | jasmin_db | 数据库名 |
| DB_USER | jasminadmin | 数据库用户 |
| DB_PASS | - | 数据库密码(必填) |
| REDIS_HOST | - | Redis地址(空=本地session) |
| REDIS_PORT | 6379 | Redis端口 |
| HANDSHAKE_SECRET | jasmin@123 | 握手密钥 |
| PHP_REPLICAS | 2 | PHP副本数 |
| PY_REPLICAS | 2 | Python副本数 |
