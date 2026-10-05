@echo off
REM ============================================================
REM  Jasmin C2 - Windows 一键启动脚本 (PHP 版)
REM  使用 PHP 内置服务器 + router.php 安全路由器
REM ============================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo  ========================================
echo   Jasmin C2 Panel - Windows Launcher
echo  ========================================
echo.

REM ── 检测 PHP ──
where php >nul 2>nul
if errorlevel 1 (
    echo  [X] 未检测到 PHP。请先安装 PHP 7.4+ 并加入 PATH。
    echo.
    echo  下载地址（二选一）:
    echo    - XAMPP:  https://www.apachefriends.org/
    echo    - 官方:   https://windows.php.net/download/
    echo.
    echo  安装后确保 php.exe 在 PATH 中，重开本窗口再试。
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('php -r "echo PHP_VERSION;"') do set PHPVER=%%v
echo  [OK] PHP 版本: %PHPVER%

REM ── 检测必要扩展 ──
php -r "exit(extension_loaded('pdo_mysql')?0:1);"
if errorlevel 1 (
    echo  [!] 警告: 未启用 pdo_mysql 扩展，面板无法连接数据库。
    echo      请在 php.ini 中取消注释:
    echo        extension=pdo_mysql
    echo        extension=mbstring
    echo        extension=openssl
    echo        extension=zip
)

REM ── 检测 .env ──
if not exist ".env" (
    if exist ".env.example" (
        echo  [i] 未找到 .env，正在从 .env.example 复制...
        copy ".env.example" ".env" >nul
    )
)

REM ── 确保目录存在 ──
if not exist "payloads"   mkdir "payloads"
if not exist "passwords"  mkdir "passwords"

REM ── 启动 ──
set PORT=8080
if not "%1"=="" set PORT=%1

echo.
echo  [*] 启动 PHP 内置服务器 (含安全路由)...
echo  [*] 地址: http://localhost:%PORT%
echo  [*] 首次访问会进入安装向导: http://localhost:%PORT%/install.php
echo.
echo  按 Ctrl+C 停止服务器
echo  ----------------------------------------
echo.

php -S localhost:%PORT% router.php

endlocal
