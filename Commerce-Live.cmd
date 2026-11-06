@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0experiments\commerce\Start-CommerceLive.ps1"
if errorlevel 1 pause
