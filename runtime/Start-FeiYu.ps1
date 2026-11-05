param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
try {
    Write-Host 'Starting FeiYu: Linux, QQ bridge and control panel...'
    Start-Process -FilePath 'wsl.exe' -ArgumentList '-d Ubuntu -u root -- flock -n /var/lib/feiyu/wsl-keepalive.lock sleep infinity' -WindowStyle Hidden
    $result = & wsl.exe -d Ubuntu -u root -- python3 /opt/feiyu/bin/manage-feiyu.py start
    if ($LASTEXITCODE -ne 0) { throw 'Startup failed. Run Status-FeiYu.cmd for details.' }
    $panelUrl = @($result | Where-Object { $_ -match '^http://127\.0\.0\.1:\d+/#[-a-fA-F0-9]+$' }) | Select-Object -Last 1
    if (-not $panelUrl) { throw 'The control panel did not return a valid local address.' }
    Write-Host 'Ready. QQ login, bot settings, Bilibili and Xiaohongshu are in one panel.'
    if (-not $NoBrowser) {
        try { Start-Process -FilePath $panelUrl }
        catch { Write-Host "Open this private address in your browser: $panelUrl" }
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
