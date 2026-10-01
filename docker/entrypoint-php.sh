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
for i in $(seq 1 15); do
  if php /var/www/html/setup.php admin123 2>/dev/null; then
    echo "[entrypoint] admin ready"
    break
  fi
  echo "[entrypoint] waiting for DB ($i/15)..."
  sleep 3
done

# 解密工具：镜像烘焙在 /opt/jasmin-tools，运行时补进 payloads 卷内
# (payloads/ 是 volume，镜像里 COPY 进去会被卷挂载覆盖)
if [ -d /opt/jasmin-tools ]; then
  for f in jasmin_decrypt_openssl.sh jasmin_decrypt.py jasmin_diagnose.sh; do
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
