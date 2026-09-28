<?php
/**
 * 首页 — 重定向到登录或面板
 */
require_once __DIR__ . '/includes/auth.php';
if (session_status() === PHP_SESSION_NONE) session_start();
if (isset($_SESSION['username'])) {
    header('Location: dashboard.php');
} else {
    header('Location: login.php');
}
exit;
