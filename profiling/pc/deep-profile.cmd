@echo off
call "%~dp0scripts\pwsh-launcher.cmd" -NoProfile -File "%~dp0scripts\deep-profile.ps1" -Capture %*
pause
