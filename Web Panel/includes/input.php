<?php
/**
 * 入参规范化 —— 所有 $_GET / $_POST 取值都应经此转换。
 *
 * 【为什么需要它】
 * PHP 允许 `?x[]=1` 把任意参数变成数组。数组一旦流进 trim() / strlen() /
 * hash_equals() / password_verify() / sanitize(string) 这类期望 string 的位置，
 * PHP 8 会抛 TypeError → 500。
 *
 * 而这类 500 是【未授权可触发】的：checklogin.php 与 install.php 都在未登录
 * 状态调用 csrf_verify()，所以一个 `csrf_token[]=x` 就能把 PHP 错误页打给任何人。
 * 它不会直接造成数据损失，但会污染日志、触发告警、并给扫描器留下"此站不稳"的信号。
 *
 * 【规则】
 *   取不到、或取到的不是标量 → 一律退回默认值，永不抛错。
 *   不做类型"猜测"：数组/对象/null 不尝试强转，直接回落。
 */

if (!function_exists('in_str')) {

    /** 从指定超全局数组里取一个字符串；非标量一律退回 $default */
    function in_str(array $src, string $key, string $default = ''): string {
        $v = $src[$key] ?? null;
        if (is_string($v)) return $v;
        if (is_int($v) || is_float($v) || is_bool($v)) return (string)$v;
        return $default;                 // 数组 / 对象 / null → 回落
    }

    /** 从指定超全局数组里取一个整数；非标量退回 $default */
    function in_int(array $src, string $key, int $default = 0): int {
        $v = $src[$key] ?? null;
        return is_scalar($v) ? (int)$v : $default;
    }

    /** POST 字符串 */
    function post_str(string $key, string $default = ''): string {
        return in_str($_POST, $key, $default);
    }

    /** GET 字符串 */
    function get_str(string $key, string $default = ''): string {
        return in_str($_GET, $key, $default);
    }

    /** POST 整数 */
    function post_int(string $key, int $default = 0): int {
        return in_int($_POST, $key, $default);
    }

    /**
     * 解析客户端 IP（用于频率限制键）。
     *
     * ★ 默认【不信任】任何代理头，直接用 REMOTE_ADDR。
     *   X-Real-IP / X-Forwarded-For 都是客户端可随手伪造的：若直接采信，
     *   攻击者每个请求换一个假 IP 就能拿到一个全新的限速桶 —— 登录/改密
     *   的爆破频率限制形同虚设（单机 compose 里 php 直接 8080 暴露，更是如此）。
     *
     * 仅当显式设置环境变量 TRUST_PROXY=1（确实部署在可信反代/nginx 之后，
     * 且该反代会覆盖这两个头）时才采信代理头。
     */
    function client_ip(): string {
        $trust = getenv('TRUST_PROXY');
        if ($trust !== false && $trust !== '' && $trust !== '0') {
            $rip = $_SERVER['HTTP_X_REAL_IP'] ?? '';
            if (is_string($rip) && $rip !== '') return $rip;
            $xff = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
            if (is_string($xff) && $xff !== '') return trim(explode(',', $xff)[0]);
        }
        return $_SERVER['REMOTE_ADDR'] ?? '';
    }
}
