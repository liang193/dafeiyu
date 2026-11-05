@echo off
set WSL_UTF8=1
echo === NapCat WebUI login token ONLY ===
echo Copy the token line below; do not copy labels or warnings.
echo.
wsl -d Ubuntu -u root -- python3 /opt/feiyu/bin/manage-feiyu.py web-token
echo.
echo Paste it at http://127.0.0.1:6099/webui/web_login
pause
