<?php
/**
 * 文件级失败计数 —— 用于登录 / 改密等敏感操作的频率限制。
 *
 * 原先计数存在 $_SESSION 里：攻击者每次请求丢弃 cookie 就是个"新会话"，
 * 限速形同虚设。这里改为共享文件 + flock，跨会话跨进程生效。
 *
 * rl_hit($key, $max, $window)  记录一次失败，返回 [是否已超限, 当前次数]
 * rl_reset($key)              成功后清零
 */
function _rl_path(string $key): string {
    return sys_get_temp_dir() . '/.jasmin_rl_' . hash('sha256', $key);
}

function rl_check(string $key, int $max = 10, int $window = 300): array {
    $f = _rl_path($key);
    $fh = @fopen($f, 'c+');
    if (!$fh) return [false, 0];            // 拿不到文件就不阻断（可用性优先）
    @flock($fh, LOCK_EX);
    $now = time();
    $data = json_decode(stream_get_contents($fh) ?: '[]', true);
    if (!is_array($data)) $data = [];
    $data = array_values(array_filter($data, function ($t) use ($now, $window) {
        return is_int($t) && ($now - $t) < $window;
    }));
    $cnt = count($data);
    $blocked = ($cnt >= $max);
    if ($cnt >= $max) {
        @ftruncate($fh, 0); @rewind($fh);
        @fwrite($fh, json_encode($data)); @fflush($fh);
    }
    @flock($fh, LOCK_UN); @fclose($fh);
    return [$blocked, $cnt];
}

function rl_hit(string $key, int $max = 10, int $window = 300): array {
    $f = _rl_path($key);
    $fh = @fopen($f, 'c+');
    if (!$fh) return [false, 0];
    @flock($fh, LOCK_EX);
    $now = time();
    $data = json_decode(stream_get_contents($fh) ?: '[]', true);
    if (!is_array($data)) $data = [];
    $data = array_values(array_filter($data, function ($t) use ($now, $window) {
        return is_int($t) && ($now - $t) < $window;
    }));
    $data[] = $now;
    $cnt = count($data);
    @ftruncate($fh, 0); @rewind($fh);
    @fwrite($fh, json_encode($data)); @fflush($fh);
    @flock($fh, LOCK_UN); @fclose($fh);
    return [$cnt > $max, $cnt];
}

function rl_reset(string $key): void {
    @unlink(_rl_path($key));
}
