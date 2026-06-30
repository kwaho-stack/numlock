# install.ps1 - Installs the NumLock(ON)/CapsLock(OFF) locker and registers it to run at logon.
# All paths are handled by PowerShell so Korean user names in the path are safe.
$ErrorActionPreference = 'Stop'

$dest    = Join-Path $env:LOCALAPPDATA 'KeyLock'
$startup = [Environment]::GetFolderPath('Startup')

# 1) Copy the locker script into a permanent location.
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
Copy-Item (Join-Path $PSScriptRoot 'KeyLock.ps1') (Join-Path $dest 'KeyLock.ps1') -Force
$ps1 = Join-Path $dest 'KeyLock.ps1'

# 2) Create a hidden launcher in the Startup folder (runs at every logon -> survives reboot).
$vbs = Join-Path $startup 'KeyLock.vbs'
$launcher = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$ps1""", 0, False
"@
Set-Content -Path $vbs -Value $launcher -Encoding Unicode

# 3) Stop any previous instance, then start now.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Process wscript.exe -ArgumentList "`"$vbs`""

Write-Host ''
Write-Host '  [OK] Installed.' -ForegroundColor Green
Write-Host '       - NumLock  : always ON  (locked)'
Write-Host '       - CapsLock : always OFF (locked)'
Write-Host '       - Auto-applies after every reboot.'
Write-Host '  To remove, run: 제거.bat'
Write-Host ''
