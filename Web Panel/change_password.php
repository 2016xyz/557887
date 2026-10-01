<?php
/**
 * 修改管理员密码
 * 安全要点: 需登录 + CSRF + 校验当前密码 + 强度校验 + 失败频率限制 + 会话ID轮换
 */
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/csrf.php';
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

// 失败频率限制: 同IP 10分钟内最多8次
$ip = preg_replace('/[^0-9a-f:.]/', '', $_SERVER['REMOTE_ADDR'] ?? '');
$fk = 'pw_fail_' . $ip;
$fc = (int)($_SESSION[$fk] ?? 0);
$ft = (int)($_SESSION[$fk . '_t'] ?? 0);
if (time() - $ft > 600) { $fc = 0; }
if ($fc >= 8) {
    http_response_code(429);
    echo json_encode(['ok' => false, 'msg' => '尝试过于频繁，请 10 分钟后再试']);
    exit;
}

$cur  = $_POST['current_password'] ?? '';
$new  = $_POST['new_password']     ?? '';
$new2 = $_POST['confirm_password'] ?? '';

// 校验当前密码
$stmt = $pdo->prepare('SELECT id, creds FROM master WHERE admin = :u LIMIT 1');
$stmt->execute([':u' => $_SESSION['username']]);
$row = $stmt->fetch();

if (!$row || !password_verify($cur, $row['creds'])) {
    $_SESSION[$fk]   = $fc + 1;
    $_SESSION[$fk . '_t'] = $fc === 0 ? time() : $ft;
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
unset($_SESSION[$fk], $_SESSION[$fk . '_t']);
session_regenerate_id(true);

@file_put_contents(__DIR__ . '/.pw_changed', date('c'));

echo json_encode(['ok' => true, 'msg' => '密码已更新，请使用新密码重新登录']);
