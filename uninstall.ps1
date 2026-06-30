# uninstall.ps1
# Removes the Scancode Map (re-enables the keys) and cleans up the startup entry,
# running helper process, and installed files.
# Writing to HKLM needs admin rights; a single reboot is required to restore the keys.

$ErrorActionPreference = 'SilentlyContinue'

# --- Self-elevate to administrator ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

# --- 1) Remove Scancode Map -> re-enable NumLock/CapsLock keys ---
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map' -ErrorAction SilentlyContinue

# --- 2) Clean up startup entry / running process / files ---
$dest    = Join-Path $env:LOCALAPPDATA 'KeyLock'
$startup = [Environment]::GetFolderPath('Startup')
Remove-Item (Join-Path $startup 'KeyLock.vbs') -Force

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item $dest -Recurse -Force

Write-Host ''
Write-Host '  [OK] Uninstalled.' -ForegroundColor Green
Write-Host '  >>> Please REBOOT once to re-enable the NumLock/CapsLock keys. <<<' -ForegroundColor Yellow
Write-Host ''
Read-Host '  Press Enter to close'
