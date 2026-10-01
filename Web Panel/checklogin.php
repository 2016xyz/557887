<?php
/**
 * 登录验证 — PDO预处理 + password_verify + CSRF + 频率限制
 */
session_start();
require_once __DIR__ . '/database/db_conection.php';
require_once __DIR__ . '/includes/csrf.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !isset($_POST['username'])) {
    echo 'not allowed';
    exit;
}

if (!csrf_verify()) {
    echo 'invalid token';
    exit;
}

// 登录频率限制: 同IP 5分钟内最多10次失败
$ip_key = 'login_fail_' . preg_replace('/[^0-9a-f:.]/', '', $_SERVER['REMOTE_ADDR'] ?? '');
$fail_count = (int)($_SESSION[$ip_key] ?? 0);
$fail_time  = (int)($_SESSION[$ip_key . '_t'] ?? 0);
if (time() - $fail_time > 300) { $fail_count = 0; } // 5分钟窗口重置
if ($fail_count >= 10) {
    http_response_code(429);
    echo 'too many attempts';
    exit;
}

$username = trim($_POST['username']);
$password = $_POST['password'] ?? '';

$stmt = $pdo->prepare('SELECT id, admin, creds FROM master WHERE admin = :admin LIMIT 1');
$stmt->execute([':admin' => $username]);
$user = $stmt->fetch();

if ($user && password_verify($password, $user['creds'])) {
    // 登录成功，清除失败计数
    unset($_SESSION[$ip_key], $_SESSION[$ip_key . '_t']);
    session_regenerate_id(true);
    $_SESSION['username'] = $user['admin'];
    echo 'success';
} else {
    // 记录失败次数
    $_SESSION[$ip_key] = $fail_count + 1;
    $_SESSION[$ip_key . '_t'] = $fail_count === 0 ? time() : $fail_time;
    echo 'denied';
}
