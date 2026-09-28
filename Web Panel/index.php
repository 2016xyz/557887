<?php
/**
 * 首页 — 未安装跳安装引导，否则跳登录/面板
 */
session_start();
if (!file_exists(__DIR__ . '/.installed')) {
    header('Location: install.php');
    exit;
}
if (isset($_SESSION['username'])) {
    header('Location: dashboard.php');
} else {
    header('Location: login.php');
}
exit;
