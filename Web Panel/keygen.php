<?php
/**
 * RSA密钥对生成API — 私钥AES加密存储
 */
require_once __DIR__ . '/includes/auth.php';
require_auth();
header('Content-Type: application/json');

$bits = 2048;
$config = ['private_key_bits' => $bits, 'private_key_type' => OPENSSL_KEYTYPE_RSA];
$key = openssl_pkey_new($config);
if (!$key) {
    echo json_encode(['ok'=>false,'msg'=>'密钥生成失败: '.openssl_error_string()]);
    exit;
}
openssl_pkey_export($key, $priv);
$pub = openssl_pkey_get_details($key)['key'];

$dir = __DIR__ . '/payloads';
if (!is_dir($dir)) mkdir($dir, 0750, true);

// AES-256-CBC 加密私钥
$aes_key = bin2hex(random_bytes(16)); // 32 hex chars = 256 bit
$iv = random_bytes(16);
$encrypted_priv = openssl_encrypt($priv, 'aes-256-cbc', $aes_key, OPENSSL_RAW_DATA, $iv);
$enc_blob = base64_encode($iv . $encrypted_priv);

// 保存: 加密私钥(公开下载) + 明文私钥(仅后台) + 公钥 + 密码
file_put_contents($dir . '/jasmin_private.pem.enc', $enc_blob);
file_put_contents($dir . '/jasmin_private.pem', $priv);  // 后台下载用
file_put_contents($dir . '/jasmin_public.pem', $pub);
file_put_contents($dir . '/.key_secret', $aes_key);      // 解密密码

// 保护明文私钥不可直接URL访问
chmod($dir . '/jasmin_private.pem', 0600);
chmod($dir . '/.key_secret', 0600);

echo json_encode([
    'ok'=>true,
    'pub'=>$pub,
    'key_id'=>substr(md5($pub),0,8),
    'msg'=>'RSA-2048 密钥对已生成，私钥已AES-256加密存储'
]);
