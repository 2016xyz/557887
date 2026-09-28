using System;
using System.ComponentModel;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace Jasmin_Decryptor
{
    public partial class mainform : Form
    {
        public mainform() { InitializeComponent(); }

        OpenFileDialog ofd = new OpenFileDialog();
        bool isKeyVerified = false;
        int totalcount = 0;
        int decryptedfiles = 0;
        string rsaPrivateKey = "";

        // 选择RSA私钥PEM文件
        async void pictureBox1_Click(object sender, EventArgs e)
        {
        recheck:
            ofd.Filter = "RSA Private Key (*.pem)|*.pem|All Files (*.*)|*.*";
            decryptbutton.Enabled = false;
            if (ofd.ShowDialog() == DialogResult.OK)
            {
                scanningicon.Visible = true;
                verifyingkey.Visible = true;
                floraicon.Visible = false;
                uppertext.Visible = false;
                invalidkeylabel.Visible = false;
                selecticon.Visible = false;

                string pemContent = File.ReadAllText(ofd.FileName);
                await System.Threading.Tasks.Task.Delay(1500);

                totalcount = filecounter();
                string result = keyverify(pemContent);

                if (result == "invalid key")
                {
                    scanningicon.Visible = false;
                    verifyingkey.Visible = false;
                    notfound.Visible = false;
                    invalidkey.Visible = true;
                    invalidkeylabel.Visible = true;
                    await System.Threading.Tasks.Task.Delay(2400);
                    goto recheck;
                }
                else if (result == "not found")
                {
                    invalidkey.Visible = false;
                    scanningicon.Visible = false;
                    verifyingkey.Visible = false;
                    verifiedlabel.Visible = false;
                    verifiedkey.Visible = false;
                    notfound.Visible = true;
                    await System.Threading.Tasks.Task.Delay(3400);
                }
                else
                {
                    invalidkey.Visible = false;
                    invalidkeylabel.Visible = false;
                    scanningicon.Visible = false;
                    verifyingkey.Visible = false;
                    notfound.Visible = false;
                    verifiedlabel.Visible = true;
                    verifiedkey.Visible = true;
                    rsaPrivateKey = pemContent;
                    await System.Threading.Tasks.Task.Delay(1400);
                    isKeyVerified = true;
                    decryptbutton.Enabled = true;
                }
            }
        }

        private void minimize_Click(object sender, EventArgs e) { WindowState = FormWindowState.Minimized; }
        private void closebutton_Click(object sender, EventArgs e) { Close(); }
        private void header_Click(object sender, EventArgs e) { }

        private void decryptbutton_Click(object sender, EventArgs e)
        {
            if (isKeyVerified)
            {
                invalidkey.Visible = false; invalidkeylabel.Visible = false;
                scanningicon.Visible = false; verifyingkey.Visible = false;
                notfound.Visible = false; verifiedlabel.Visible = false;
                verifiedkey.Visible = false;
                progressBar1.Visible = true; loadingman2.Visible = true;
                isKeyVerified = false;
                if (!backgroundWorker1.IsBusy) backgroundWorker1.RunWorkerAsync(rsaPrivateKey);
                decryptbutton.Enabled = false;
            }
            else
            {
                progressBar1.Visible = false; loadingman2.Visible = false;
                MessageBox.Show("Please load RSA private key file", "Jasmin");
                pictureBox1_Click(sender, e);
            }
        }

        // 用第一个.jasmin文件测试私钥是否匹配
        string keyverify(string pem)
        {
            string ext = "*.jasmin";
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            foreach (DriveInfo d in DriveInfo.GetDrives())
            {
                try
                {
                    if (d.Name == @"C:\") continue;
                    foreach (string dir in Directory.EnumerateDirectories(d.Name))
                        try { foreach (string f in Directory.EnumerateFiles(dir, ext, SearchOption.AllDirectories))
                            try { return TestDecrypt(f, pem); } catch { continue; }
                        } catch { continue; }
                } catch { }
            }
            foreach (string dir in Directory.EnumerateDirectories(home))
                try { foreach (string f in Directory.EnumerateFiles(dir, ext, SearchOption.AllDirectories))
                    try { return TestDecrypt(f, pem); } catch { continue; }
                } catch { continue; }
            return "not found";
        }

        string TestDecrypt(string path, string pem)
        {
            byte[] raw = File.ReadAllBytes(path);
            if (raw.Length < 4) return "not found";
            int keyLen = BitConverter.ToInt32(raw, raw.Length - 4);
            if (keyLen <= 0 || keyLen > 512 || raw.Length < keyLen + 4) return "invalid key";
            int keyStart = raw.Length - 4 - keyLen;
            byte[] encKey = new byte[keyLen];
            Buffer.BlockCopy(raw, keyStart, encKey, 0, keyLen);
            try
            {
                byte[] km = CryptoHelper.RsaDecrypt(encKey, pem);
                return km.Length == 48 ? "valid key" : "invalid key";
            }
            catch { return "invalid key"; }
        }

        private void backgroundWorker1_ProgressChanged(object sender, ProgressChangedEventArgs e)
        {
            try { progressBar1.Value = Math.Min(e.ProgressPercentage, 100); progressBar1.Update(); } catch { }
        }

        private void backgroundWorker1_DoWork(object sender, DoWorkEventArgs e)
        {
            string pem = (string)e.Argument;
            string ext = "*.jasmin";
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

            void ProcessFile(string f)
            {
                var t = new Thread(() => {
                    if (HybridFileDecryptor.DecryptFile(f, pem) != null)
                        Interlocked.Increment(ref decryptedfiles);
                }) { Priority = ThreadPriority.Highest };
                t.Start();
                Thread.Sleep(90);
                if (totalcount > 0) backgroundWorker1.ReportProgress(decryptedfiles * 100 / totalcount);
            }

            foreach (DriveInfo d in DriveInfo.GetDrives())
            {
                try
                {
                    if (d.Name == @"C:\") continue;
                    foreach (string dir in Directory.EnumerateDirectories(d.Name))
                        try { foreach (string f in Directory.EnumerateFiles(dir, ext, SearchOption.AllDirectories))
                            try { ProcessFile(f); } catch { } } catch { }
                    foreach (string f in Directory.EnumerateFiles(d.Name, ext))
                        try { ProcessFile(f); } catch { }
                } catch { }
            }
            foreach (string dir in Directory.EnumerateDirectories(home))
                try { foreach (string f in Directory.EnumerateFiles(dir, ext, SearchOption.AllDirectories))
                    try { ProcessFile(f); } catch { } } catch { }
            foreach (string f in Directory.EnumerateFiles(home, ext))
                try { ProcessFile(f); } catch { }

            backgroundWorker2.RunWorkerAsync();
            Thread.Sleep(1000);
        }

        private void backgroundWorker2_DoWork(object sender, DoWorkEventArgs e)
        {
            string alertPath = @"C:\Users\Public\Windows\Ui\";
            string startup = Environment.GetFolderPath(Environment.SpecialFolder.Startup) + @"\unlock your files.lnk";
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop) + @"\unlock your files.lnk";
            string startm  = Environment.GetFolderPath(Environment.SpecialFolder.StartMenu) + @"\unlock your files.lnk";
            try { Directory.Delete(alertPath, true); } catch { }
            foreach (string p in new[] { startup, desktop, startm })
                try { File.Delete(p); } catch { }
            foreach (DriveInfo d in DriveInfo.GetDrives())
                try { File.Delete(d.Name + @"\unlock your files.lnk"); } catch { }
        }

        private void backgroundWorker1_RunWorkerCompleted(object sender, RunWorkerCompletedEventArgs e)
        {
            totalfileslabel.Text = totalcount.ToString();
            decryptedfileslabel.Text = decryptedfiles.ToString();
            remainingfileslabel.Text = (totalcount - decryptedfiles).ToString();
            progressBar1.Visible = false;
            Thread.Sleep(1000);
            loadingman2.Visible = false;
            finalreport.Visible = true;
            totalfileslabel.Visible = true;
            decryptedfileslabel.Visible = true;
            remainingfileslabel.Visible = true;
        }

        static int filecounter()
        {
            int count = 0;
            string ext = "*.jasmin";
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            foreach (DriveInfo d in DriveInfo.GetDrives())
            {
                try
                {
                    if (d.Name == @"C:\") continue;
                    foreach (string dir in Directory.EnumerateDirectories(d.Name))
                        try { foreach (string f in Directory.EnumerateFiles(dir, ext, SearchOption.AllDirectories))
                            try { count++; } catch { } } catch { }
                    foreach (string f in Directory.EnumerateFiles(d.Name, ext))
                        try { count++; } catch { }
                } catch { }
            }
            foreach (string dir in Directory.EnumerateDirectories(home))
                try { foreach (string f in Directory.EnumerateFiles(dir, ext, SearchOption.AllDirectories))
                    try { count++; } catch { } } catch { }
            foreach (string f in Directory.EnumerateFiles(home, ext))
                try { count++; } catch { }
            return count;
        }
    }
}
