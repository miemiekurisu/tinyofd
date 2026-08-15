@echo off
REM ============================================================
REM TinyOFD 一键构建入口 (兼容 cmd.exe 双击/命令行)
REM 实际构建逻辑在 script\build.ps1 (lazbuild 前端 + fpc 后端，动态路径)。
REM 用法: build.bat 或 build.bat 任意参数透传给 build.ps1
REM ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build.ps1" %*
exit /b %errorlevel%
