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
}
