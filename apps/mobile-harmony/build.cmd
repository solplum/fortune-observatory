@echo off
rem Build wrapper for the destiny HarmonyOS app. Keep this file ASCII-only:
rem cmd.exe parses .cmd files in the ANSI codepage and UTF-8 Chinese comments garble it.
rem External invocation: cmd /c project/destiny/apps/mobile-harmony\build.cmd assembleHap
setlocal
set "HERE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%build.ps1" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
