<?php
/**
 * RSA密钥对生成API — 生成并保存到 payloads/ 目录
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
file_put_contents($dir . '/jasmin_private.pem', $priv);
file_put_contents($dir . '/jasmin_public.pem', $pub);

echo json_encode(['ok'=>true,'pub'=>$pub,'msg'=>'RSA-2048 密钥对已生成并保存到 payloads/ 目录']);
