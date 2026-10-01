<?php
/**
 * 登录验证 — PDO预处理 + password_verify + CSRF + 频率限制
 */
session_start();
require_once __DIR__ . '/database/db_conection.php';
require_once __DIR__ . '/includes/csrf.php';
require_once __DIR__ . '/includes/ratelimit.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !isset($_POST['username'])) {
    echo 'not allowed';
    exit;
}

if (!csrf_verify()) {
    echo 'invalid token';
    exit;
}

// 登录频率限制：同 IP + 同账号，5 分钟内最多 10 次失败。
// 存在共享文件里而非 $_SESSION —— 后者丢 cookie 就能绕过。
$ip = $_SERVER['HTTP_X_REAL_IP'] ?? '';
if ($ip === '') { $xf = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? ''; $ip = $xf !== '' ? trim(explode(',', $xf)[0]) : ($_SERVER['REMOTE_ADDR'] ?? ''); }
$is_str = function ($k) { return isset($_POST[$k]) && is_string($_POST[$k]); };
$username = $is_str('username') ? trim($_POST['username']) : '';
$password = $is_str('password') ? $_POST['password'] : '';   // 传数组会让 password_verify 抛 TypeError 500
$rl_key = 'login|' . $ip . '|' . $username;
list($blocked, $cnt) = rl_check($rl_key, 10, 300);
if ($blocked) {
    http_response_code(429);
    echo 'too many attempts';
    exit;
}
if ($username === '' || $password === '') {
    echo 'denied';
    exit;
}

$stmt = $pdo->prepare('SELECT id, admin, creds FROM master WHERE admin = :admin LIMIT 1');
$stmt->execute([':admin' => $username]);
$user = $stmt->fetch();

if ($user && password_verify($password, $user['creds'])) {
    rl_reset($rl_key);            // 登录成功清零
    session_regenerate_id(true);
    $_SESSION['username'] = $user['admin'];
    echo 'success';
} else {
    rl_hit($rl_key, 10, 300);     // 记录失败（每次都追加，窗口自然滑动）
    echo 'denied';
}
