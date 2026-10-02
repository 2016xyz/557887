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

// ★ 只在【库中尚无任何管理员】时创建 admin。
// 此前无论是否存在都 upsert 字面量 'admin'：而安装向导 install.php 允许自选
// 管理员名 —— 一旦向导用了别的名字，容器每次重建都会凭空多出一个
// admin/ADMIN_PASSWORD(未设置时=admin123) 的第二账号，等于已知口令后门。
// 改为"表为空才建"，容器重建不再新增/覆盖任何账号。
// （管理员在后台改过口令时，entrypoint 已通过 payloads/.pw_changed 提前跳过本脚本。）
try {
    $n = (int)$pdo->query('SELECT COUNT(*) FROM master')->fetchColumn();
} catch (PDOException $e) {
    // master 表尚未建好 -> 以非零退出，让 entrypoint 的重试循环继续等待
    fwrite(STDERR, "master table not ready: " . $e->getMessage() . "\n");
    exit(1);
}
if ($n > 0) {
    echo "master 已有管理员，跳过建号（不覆盖、不新增）。\n";
    exit(0);
}

$insert = $pdo->prepare('INSERT INTO master (admin, creds) VALUES (:admin, :creds)');
$insert->execute([':admin' => 'admin', ':creds' => $hash]);
echo "Admin user created.\n";
echo "Done.\n";
