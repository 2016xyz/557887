#!/bin/bash
# Auto-create .env from Docker environment
ENV_FILE=/var/www/html/.env
if [ ! -f "$ENV_FILE" ]; then
cat > "$ENV_FILE" << EOF
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-3306}
DB_NAME=${DB_NAME:-jasmin_db}
DB_USER=${DB_USER:-jasminadmin}
DB_PASS=${DB_PASS:-jasmin_secure_pw}
HANDSHAKE_SECRET=${HANDSHAKE_SECRET:-jasmin@123}
EOF
chown www-data:www-data "$ENV_FILE"
echo "[entrypoint] .env created"
fi

# Redis session (集群模式)
if [ -n "$REDIS_HOST" ]; then
cat > /usr/local/etc/php/conf.d/session-redis.ini << EOF
session.save_handler = redis
session.save_path = "tcp://${REDIS_HOST}:${REDIS_PORT:-6379}"
EOF
echo "[entrypoint] session -> redis://${REDIS_HOST}:${REDIS_PORT:-6379}"
fi

# Wait for DB schema + auto-create admin
# 口令从 ADMIN_PASSWORD 取；未设置则退回初始口令 admin123，并在日志里明确告警
# （硬编码 admin/admin123 意味着任何部署开局都是同一组可猜凭据）
ADMIN_OK=0
ADMIN_PW="${ADMIN_PASSWORD:-admin123}"
if [ -z "${ADMIN_PASSWORD:-}" ]; then
  echo "[entrypoint] !! ADMIN_PASSWORD 未设置，使用初始口令 admin123 —— 请部署后立即在后台修改"
fi

# ★ 管理员已在后台改过口令吗？
# 以前这里【每次启动都无条件】跑 setup.php → UPDATE master SET creds=...
# 于是：管理员在后台设了强口令 → 任何一次 docker restart / compose up -d /
# 宿主机重建 → 口令被静默回滚成 ADMIN_PASSWORD（未设置时就是 admin123）。
# change_password.php 早已在写 .pw_changed 标记，但从来没有任何代码读它。
# 标记放在共享卷 payloads/ 下：两个 php 副本与两个 python 副本都能看到同一份，
# 且 payloads/ 对 .开头文件有 .htaccess deny + app.py 白名单双保险。
PW_MARK=/var/www/html/payloads/.pw_changed
if [ -f "$PW_MARK" ]; then
  echo "[entrypoint] 检测到 $PW_MARK —— 管理员已自行改过口令，跳过建号（不覆盖）"
  ADMIN_OK=2
fi
for i in $(seq 1 15); do
  [ "$ADMIN_OK" = "2" ] && break
  if php /var/www/html/setup.php "$ADMIN_PW" 2>/dev/null; then
    echo "[entrypoint] admin ready"
    ADMIN_OK=1
    break
  fi
  echo "[entrypoint] waiting for DB ($i/15)..."
  sleep 3
done
# ADMIN_OK: 1=本次建号成功, 2=管理员已存在(改过口令,跳过), 0=失败
# 此前用 != "1" 判断，导致 ADMIN_OK=2（一切正常）时也误报"未能创建管理员"。
if [ "$ADMIN_OK" = "0" ]; then
  echo "[entrypoint] !! 15 次重试后仍未能创建管理员 —— 容器内可能没有任何可登录账号"
fi

# 标记安装完成。install.php 只在 .installed 不存在时才放行，
# 而 Docker 部署路径以前从不写它 —— 结果是安装向导永久暴露，
# 任何人都能 POST /install.php?step=3 抢注或覆盖管理员（已实测确认）。
# ADMIN_OK=1(新建) 或 2(已存在) 都说明有可用管理员 -> 都要确保向导关闭
if [ "$ADMIN_OK" != "0" ] && [ ! -f /var/www/html/.installed ]; then
  date '+%Y-%m-%d %H:%M:%S' > /var/www/html/.installed
  chown www-data:www-data /var/www/html/.installed 2>/dev/null || true
  chmod 0644 /var/www/html/.installed 2>/dev/null || true
  echo "[entrypoint] .installed 已写入（安装向导已关闭）"
fi

# 解密工具：镜像烘焙在 /opt/jasmin-tools，运行时补进 payloads 卷内
# (payloads/ 是 volume，镜像里 COPY 进去会被卷挂载覆盖)
if [ -d /opt/jasmin-tools ]; then
  for f in jasmin_decrypt_openssl.sh jasmin_decrypt.py jasmin_diagnose.sh jasmin_unlock.sh jasmin_unlock.ps1; do
    if [ -f "/opt/jasmin-tools/$f" ]; then
      cp -f "/opt/jasmin-tools/$f" "/var/www/html/payloads/$f"
      chmod 0644 "/var/www/html/payloads/$f" 2>/dev/null || true
      echo "[entrypoint] 部署解密工具 $f"
    fi
  done
fi

# 修复历史密钥文件权限：早期版本把密钥写成 root:root 0600，
# 而 Apache worker 是 www-data → download_file.php 的 readfile() 会因权限不足失败。
if [ -d /var/www/html/payloads ]; then
  chown -R www-data:www-data /var/www/html/payloads 2>/dev/null || true
  chmod 0755 /var/www/html/payloads 2>/dev/null || true
  for f in jasmin_private.pem jasmin_private.pem.enc jasmin_public.pem .key_secret; do
    if [ -f "/var/www/html/payloads/$f" ]; then
      chmod 0640 "/var/www/html/payloads/$f" 2>/dev/null || true
    fi
  done
  echo "[entrypoint] payloads/ 权限已修正 (owner=www-data)"
fi

exec apache2-foreground
