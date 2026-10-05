<?php
/**
 * PHP 内置服务器路由器 (router.php)
 * 
 * 用途：在 Windows / Linux / macOS 上使用 PHP 内置服务器时，
 *       模拟 Apache .htaccess 的安全规则 —— 因为 `php -S` 会忽略 .htaccess，
 *       若不加此路由器，.env / 私钥 / passwords/*.flora 会被直接下载。
 * 
 * 启动方式：
 *   php -S localhost:8080 router.php
 *   （必须显式指定 router.php；否则静态文件会被内置服务器直接返回）
 * 
 * 注意：仅用于开发/测试。生产环境请使用 Apache（.htaccess）或 Nginx。
 */

$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));
$path = __DIR__ . $uri;
$rel = ltrim(str_replace('\\', '/', $uri), '/');

// ── ① 拒绝所有隐藏文件（.env / .installed / .schema_* / .key_secret ...）──
$basename = basename($rel);
if ($basename !== '' && $basename[0] === '.') {
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'Forbidden';
    return true;
}

// ── ② 拒绝敏感目录（includes / database / templates / passwords）──
$firstSeg = strtok($rel, '/');
if (in_array($firstSeg, ['includes', 'database', 'templates', 'passwords'], true)) {
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'Forbidden';
    return true;
}

// ── ③ 拒绝归档/备份/配置/文档扩展名 ──
if (preg_match('/\.(zip|tar|gz|tgz|bz2|xz|rar|7z|bak|old|orig|save|swp|swo|log|sql|tpl|md|txt|env|ini|conf|cfg|inc|yml|yaml|lock|json|gitignore)$/i', $rel)) {
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'Forbidden';
    return true;
}

// ── ④ 拒绝明文私钥与 AES 口令（仅 .pem.enc 公开）──
if (preg_match('#^payloads/(jasmin_private\.pem|\.key_secret)$#', $rel)) {
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'Forbidden';
    return true;
}

// ── ⑤ 拒绝密钥归档备份 ──
if (preg_match('#^payloads/.*\.bak\.#', $rel)) {
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'Forbidden';
    return true;
}

// ── ⑥ 拒绝 .flora 直接访问（必须走需登录的 download_file.php）──
if (preg_match('#^passwords/.*\.flora$#', $rel)) {
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'Forbidden';
    return true;
}

// ── ⑦ 目录请求：尝试 index.php ──
if (is_dir($path)) {
    if (file_exists($path . '/index.php')) {
        require $path . '/index.php';
        return true;
    }
    // 无 index：拒绝目录列举
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'Forbidden';
    return true;
}

// ── ⑧ 存在的文件：交由内置服务器处理 ──
if (is_file($path)) {
    return false;   // false = 让 PHP 内置服务器直接返回该文件
}

// ── ⑨ 不存在的路径：404 ──
http_response_code(404);
header('Content-Type: text/plain');
echo 'Not Found';
return true;
