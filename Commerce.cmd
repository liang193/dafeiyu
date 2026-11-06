@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0experiments\commerce\Start-Commerce.ps1" %*
if errorlevel 1 pause
