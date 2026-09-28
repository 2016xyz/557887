<?php
/**
 * 登录验证 — PDO预处理 + password_verify + CSRF
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

$username = trim($_POST['username']);
$password = $_POST['password'] ?? '';

$stmt = $pdo->prepare('SELECT id, admin, creds FROM master WHERE admin = :admin LIMIT 1');
$stmt->execute([':admin' => $username]);
$user = $stmt->fetch();

if ($user && password_verify($password, $user['creds'])) {
    session_regenerate_id(true);
    $_SESSION['username'] = $user['admin'];
    echo 'success';
} else {
    echo 'denied';
}
