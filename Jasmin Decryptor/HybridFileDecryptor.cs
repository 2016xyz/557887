using System;
using System.IO;
using System.Security.Cryptography;

namespace Jasmin_Decryptor
{
    /// <summary>
    /// 格式: [SHA256 32B][AES密文][RSA密钥块][4B长度]
    /// 解密后校验SHA256确保文件完整恢复
    /// </summary>
    public static class HybridFileDecryptor
    {
        public static string DecryptFile(string path, string privPem)
        {
            try
            {
                byte[] raw = File.ReadAllBytes(path);
                // 最小: 32(hash)+16(aes最小块)+256(rsa)+4(len)=308
                if (raw.Length < 308) return null;

                // 1. 读RSA密钥块长度
                int ekLen = BitConverter.ToInt32(raw, raw.Length - 4);
                if (ekLen <= 0 || ekLen > 512) return null;
                int ekStart = raw.Length - 4 - ekLen;
                if (ekStart <= 32) return null;

                // 2. 提取各段
                byte[] origHash = new byte[32];
                Buffer.BlockCopy(raw, 0, origHash, 0, 32);

                byte[] encKey = new byte[ekLen];
                Buffer.BlockCopy(raw, ekStart, encKey, 0, ekLen);

                int cipherLen = ekStart - 32;
                byte[] cipher = new byte[cipherLen];
                Buffer.BlockCopy(raw, 32, cipher, 0, cipherLen);

                // 3. RSA解密密钥
                byte[] km;
                try { km = CryptoHelper.RsaDecrypt(encKey, privPem); }
                catch { return null; }
                if (km.Length != 48) return null;

                byte[] aesKey = new byte[32];
                byte[] aesIV = new byte[16];
                Buffer.BlockCopy(km, 0, aesKey, 0, 32);
                Buffer.BlockCopy(km, 32, aesIV, 0, 16);

                // 4. AES解密
                byte[] plain = CryptoHelper.AesDecrypt(cipher, aesKey, aesIV);

                // 5. SHA256完整性校验
                byte[] checkHash;
                using (var sha = SHA256.Create())
                    checkHash = sha.ComputeHash(plain);

                for (int i = 0; i < 32; i++)
                    if (origHash[i] != checkHash[i])
                        return null; // 完整性校验失败

                // 6. 写回原文件
                string outPath = path.EndsWith(".jasmin",
                    StringComparison.OrdinalIgnoreCase)
                    ? path.Substring(0, path.Length - 7)
                    : path + ".dec";

                File.WriteAllBytes(outPath, plain);
                File.Delete(path);
                return outPath;
            }
            catch { return null; }
        }
    }
}
