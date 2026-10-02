#!/usr/bin/env python3
"""
Round-trip test: keygen → encrypt → decrypt → SHA256 verify
"""
import os, sys, tempfile, hashlib, struct
sys.path.insert(0, os.path.dirname(__file__))

from cryptography.hazmat.primitives.asymmetric import rsa, padding as ap
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

def pad16(d):
    n = 16 - (len(d) % 16)
    return d + bytes([n]*n)
def unpad(d):
    # 与真实实现 jasmin_decrypt.py 一致地校验 PKCS7：长度 1..16 且尾部全为该值。
    # 无校验时非法填充不会被发现，测试可能假绿。
    if not d:
        raise ValueError('empty input')
    n = d[-1]
    if n < 1 or n > 16 or len(d) < n or d[-n:] != bytes([n]) * n:
        raise ValueError('invalid PKCS7 padding')
    return d[:-n]

def test_roundtrip():
    # 1. Generate RSA-2048 keypair
    priv = rsa.generate_private_key(65537, 2048, default_backend())
    pub = priv.public_key()

    # 2. Create test file
    tmpdir = tempfile.mkdtemp()
    src = os.path.join(tmpdir, 'testfile.txt')
    content = b'Hello Jasmin Ransomware AES+RSA hybrid test! ' * 100
    with open(src, 'wb') as f:
        f.write(content)
    orig_hash = hashlib.sha256(content).digest()
    print(f'[*] Original SHA256: {orig_hash.hex()[:16]}...')

    # 3. Encrypt
    plain = open(src,'rb').read()
    sha = hashlib.sha256(plain).digest()
    aes_key = os.urandom(32)
    aes_iv = os.urandom(16)
    c = Cipher(algorithms.AES(aes_key), modes.CBC(aes_iv), default_backend())
    # 这里原本还有一行用两个【不同】encryptor 实例拼出来的密文
    # （update 与 finalize 各来自一个新实例），结果立刻被下面正确的一次覆盖 ——
    # 纯死代码，且一旦行序变动就会产出无法解密的密文，已删除。
    enc = c.encryptor()
    ct = enc.update(pad16(plain)) + enc.finalize()
    km = aes_key + aes_iv
    ek = pub.encrypt(km, ap.OAEP(mgf=ap.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    enc_path = src + '.jasmin'
    with open(enc_path, 'wb') as f:
        f.write(sha)
        f.write(ct)
        f.write(ek)
        f.write(struct.pack('<I', len(ek)))
    os.remove(src)
    print(f'[+] Encrypted: {enc_path} ({os.path.getsize(enc_path)} bytes)')

    # 4. Decrypt
    raw = open(enc_path,'rb').read()
    ek_len = struct.unpack('<I', raw[-4:])[0]
    ek_start = len(raw) - 4 - ek_len
    stored_hash = raw[:32]
    ek2 = raw[ek_start:ek_start+ek_len]
    ct2 = raw[32:ek_start]
    km2 = priv.decrypt(ek2, ap.OAEP(mgf=ap.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    aes_key2 = km2[:32]
    aes_iv2 = km2[32:]
    c2 = Cipher(algorithms.AES(aes_key2), modes.CBC(aes_iv2), default_backend())
    dec = c2.decryptor()
    recovered = unpad(dec.update(ct2) + dec.finalize())

    # 5. Verify
    rec_hash = hashlib.sha256(recovered).digest()
    print(f'[*] Recovered SHA256: {rec_hash.hex()[:16]}...')

    assert stored_hash == orig_hash, 'Stored hash mismatch!'
    assert rec_hash == orig_hash, 'Recovered content hash mismatch!'
    assert recovered == content, 'Content mismatch!'

    dec_path = enc_path[:-7]
    with open(dec_path, 'wb') as f:
        f.write(recovered)
    os.remove(enc_path)
    print(f'[+] Decrypted: {dec_path}')
    print(f'[✓] Round-trip OK — file integrity verified')

    # Cleanup
    os.remove(dec_path)
    os.rmdir(tmpdir)

if __name__ == '__main__':
    test_roundtrip()
