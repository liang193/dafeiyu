@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\Start-FeiYu.ps1" %*
if errorlevel 1 pause
