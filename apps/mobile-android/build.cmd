@echo off
rem 看运（destiny）Android 构建入口
rem 用法: cmd /c project/destiny/apps/mobile-android\build.cmd assembleDebug
rem 完整输出写 build-last.log，stdout 只回显最后 100 行，末行打印 BUILD_EXIT=<码>
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build.ps1" %*
set "EC=%ERRORLEVEL%"
endlocal & exit /b %EC%
