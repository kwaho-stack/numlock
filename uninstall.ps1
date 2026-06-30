# uninstall.ps1 - Removes the locker: startup entry, running process, and installed files.
$ErrorActionPreference = 'SilentlyContinue'

$dest    = Join-Path $env:LOCALAPPDATA 'KeyLock'
$startup = [Environment]::GetFolderPath('Startup')
$vbs     = Join-Path $startup 'KeyLock.vbs'

# 1) Remove the startup launcher.
Remove-Item $vbs -Force

# 2) Stop the running locker process (only the one running KeyLock.ps1).
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# 3) Remove the installed files.
Remove-Item $dest -Recurse -Force

Write-Host ''
Write-Host '  [OK] Uninstalled. NumLock / CapsLock keys are free again.' -ForegroundColor Green
Write-Host ''
