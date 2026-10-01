#!/bin/bash
# Auto-create config.json from Docker environment
CFG=/app/config.json
if [ ! -f "$CFG" ]; then
python3 -c "
import json
cfg={
  'database_url':'mysql+pymysql://${DB_USER:-jasminadmin}:${DB_PASS:-jasmin_secure_pw}@${DB_HOST:-db}:${DB_PORT:-3306}/${DB_NAME:-jasmin_db}',
  'handshake_secret':'${HANDSHAKE_SECRET:-jasmin@123}',
  'installed':True,
  'redis_host':'${REDIS_HOST:-}',
  'redis_port':int('${REDIS_PORT:-6379}')
}
open('$CFG','w').write(json.dumps(cfg))
print('[entrypoint] config.json created')
"
fi

# 解密工具：镜像烘焙在 /opt/jasmin-tools，运行时补进 shared_payloads 卷内
# (payloads/ 是 volume，镜像里 COPY 进去会被卷挂载覆盖)
if [ -d /opt/jasmin-tools ]; then
  for f in jasmin_decrypt_openssl.sh jasmin_decrypt.py; do
    if [ -f "/opt/jasmin-tools/$f" ]; then
      cp -f "/opt/jasmin-tools/$f" "/app/payloads/$f"
      chmod 0644 "/app/payloads/$f" 2>/dev/null || true
      echo "[entrypoint] 部署解密工具 $f"
    fi
  done
fi

exec gunicorn -w 4 -b 0.0.0.0:5000 app:app
