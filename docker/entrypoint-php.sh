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
exec apache2-foreground
