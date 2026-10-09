@echo off
title REDMAGIC Live Performance
if exist "%~dp0dashboard.html" start "" "%~dp0dashboard.html"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\live-redmagic.ps1" %*
pause
