#!/bin/bash
# Auto-create config.json from Docker environment
CFG=/app/config.json
if [ ! -f "$CFG" ]; then
python3 <<'PY'
import json, os, secrets
u = os.environ.get('DB_USER', 'jasminadmin')
p = os.environ.get('DB_PASS', '')
from urllib.parse import quote_plus
cfg = {
    'database_url': 'mysql+pymysql://%s:%s@%s:%s/%s?charset=utf8mb4' % (
        quote_plus(u), quote_plus(p),
        os.environ.get('DB_HOST', 'db'), os.environ.get('DB_PORT', '3306'),
        os.environ.get('DB_NAME', 'jasmin_db')),
    'handshake_secret': os.environ.get('HANDSHAKE_SECRET', 'jasmin@123'),
    'installed': True,
    # SECRET_KEY 必须每个部署各自随机 —— 镜像里写死的密钥等于公开的会话签名密钥
    'secret_key': secrets.token_hex(32),
    'redis_host': os.environ.get('REDIS_HOST', ''),
    'redis_port': int(os.environ.get('REDIS_PORT', '6379')),
}
open('/app/config.json', 'w').write(json.dumps(cfg))
print('[entrypoint] config.json created (secret_key 随机生成)')
PY
fi

# ── 创建管理员 ──
# 此前 config.json 直接写 installed=True 却从不建号，导致单独部署 Python 后端时
# 没有任何账号可登录（安装向导也因 installed 被跳过）。
# 这里从环境变量取口令；未设置则跳过并明确告警。
# 哈希统一用 bcrypt($2y$) —— 与 PHP 端共用同一张 master 表，两端都要能验证通过。
# ★ 管理员已在后台改过口令就跳过建号 —— 否则每次容器重建都会
# DELETE + INSERT 把口令重置回 ADMIN_PASSWORD（与 PHP entrypoint 同一问题）。
PW_MARK=/app/payloads/.pw_changed
if [ -f "$PW_MARK" ]; then
  echo "[entrypoint] 检测到 $PW_MARK —— 跳过建号（不覆盖管理员已改的口令）"
  ADMIN_PASSWORD=""
fi

if [ -n "$ADMIN_PASSWORD" ]; then
  for i in $(seq 1 15); do
    if python3 <<'PY' 2>/dev/null
import json, os, bcrypt
from sqlalchemy import create_engine, text
cfg = json.load(open('/app/config.json'))
u = os.environ.get('ADMIN_USER', 'admin')
p = os.environ['ADMIN_PASSWORD']
e = create_engine(cfg['database_url'])
h = bcrypt.hashpw(p.encode('utf-8'), bcrypt.gensalt(rounds=10, prefix=b'2y')).decode('utf-8')
with e.begin() as c:
    c.execute(text("SELECT 1"))                 # 先确认表已就绪
    c.execute(text("DELETE FROM master WHERE admin=:u"), {'u': u})
    c.execute(text("INSERT INTO master (admin,creds) VALUES (:u,:p)"), {'u': u, 'p': h})
print('[entrypoint] admin ready')
PY
    then
      echo "[entrypoint] admin ready"
      break
    fi
    echo "[entrypoint] waiting for DB/master table ($i/15)..."
    sleep 3
  done
else
  echo "[entrypoint] !! ADMIN_PASSWORD 未设置 —— 跳过建号。"
  echo "[entrypoint] !! 若 PHP 容器已建号，可共用；否则将无人可登录。"
fi

# 解密工具：镜像烘焙在 /opt/jasmin-tools，运行时补进 shared_payloads 卷内
# (payloads/ 是 volume，镜像里 COPY 进去会被卷挂载覆盖)
if [ -d /opt/jasmin-tools ]; then
  for f in jasmin_decrypt_openssl.sh jasmin_decrypt.py jasmin_diagnose.sh jasmin_unlock.sh jasmin_unlock.ps1; do
    if [ -f "/opt/jasmin-tools/$f" ]; then
      cp -f "/opt/jasmin-tools/$f" "/app/payloads/$f"
      chmod 0644 "/app/payloads/$f" 2>/dev/null || true
      echo "[entrypoint] 部署解密工具 $f"
    fi
  done
fi

exec gunicorn -w 4 -b 0.0.0.0:5000 app:app
