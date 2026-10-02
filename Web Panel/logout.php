<?php
/**
 * 登出 — 销毁会话并重定向
 */
// 仅接受 POST + 有效 CSRF：防止第三方页面用 <img src="logout.php"> 强制登出（登出 CSRF）
require_once __DIR__ . '/includes/csrf.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !csrf_verify()) {
    http_response_code(405);
    echo 'Method Not Allowed';
    exit;
}
if (session_status() === PHP_SESSION_NONE) session_start();
$_SESSION = [];
if (ini_get('session.use_cookies')) {
    $p = session_get_cookie_params();
    setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
}
session_destroy();
header('Location: login.php');
exit;
