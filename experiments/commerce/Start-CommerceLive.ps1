$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$downloads = Join-Path $repo 'runtime\downloads'
$release = 'scrcpy-win64-v5.0.1'
$directory = Join-Path $downloads $release
$viewer = Join-Path $directory 'scrcpy.exe'

try {
    if (-not (Test-Path -LiteralPath $viewer)) {
        New-Item -ItemType Directory -Path $downloads -Force | Out-Null
        $archive = Join-Path $downloads "$release.zip"
        $sha256 = 'b12a2c4ee8be317422451fc7dcf8ee20a71b5ea7ef9ad73ddd825a25316227a5'
        if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive).Hash -ne $sha256) {
            Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/$release.zip" -OutFile $archive -TimeoutSec 120
        }
        if ((Get-FileHash -LiteralPath $archive).Hash -ne $sha256) { throw 'scrcpy download checksum mismatch.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $downloads -Force
    }

    $existing = Get-Process -Name scrcpy -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -eq $viewer -and $_.MainWindowTitle -eq 'FeiYu Android Live'
    }
    if ($existing) {
        Write-Host 'Switch to the FeiYu Android Live window on the Windows taskbar.'
        exit 0
    }

    & (Join-Path $PSScriptRoot 'Start-Commerce.ps1') -NoBrowser
    $adb = '/opt/feiyu/android-sdk/platform-tools/adb'
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        $device = & wsl.exe -d Ubuntu -u root -- runuser -u feiyu -- $adb -s emulator-5580 emu avd name 2>$null
        if ($LASTEXITCODE -eq 0 -and $device -contains 'FeiYuCommerce') { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($device -notcontains 'FeiYuCommerce') { throw 'The FeiYuCommerce Android device did not start.' }

    $launch = [Diagnostics.ProcessStartInfo]::new($viewer)
    $launch.WorkingDirectory = $directory
    $launch.UseShellExecute = $false
    $launch.CreateNoWindow = $true
    $launch.EnvironmentVariables['ADB_SERVER_SOCKET'] = 'tcp:127.0.0.1:5037'
    $launch.Arguments = '--serial=emulator-5580 --tunnel-host=127.0.0.1 --tunnel-port=27186 --port=27186 --no-audio --max-size=960 --max-fps=30 --video-bit-rate=2M --window-title="FeiYu Android Live"'
    $process = [Diagnostics.Process]::Start($launch)
    if ($process.WaitForExit(2000)) { throw "scrcpy closed during startup (exit $($process.ExitCode))." }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
