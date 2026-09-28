<?php
/**
 * 文件下载 — 修复任意文件读取漏洞
 * 使用 realpath() 限制只能下载 passwords/ 目录内的文件
 */
require_once __DIR__ . '/includes/auth.php';
require_auth();

$file = $_GET['file'] ?? '';
if (empty($file)) {
    http_response_code(400);
    echo 'No file specified.';
    exit;
}

// 限制下载目录为 passwords/
$base_dir = realpath(__DIR__ . '/passwords');
$real_path = realpath($file);

// realpath 返回 false 说明文件不存在; 前缀校验防目录穿越
if ($real_path === false || strpos($real_path, $base_dir) !== 0) {
    http_response_code(403);
    echo 'Access denied.';
    exit;
}

if (!is_file($real_path)) {
    http_response_code(404);
    echo 'File not found.';
    exit;
}

$filename = basename($real_path);
header('Cache-Control: public');
header('Content-Description: File Transfer');
header('Content-Disposition: attachment; filename="' . $filename . '"');
header('Content-Type: application/octet-stream');
header('Content-Transfer-Encoding: binary');
header('Content-Length: ' . filesize($real_path));
readfile($real_path);
exit;
