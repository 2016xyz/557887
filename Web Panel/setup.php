<?php
/**
 * 初始化脚本 — 生成管理员密码的 bcrypt 哈希并写入数据库
 * 用法: php setup.php <password>
 * 示例: php setup.php MyStr0ngP@ss!
 */

if (php_sapi_name() !== 'cli') {
    die('This script must be run from the command line.');
}

if ($argc < 2) {
    echo "Usage: php setup.php <admin_password>\n";
    exit(1);
}

$password = $argv[1];
$hash = password_hash($password, PASSWORD_BCRYPT);

require_once __DIR__ . '/database/db_conection.php';

// 更新或插入默认管理员
$stmt = $pdo->prepare('SELECT id FROM master WHERE admin = :admin');
$stmt->execute([':admin' => 'admin']);

if ($stmt->fetch()) {
    $update = $pdo->prepare('UPDATE master SET creds = :creds WHERE admin = :admin');
    $update->execute([':creds' => $hash, ':admin' => 'admin']);
    echo "Admin password updated.\n";
} else {
    $insert = $pdo->prepare('INSERT INTO master (admin, creds) VALUES (:admin, :creds)');
    $insert->execute([':admin' => 'admin', ':creds' => $hash]);
    echo "Admin user created.\n";
}

echo "Hash: $hash\n";
echo "Done.\n";
