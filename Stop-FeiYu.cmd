@echo off
set WSL_UTF8=1
wsl -d Ubuntu -u root -- python3 /opt/feiyu/bin/manage-feiyu.py stop
pause
