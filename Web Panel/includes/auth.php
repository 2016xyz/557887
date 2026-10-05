<?php
/**
 * 认证辅助 — 增强Session安全 + header重定向后强制exit
 */
require_once __DIR__ . '/input.php';

/**
 * 安全的Session启动（带安全配置）
 */
function secure_session_start(): void {
    if (session_status() !== PHP_SESSION_NONE) {
        return; // 已启动
    }
    
    // Session安全配置（必须在session_start之前）
    ini_set('session.cookie_httponly', '1');
    ini_set('session.cookie_samesite', 'Strict');
    ini_set('session.use_strict_mode', '1');
    ini_set('session.use_only_cookies', '1');
    ini_set('session.gc_maxlifetime', '3600');  // 1小时
    ini_set('session.cookie_lifetime', '0');     // 浏览器关闭即过期
    
    // HTTPS环境启用secure cookie
    if ((!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') 
        || (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https')) {
        ini_set('session.cookie_secure', '1');
    }
    
    session_start();
    
    // Session固定攻击防护：首次访问时重新生成ID
    if (!isset($_SESSION['initiated'])) {
        session_regenerate_id(true);
        $_SESSION['initiated'] = true;
        $_SESSION['created_at'] = time();
    }
}

function require_auth(): void {
    secure_session_start();
    
    if (!isset($_SESSION['username'])) {
        header('Location: login.php');
        exit;
    }
    
    // Session超时检查（1小时无活动）
    $timeout = 3600;
    if (isset($_SESSION['last_activity']) 
        && (time() - $_SESSION['last_activity']) > $timeout) {
        session_unset();
        session_destroy();
        header('Location: login.php?timeout=1');
        exit;
    }
    $_SESSION['last_activity'] = time();
}

function require_guest(): void {
    secure_session_start();
    
    if (isset($_SESSION['username'])) {
        header('Location: dashboard.php');
        exit;
    }
}
