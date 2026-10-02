<?php
/**
 * 失败计数 —— 用于登录 / 改密等敏感操作的频率限制。
 *
 * 【为什么要重写】
 * 第一版把计数存在 $_SESSION 里：攻击者每次请求丢弃 cookie 就是个"新会话"，
 * 限速形同虚设。第二版改成共享文件 + flock，解决了"跨会话跨进程"的问题 ——
 * 但部署是【多个 php 容器共用一个 nginx】，每个容器各有自己的 /tmp，
 * 于是计数是分开的：限速实际被放大了 N 倍（N = php 副本数），
 * 而且容器一重启就清零。注释里承诺的"跨进程生效"在集群下并不成立。
 *
 * 【现在】
 * 优先使用两个后台都依赖的共享 MySQL；DB 不可用时退回原来的文件实现。
 * 两种后端对调用方完全透明，公开 API 不变：
 *
 *   rl_check($key, $max, $window)  查状态，不计数 → [是否已超限, 当前次数]
 *   rl_hit($key, $max, $window)    记一次失败     → [是否已超限, 当前次数]
 *   rl_reset($key)                 清零
 */

/** 计数键统一哈希后再落库/落盘：原键含用户名，可能超长或含特殊字符 */
function _rl_id(string $key): string {
    return hash('sha256', $key);
}

/** 拿到可用的 DB 句柄；表不存在则懒建一次。不可用返回 null（由调用方回退文件） */
function _rl_store(): ?PDO {
    $pdo = $GLOBALS['pdo'] ?? null;
    if (!($pdo instanceof PDO)) return null;

    static $usable = null;
    if ($usable === false) return null;
    if ($usable === true)  return $pdo;

    // 用标记文件避免每个请求都跑一次 DDL
    $marker = __DIR__ . '/../.schema_rl';
    try {
        if (!file_exists($marker)) {
            $pdo->exec("CREATE TABLE IF NOT EXISTS rate_limit (
                rl_id      char(64)     NOT NULL,
                hits       text         NOT NULL,
                updated_at timestamp    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (rl_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            @file_put_contents($marker, date('c'));
        }
        $usable = true;
        return $pdo;
    } catch (PDOException $e) {
        error_log('ratelimit: DB 后端不可用，回退到文件: ' . $e->getMessage());
        $usable = false;
        return null;
    }
}

function _rl_path(string $key): string {
    return sys_get_temp_dir() . '/.jasmin_rl_' . _rl_id($key);
}

/** 从命中列表里剔除过期项 */
function _rl_prune($data, int $now, int $window): array {
    if (!is_array($data)) return [];
    return array_values(array_filter($data, function ($t) use ($now, $window) {
        return is_int($t) && ($now - $t) < $window;
    }));
}

function rl_check(string $key, int $max = 10, int $window = 300): array {
    $now = time();

    $pdo = _rl_store();
    if ($pdo) {
        try {
            $s = $pdo->prepare('SELECT hits FROM rate_limit WHERE rl_id = :i');
            $s->execute([':i' => _rl_id($key)]);
            $data = _rl_prune(json_decode((string)$s->fetchColumn() ?: '[]', true), $now, $window);
            $cnt = count($data);
            return [$cnt >= $max, $cnt];
        } catch (PDOException $e) {
            error_log('ratelimit: DB 读取失败，回退文件: ' . $e->getMessage());
        }
    }

    $fh = @fopen(_rl_path($key), 'c+');
    if (!$fh) return [false, 0];            // 拿不到就不断（可用性优先）
    @flock($fh, LOCK_EX);
    $data = _rl_prune(json_decode(stream_get_contents($fh) ?: '[]', true), $now, $window);
    $cnt = count($data);
    @ftruncate($fh, 0); @rewind($fh);
    @fwrite($fh, json_encode($data)); @fflush($fh);
    @flock($fh, LOCK_UN); @fclose($fh);
    return [$cnt >= $max, $cnt];
}

function rl_hit(string $key, int $max = 10, int $window = 300): array {
    $now = time();
    $id  = _rl_id($key);

    $pdo = _rl_store();
    if ($pdo) {
        try {
            $pdo->beginTransaction();
            // FOR UPDATE：读-改-写必须串行，否则并发下计数会丢
            $s = $pdo->prepare('SELECT hits FROM rate_limit WHERE rl_id = :i FOR UPDATE');
            $s->execute([':i' => $id]);
            $data = _rl_prune(json_decode((string)$s->fetchColumn() ?: '[]', true), $now, $window);
            $data[] = $now;
            $u = $pdo->prepare('INSERT INTO rate_limit (rl_id, hits) VALUES (:i, :h)
                                ON DUPLICATE KEY UPDATE hits = VALUES(hits)');
            $u->execute([':i' => $id, ':h' => json_encode($data)]);
            $pdo->commit();
            $cnt = count($data);
            // 与 rl_check 的 >= 语义一致：第 $max 次即判超限。
            // 此前 rl_check 用 >= 而 rl_hit 用 >，两函数临界点不一致，
            // 依赖 rl_hit 返回值的调用方会在第 $max 次失败时不判超限。
            return [$cnt >= $max, $cnt];
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            error_log('ratelimit: DB 写入失败，回退文件: ' . $e->getMessage());
        }
    }

    $fh = @fopen(_rl_path($key), 'c+');
    if (!$fh) return [false, 0];
    @flock($fh, LOCK_EX);
    $data = _rl_prune(json_decode(stream_get_contents($fh) ?: '[]', true), $now, $window);
    $data[] = $now;
    $cnt = count($data);
    @ftruncate($fh, 0); @rewind($fh);
    @fwrite($fh, json_encode($data)); @fflush($fh);
    @flock($fh, LOCK_UN); @fclose($fh);
    return [$cnt >= $max, $cnt];
}

function rl_reset(string $key): void {
    $pdo = _rl_store();
    if ($pdo) {
        try {
            $s = $pdo->prepare('DELETE FROM rate_limit WHERE rl_id = :i');
            $s->execute([':i' => _rl_id($key)]);
        } catch (PDOException $e) {
            error_log('ratelimit: DB 删除失败: ' . $e->getMessage());
        }
    }
    @unlink(_rl_path($key));
}
