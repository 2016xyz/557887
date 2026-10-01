<?php
/**
 * CSRF Token 辅助函数
 */
require_once __DIR__ . '/input.php';

function csrf_token(): string {
    if (session_status() === PHP_SESSION_NONE) session_start();
    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

function csrf_field(): string {
    return '<input type="hidden" name="csrf_token" value="' . csrf_token() . '">';
}

function csrf_verify(): bool {
    if (session_status() === PHP_SESSION_NONE) session_start();
    // in_str 而非直接取 $_POST：`csrf_token[]=x` 传数组会让 hash_equals
    // 抛 TypeError → 500。而 checklogin.php / install.php 都在【未登录】状态
    // 调用本函数，所以那是一个未授权可达的 500。
    $token = post_str('csrf_token');
    $sess  = $_SESSION['csrf_token'] ?? '';
    return is_string($sess) && $token !== '' && hash_equals($sess, $token);
}
