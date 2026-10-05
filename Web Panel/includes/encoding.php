<?php
/**
 * 全局字符编码配置
 * 确保所有文本输入输出都使用 UTF-8
 */

// PHP内部编码设置
if (function_exists('mb_internal_encoding')) {
    mb_internal_encoding('UTF-8');
}

if (function_exists('mb_http_output')) {
    mb_http_output('UTF-8');
}

// 设置默认字符集（影响htmlspecialchars等函数）
if (function_exists('ini_set')) {
    ini_set('default_charset', 'UTF-8');
}

// 为API响应设置默认Content-Type
// 注意：此设置会被具体页面的header()调用覆盖
if (!headers_sent() && php_sapi_name() !== 'cli') {
    // 检测是否为AJAX/API请求
    $is_ajax = isset($_SERVER['HTTP_X_REQUESTED_WITH']) 
               && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest';
    
    $accept = $_SERVER['HTTP_ACCEPT'] ?? '';
    $is_json_request = strpos($accept, 'application/json') !== false;
    
    // 仅对明确的JSON请求设置JSON响应头
    if ($is_ajax || $is_json_request) {
        @header('Content-Type: application/json; charset=UTF-8');
    }
}

/**
 * 确保字符串为有效的UTF-8
 * 
 * @param string $str 输入字符串
 * @return string 清理后的UTF-8字符串
 */
function ensure_utf8(string $str): string {
    // 移除无效的UTF-8字符
    if (function_exists('mb_check_encoding')) {
        if (!mb_check_encoding($str, 'UTF-8')) {
            // 尝试转换
            if (function_exists('mb_convert_encoding')) {
                $str = mb_convert_encoding($str, 'UTF-8', 'UTF-8');
            } else {
                // 回退：移除非法字符
                $str = iconv('UTF-8', 'UTF-8//IGNORE', $str);
            }
        }
    }
    return $str;
}

/**
 * 安全的HTML输出（防XSS + UTF-8保证）
 * 
 * @param string $str 输入字符串
 * @return string HTML安全的字符串
 */
function safe_html(string $str): string {
    return htmlspecialchars(ensure_utf8($str), ENT_QUOTES | ENT_HTML5, 'UTF-8');
}
