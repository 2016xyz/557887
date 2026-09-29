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

# Auto-create default admin if master table is empty
php -r '
$p=new PDO("mysql:host='${DB_HOST:-db}';port='${DB_PORT:-3306}';dbname='${DB_NAME:-jasmin_db}'","'${DB_USER:-jasminadmin}'","'${DB_PASS:-jasmin_secure_pw}'");
$c=(int)$p->query("SELECT COUNT(*) FROM master")->fetchColumn();
if($c===0){
  $h=password_hash("admin123",PASSWORD_BCRYPT);
  $s=$p->prepare("INSERT INTO master(admin,creds)VALUES(?,?)");
  $s->execute(["admin",$h]);
  echo "[entrypoint] default admin created (admin/admin123)\n";
}
' 2>/dev/null

exec apache2-foreground
