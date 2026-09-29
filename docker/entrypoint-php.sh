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

exec apache2-foreground
