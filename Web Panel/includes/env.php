<?php
/**
 * .env 解析与读取 —— 全站统一入口。
 *
 * ★ 缺陷背景：此前 .env 的解析函数只定义在 `database/db_conection.php` 内部，
 *   于是【只有】引用了该文件的入口才能拿到 .env 配置。
 *   `update.php` 只 require 了 auth/platform/csrf 三个 includes，从未加载 .env，
 *   导致它里面的 `GIT_TOKEN` 恒为空字符串 ——
 *   而 GIT_TOKEN 是访问【私有】仓库所必需的，于是「检查更新」在私有部署下
 *   必然返回"无法连接更新服务器"。
 *
 *   本文件把加载逻辑抽出来，任何入口 require 一次即可。
 */

if (!function_exists('loadEnv')) {

    /** 定位 Web Panel 根目录下的 .env */
    function env_path(): string {
        return __DIR__ . '/../.env';
    }

    /**
     * 解析 .env（key=value；忽略空行与 # 注释）。
     * 只写入 $_ENV，不 putenv —— 避免 mod_php 常驻进程下配置跨请求泄漏。
     */
    function loadEnv(string $path = ''): void {
        $path = ($path !== '') ? $path : env_path();
        if (!is_file($path)) return;
        foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            $line = trim($line);
            if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) continue;
            [$k, $v] = explode('=', $line, 2);
            $k = trim($k);
            if ($k === '') continue;
            $_ENV[$k] = trim($v);
        }
    }

    /**
     * 取配置值。优先级：$_ENV（已 loadEnv） > 真实环境变量 > 默认值。
     * 注意不把「空字符串」当作有效覆盖 —— .env 里写了 KEY= 时仍会回落到默认值。
     */
    function env_get(string $key, string $default = ''): string {
        if (array_key_exists($key, $_ENV)) {
            $v = $_ENV[$key];
            if (is_scalar($v) && (string)$v !== '') return (string)$v;
        }
        $g = getenv($key);
        if ($g !== false && $g !== '') return (string)$g;
        return $default;
    }
}

// 引入即自动加载默认 .env
loadEnv();
