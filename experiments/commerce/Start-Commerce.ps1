param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
Start-Process -FilePath 'wsl.exe' -ArgumentList '-d Ubuntu -u root -- flock -n /var/lib/feiyu/wsl-keepalive.lock sleep infinity' -WindowStyle Hidden
& wsl.exe -d Ubuntu -u root -- systemctl start feiyu-commerce-phone.service feiyu-commerce.service
if ($LASTEXITCODE -ne 0) { throw 'Commerce runtime is not installed. See experiments/commerce/README.md.' }
$panelUrl = & wsl.exe -d Ubuntu -u root -- python3 -c "import pathlib,time; from urllib.parse import urlunsplit; p=pathlib.Path('/var/lib/feiyu/commerce/panel-token'); deadline=time.monotonic()+15; exec('while not p.exists() and time.monotonic()<deadline: time.sleep(.2)'); print(urlunsplit(('http','127.0.0.1:6088','/','',p.read_text().strip())))"
if ($LASTEXITCODE -ne 0) { throw 'Commerce panel did not start.' }
Write-Host 'Commerce ready. Login in the Android window; tasks stop before order submission/payment.'
if (-not $NoBrowser) { Start-Process -FilePath ($panelUrl | Select-Object -Last 1) }
