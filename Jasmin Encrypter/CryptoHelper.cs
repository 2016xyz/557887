using System;
using System.IO;
using System.Security.Cryptography;

namespace Jasmin_Encrypter
{
    public static class CryptoHelper
    {
        // RSA-2048 public key (PEM). Replace with your own keypair.
        public const string RSA_PUBLIC_KEY = @"-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Z3VS5JJcds3xfn/ygWe
hEhQLiP5RO2s5RCQTBKV9n0RUVMxNBMH8VEJnAEI8hnQpKr2LMV1TsXGBQX0FWv
rVENBEYBqxE+a3DxVFpU8PQKA08W7HFv9p9b2vB9GrNLFkKN+CqXLzR7E7oLP8v8
b7cHYrLKWD2IexLhkbR0FYFk2TZ4YOCYnvOSE91rPGJbQoTz+G6Acv1sGHHCvOGe
IMPKjb8GRQHY0PrXuYt/0svbzN7g9r5yp+JBiDHjPn0mJMqZrs5ag1yrA+3e54G+
WlE0AUsm6LcCPXGGY5EPnbjyY+oB5YOFh6xMZgbOGG+iH4VEEjm2aRaYFnSlJDuM
3wIDAQAB
-----END PUBLIC KEY-----";

        public static byte[] AesEncrypt(byte[] data, byte[] key, byte[] iv)
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
                using (var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
                {
                    cs.Write(data, 0, data.Length);
                    cs.FlushFinalBlock();
                    return ms.ToArray();
                }
            }
        }

        public static byte[] RsaEncrypt(byte[] data, string publicKeyPem)
        {
            using (var rsa = RSA.Create())
            {
                rsa.ImportFromPem(publicKeyPem);
                return rsa.Encrypt(data, RSAEncryptionPadding.OaepSHA256);
            }
        }

        public static byte[] GenerateRandomBytes(int count)
        {
            var buf = new byte[count];
            using (var rng = RandomNumberGenerator.Create())
                rng.GetBytes(buf);
            return buf;
        }
    }
}
