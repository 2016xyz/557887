<?php
/**
 * 跨平台兼容性辅助函数
 * 支持 Windows / Linux / macOS
 */

/**
 * 检测是否为Windows平台
 */
function is_windows(): bool {
    return PHP_OS_FAMILY === 'Windows' || strtoupper(substr(PHP_OS, 0, 3)) === 'WIN';
}

/**
 * 跨平台文件权限设置
 * 
 * @param string $path 文件路径
 * @param int $mode Unix权限模式 (如 0640)
 * @param string|null $owner 所有者 (Unix only, null=自动检测)
 * @return bool
 */
function set_file_permissions(string $path, int $mode = 0640, ?string $owner = null): bool {
    if (!file_exists($path)) {
        error_log("[jasmin] set_file_permissions: file not found: $path");
        return false;
    }
    
    if (is_windows()) {
        // Windows: 权限模型完全不同,简单chmod无效
        // 可选: 使用 icacls 设置ACL，但大多数场景下保持默认权限即可
        // Windows文件系统会自动继承父目录权限
        return true;  // Windows上不报错，跳过权限设置
    }
    
    // Unix/Linux/macOS
    $success = @chmod($path, $mode);
    
    // 尝试更改所有者
    if ($owner && function_exists('posix_getpwnam')) {
        @chown($path, $owner);
        @chgrp($path, $owner);
    } elseif ($owner === null && function_exists('posix_geteuid')) {
        // 自动检测web用户
        $euid = posix_geteuid();
        $user_info = posix_getpwuid($euid);
        $web_user = $user_info['name'] ?? 'www-data';
        @chown($path, $web_user);
        @chgrp($path, $web_user);
    }
    
    // 如果chmod失败，尝试更宽松的权限作为兜底
    if (!$success && !is_readable($path)) {
        @chmod($path, 0644);
    }
    
    return true;
}

/**
 * 跨平台目录创建
 * 
 * @param string $path 目录路径
 * @param int $mode Unix权限模式
 * @param bool $recursive 是否递归创建
 * @return bool
 */
function make_directory(string $path, int $mode = 0750, bool $recursive = true): bool {
    if (is_dir($path)) {
        return true;
    }
    
    if (!@mkdir($path, $mode, $recursive)) {
        return false;
    }
    
    // Unix下设置权限
    if (!is_windows()) {
        @chmod($path, $mode);
    }
    
    return true;
}

/**
 * 规范化路径分隔符
 * 
 * @param string $path 文件路径
 * @return string
 */
function normalize_path(string $path): string {
    // 统一使用正斜杠，Windows也支持正斜杠
    return str_replace('\\', '/', $path);
}

/**
 * 获取临时目录路径
 * 
 * @return string
 */
function get_temp_dir(): string {
    if (is_windows()) {
        return getenv('TEMP') ?: getenv('TMP') ?: 'C:\\Windows\\Temp';
    }
    return sys_get_temp_dir();
}

/**
 * 安全删除文件（跨平台）
 * 
 * @param string $path 文件路径
 * @return bool
 */
function safe_unlink(string $path): bool {
    if (!file_exists($path)) {
        return true;
    }
    
    // Windows上可能有文件锁占用，多次重试
    $max_attempts = is_windows() ? 3 : 1;
    for ($i = 0; $i < $max_attempts; $i++) {
        if (@unlink($path)) {
            return true;
        }
        if ($i < $max_attempts - 1) {
            usleep(100000); // 等待100ms
        }
    }
    
    return false;
}
