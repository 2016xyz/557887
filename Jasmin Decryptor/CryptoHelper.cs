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

        // ── DER (ASN.1) 最小解析器 ──────────────────────────────────────────
        // 为什么不用 RSA.ImportFromPem()：
        //   它是 .NET 5+ 专有 API，在【任何】.NET Framework 版本上都不存在。
        //   实测（net45 / net48 双目标编译）：
        //     net45 -> CS1061 ImportFromPem 不存在、CS0103 RSAEncryptionPadding 不存在
        //     net48 -> CS1061 ImportFromPem 仍不存在
        //   即该项目在原目标框架下根本无法编译。改为自行解析 PEM/DER。
        private static byte[] DerValue(byte[] d, ref int p, int want)
        {
            if (p >= d.Length) throw new CryptographicException("DER: truncated (tag)");
            int tag = d[p++];
            if (tag != want)
                throw new CryptographicException(string.Format(
                    "DER: tag mismatch, got 0x{0:X2} want 0x{1:X2}", tag, want));
            if (p >= d.Length) throw new CryptographicException("DER: truncated (length)");
            int lb = d[p++];
            int len;
            if (lb < 0x80) { len = lb; }
            else
            {
                int n = lb & 0x7F;
                if (n < 1 || n > 4) throw new CryptographicException("DER: unsupported length encoding");
                if (p + n > d.Length) throw new CryptographicException("DER: truncated (length bytes)");
                len = 0;
                for (int i = 0; i < n; i++) len = (len << 8) | d[p++];
            }
            if (p + len > d.Length) throw new CryptographicException("DER: truncated (value)");
            byte[] v = new byte[len];
            Buffer.BlockCopy(d, p, v, 0, len);
            p += len;
            return v;
        }

        // DER 正整数最高位为 1 时会补一个 0x00；RSAParameters 不接受该前导零
        private static byte[] StripLeadingZeros(byte[] a)
        {
            int i = 0;
            while (i < a.Length - 1 && a[i] == 0) i++;
            if (i == 0) return a;
            byte[] o = new byte[a.Length - i];
            Buffer.BlockCopy(a, i, o, 0, o.Length);
            return o;
        }

        private static byte[] PemToDer(string pem)
        {
            var sb = new System.Text.StringBuilder();
            string[] lines = pem.Split('\n');
            for (int i = 0; i < lines.Length; i++)
            {
                string t = lines[i].Trim();
                if (t.Length == 0 || t.StartsWith("-----")) continue;
                sb.Append(t);
            }
            if (sb.Length == 0)
                throw new CryptographicException("PEM body is empty - private key not loaded");
            return Convert.FromBase64String(sb.ToString());
        }

        /// <summary>
        /// 解析 RSA 私钥 PEM → RSAParameters。必须同时支持两种容器格式：
        ///   · PKCS#1 "BEGIN RSA PRIVATE KEY"  ← Python 面板 (PrivateFormat.TraditionalOpenSSL)
        ///     RSAPrivateKey  ::= SEQUENCE { version, n, e, d, p, q, dp, dq, qInv }
        ///   · PKCS#8 "BEGIN PRIVATE KEY"      ← PHP 面板 (keygen.php, openssl_pkey_export)
        ///     PrivateKeyInfo ::= SEQUENCE { version, AlgorithmIdentifier, OCTET STRING(内层 RSAPrivateKey) }
        /// 只认 PKCS#1 会在遇到 PKCS#8 时抛
        ///   "DER: tag mismatch, got 0x30 want 0x02"
        /// 判别点：跳过 version INTEGER 后下一个 TLV 的 tag（0x02=PKCS#1，0x30=PKCS#8）。
        /// </summary>
        private static RSAParameters ParseRsaPrivateKeyPem(string pem)
        {
            byte[] der = PemToDer(pem);
            int off = 0;
            byte[] outer = DerValue(der, ref off, 0x30);

            int probe = 0;
            DerValue(outer, ref probe, 0x02);                     // version INTEGER
            if (probe >= outer.Length)
                throw new CryptographicException("DER: truncated after version - not a valid RSA private key");
            int nextTag = outer[probe];

            byte[] seq = outer;
            if (nextTag == 0x30)
            {
                // ── PKCS#8：解开 PrivateKeyInfo 取内层 RSAPrivateKey ──
                int q = 0;
                DerValue(outer, ref q, 0x02);                     // version
                DerValue(outer, ref q, 0x30);                     // AlgorithmIdentifier
                byte[] pk = DerValue(outer, ref q, 0x04);         // privateKey OCTET STRING
                int r = 0;
                seq = DerValue(pk, ref r, 0x30);                  // 内层 RSAPrivateKey
                if (seq.Length > 0 && seq[0] == 0x30)
                    throw new CryptographicException(
                        "DER: looks like an EncryptedPrivateKeyInfo (encrypted PKCS#8); " +
                        "supply the decrypted plaintext private key PEM");
            }
            else if (nextTag != 0x02)
            {
                throw new CryptographicException(string.Format(
                    "DER: unexpected tag 0x{0:X2} after version - not PKCS#1 (0x02) nor PKCS#8 (0x30)", nextTag));
            }

            int p = 0;
            DerValue(seq, ref p, 0x02);                           // version
            byte[] n = DerValue(seq, ref p, 0x02);                // modulus
            byte[] e = DerValue(seq, ref p, 0x02);                // publicExponent
            byte[] d = DerValue(seq, ref p, 0x02);                // privateExponent
            byte[] p1 = DerValue(seq, ref p, 0x02);               // prime1 (P)
            byte[] p2 = DerValue(seq, ref p, 0x02);               // prime2 (Q)
            byte[] dp = DerValue(seq, ref p, 0x02);               // exponent1 (DP)
            byte[] dq = DerValue(seq, ref p, 0x02);               // exponent2 (DQ)
            byte[] qi = DerValue(seq, ref p, 0x02);               // coefficient (qInv)

            // ★ CRT 参数必须一并导入：只给 n/e/d 时 RSACng.ImportParameters 看似成功，
            //   但一调用 Decrypt 就报 "Key does not exist."（CNG 的 BCRYPT_RSAPRIVATE_BLOB
            //   结构本身要求 cbPrime1/cbPrime2，缺素数导入的是空壳）。
            var ps = new RSAParameters();
            ps.Modulus = StripLeadingZeros(n);
            ps.Exponent = StripLeadingZeros(e);
            ps.D = StripLeadingZeros(d);
            ps.P = StripLeadingZeros(p1);
            ps.Q = StripLeadingZeros(p2);
            ps.DP = StripLeadingZeros(dp);
            ps.DQ = StripLeadingZeros(dq);
            ps.InverseQ = StripLeadingZeros(qi);
            return ps;
        }

        public static byte[] RsaDecrypt(byte[] data, string privateKeyPem)
        {
            RSAParameters ps = ParseRsaPrivateKeyPem(privateKeyPem);
            // 不用 RSA.Create()：.NET Framework 上它返回 RSACryptoServiceProvider，
            // 只支持 PKCS#1 与 OAEP-SHA1 —— 传 OaepSHA256 必抛
            // "Specified padding mode is not valid for this algorithm"。
            // RSACng 自 .NET Framework 4.6 起可用，支持 OAEP-SHA256。
            using (var rsa = new RSACng())
            {
                rsa.ImportParameters(ps);
                return rsa.Decrypt(data, RSAEncryptionPadding.OaepSHA256);
            }
        }
    }
}
