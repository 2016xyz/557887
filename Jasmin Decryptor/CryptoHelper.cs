using System;
using System.IO;
using System.Security.Cryptography;

namespace Jasmin_Decryptor
{
    public static class CryptoHelper
    {
        public static byte[] AesDecrypt(byte[] cipher, byte[] key, byte[] iv)
        {
            using (var aes = Aes.Create())
            {
                aes.KeySize = 256;
                aes.BlockSize = 128;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                aes.Key = key;
                aes.IV = iv;
                using (var ms = new MemoryStream())
                using (var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Write))
                {
                    cs.Write(cipher, 0, cipher.Length);
                    cs.FlushFinalBlock();
                    return ms.ToArray();
                }
            }
        }

        public static byte[] RsaDecrypt(byte[] data, string privateKeyPem)
        {
            using (var rsa = RSA.Create())
            {
                rsa.ImportFromPem(privateKeyPem);
                return rsa.Decrypt(data, RSAEncryptionPadding.OaepSHA256);
            }
        }
    }
}
