<?php
/**
 * 修改管理员密码
 * 安全要点: 需登录 + CSRF + 校验当前密码 + 强度校验 + 失败频率限制 + 会话ID轮换
 */
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/csrf.php';
require_once __DIR__ . '/includes/ratelimit.php';
require_auth();
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/database/db_conection.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['ok' => false, 'msg' => '仅支持 POST']);
    exit;
}

if (!csrf_verify()) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'msg' => 'CSRF 校验失败，请刷新页面重试']);
    exit;
}

// 失败频率限制: 同 IP 10 分钟内最多 8 次。
// 此前计数存在 $_SESSION 里 —— 那正是 ratelimit.php 开头批判的写法：
// 攻击者每次请求丢掉 cookie 就是一个"新会话"，限速形同虚设。
// 登录路径早已改成文件级 + flock，改密路径当时漏改了，这里补齐。
// IP 取可信来源（nginx 已设 X-Real-IP / X-Forwarded-For），与 checklogin.php 一致。
$ip = $_SERVER['HTTP_X_REAL_IP'] ?? '';
if ($ip === '') {
    $xf = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
    $ip = $xf !== '' ? trim(explode(',', $xf)[0]) : ($_SERVER['REMOTE_ADDR'] ?? '');
}
$fk = 'pw|' . $ip;
list($blocked, $cnt) = rl_check($fk, 8, 600);
if ($blocked) {
    http_response_code(429);
    echo json_encode(['ok' => false, 'msg' => '尝试过于频繁，请 10 分钟后再试']);
    exit;
}

// post_str 而非直接取：`new_password[]=x` 传数组会让 strlen/password_verify 抛 TypeError
$cur  = post_str('current_password');
$new  = post_str('new_password');
$new2 = post_str('confirm_password');

// 校验当前密码
$stmt = $pdo->prepare('SELECT id, creds FROM master WHERE admin = :u LIMIT 1');
$stmt->execute([':u' => $_SESSION['username']]);
$row = $stmt->fetch();

if (!$row || !password_verify($cur, $row['creds'])) {
    rl_hit($fk, 8, 600);
    echo json_encode(['ok' => false, 'msg' => '当前密码不正确']);
    exit;
}

// 新密码校验
if (strlen($new) < 8) {
    echo json_encode(['ok' => false, 'msg' => '新密码至少 8 位']);
    exit;
}
if (strlen($new) > 72) {   // bcrypt 上限 72 字节
    echo json_encode(['ok' => false, 'msg' => '新密码过长（最长 72 字节）']);
    exit;
}
if ($new !== $new2) {
    echo json_encode(['ok' => false, 'msg' => '两次输入的新密码不一致']);
    exit;
}
if (hash_equals($cur, $new)) {
    echo json_encode(['ok' => false, 'msg' => '新密码不能与当前密码相同']);
    exit;
}
$classes = 0;
foreach (['/[a-z]/', '/[A-Z]/', '/[0-9]/', '/[^a-zA-Z0-9]/'] as $re) {
    if (preg_match($re, $new)) { $classes++; }
}
if ($classes < 2) {
    echo json_encode(['ok' => false, 'msg' => '新密码需包含小写字母、大写字母、数字、符号中的至少两类']);
    exit;
}

// 写入新哈希
$hash = password_hash($new, PASSWORD_BCRYPT);
$up = $pdo->prepare('UPDATE master SET creds = :c WHERE id = :id');
$up->execute([':c' => $hash, ':id' => $row['id']]);

// 清理失败计数 + 轮换会话ID（防会话固定）
rl_reset($fk);
session_regenerate_id(true);

@file_put_contents(__DIR__ . '/.pw_changed', date('c'));

echo json_encode(['ok' => true, 'msg' => '密码已更新，请使用新密码重新登录']);
