@echo off
setlocal

where.exe pwsh.exe >nul 2>nul
if not errorlevel 1 (
    pwsh.exe %*
    exit /b %errorlevel%
)

set "PS7=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PS7%" goto launch

rem Codex includes PowerShell 7 even when it is not on the Windows PATH.
set "PS7=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
if exist "%PS7%" goto launch

>&2 echo PowerShell 7 was not found. Open screen-viewer.cmd for the phone preview.
exit /b 1

:launch
"%PS7%" %*
exit /b %errorlevel%
