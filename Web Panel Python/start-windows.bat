@echo off
REM ============================================================
REM  Jasmin C2 - Windows 一键启动脚本 (Python Flask 版)
REM ============================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo  ========================================
echo   Jasmin C2 Panel - Python Launcher
echo  ========================================
echo.

REM ── 检测 Python ──
where python >nul 2>nul
if errorlevel 1 (
    echo  [X] 未检测到 Python。请先安装 Python 3.8+ 并加入 PATH。
    echo      下载: https://www.python.org/downloads/
    echo      安装时务必勾选 "Add Python to PATH"
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('python -c "import sys;print(sys.version.split()[0])"') do set PYVER=%%v
echo  [OK] Python 版本: %PYVER%

REM ── 创建/激活虚拟环境 ──
if not exist "venv" (
    echo  [*] 首次运行，创建虚拟环境...
    python -m venv venv
    if errorlevel 1 (
        echo  [X] 创建虚拟环境失败。
        pause
        exit /b 1
    )
)
call venv\Scripts\activate.bat

REM ── 安装依赖（首次或 requirements 变化时）──
if not exist "venv\.deps_ok" (
    echo  [*] 安装依赖包（首次较慢，请耐心等待）...
    python -m pip install --upgrade pip -q
    python -m pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    if errorlevel 1 (
        echo  [!] 清华镜像安装失败，尝试官方源...
        python -m pip install -r requirements.txt
    )
    if not errorlevel 1 echo ok > "venv\.deps_ok"
)

REM ── 启动 ──
set PORT=5000
if not "%1"=="" set PORT=%1

if not exist "payloads"  mkdir "payloads"

echo.
echo  [*] 启动 Flask 开发服务器...
echo  [*] 地址: http://localhost:%PORT%
echo  [*] 首次访问会进入安装向导: http://localhost:%PORT%/install
echo.
echo  按 Ctrl+C 停止服务器
echo  ----------------------------------------
echo.

set FLASK_APP=app.py
python app.py

endlocal
