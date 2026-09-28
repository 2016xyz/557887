<?php
/**
 * 数据库连接 - 使用PDO预处理防SQL注入
 * 凭据从 .env 文件读取，不再硬编码
 */

// 解析 .env 文件
function loadEnv(string $path): void {
    if (!file_exists($path)) {
        die('Missing .env configuration file.');
    }
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') continue;
        if (strpos($line, '=') === false) continue;
        [$key, $value] = explode('=', $line, 2);
        $_ENV[trim($key)] = trim($value);
    }
}

loadEnv(__DIR__ . '/../.env');

$db_host = $_ENV['DB_HOST'] ?? 'localhost';
$db_name = $_ENV['DB_NAME'] ?? 'jasmin_db';
$db_user = $_ENV['DB_USER'] ?? 'jasminadmin';
$db_pass = $_ENV['DB_PASS'] ?? '';

try {
    $pdo = new PDO(
        "mysql:host={$db_host};dbname={$db_name};charset=utf8mb4",
        $db_user,
        $db_pass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    error_log('Database connection failed: ' . $e->getMessage());
    die('Database connection error.');
}
