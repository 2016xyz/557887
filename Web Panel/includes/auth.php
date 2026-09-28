<?php
/**
 * 认证辅助 — header重定向后强制exit
 */

function require_auth(): void {
    if (session_status() === PHP_SESSION_NONE) session_start();
    if (!isset($_SESSION['username'])) {
        header('Location: login.php');
        exit;
    }
}

function require_guest(): void {
    if (session_status() === PHP_SESSION_NONE) session_start();
    if (isset($_SESSION['username'])) {
        header('Location: dashboard.php');
        exit;
    }
}
