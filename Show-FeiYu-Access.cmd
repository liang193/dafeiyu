@echo off
set WSL_UTF8=1
echo NapCat WebUI login token:
wsl -d Ubuntu -u root -- python3 /opt/feiyu/bin/manage-feiyu.py web-token
echo.
echo OneBot access token for the FeiYu panel:
wsl -d Ubuntu -u root -- python3 /opt/feiyu/bin/manage-feiyu.py onebot-token
echo.
echo Keep these local. Do not share screenshots.
pause
