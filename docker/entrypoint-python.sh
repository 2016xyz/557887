#!/bin/bash
# Auto-create config.json from Docker environment
CFG=/app/config.json
if [ ! -f "$CFG" ]; then
python3 -c "
import json
cfg={'database_url':'mysql+pymysql://${DB_USER:-jasminadmin}:${DB_PASS:-jasmin_secure_pw}@${DB_HOST:-db}:${DB_PORT:-3306}/${DB_NAME:-jasmin_db}','handshake_secret':'${HANDSHAKE_SECRET:-jasmin@123}','installed':True}
open('$CFG','w').write(json.dumps(cfg))
print('[entrypoint] config.json created')
"
fi
exec gunicorn -b 0.0.0.0:5000 app:app
