# install.ps1
# Disables the NumLock/CapsLock keys at the driver level (Scancode Map) and makes
# NumLock boot ON, so:
#   - CapsLock: key is dead and boots OFF  -> always OFF
#   - NumLock : key is dead and boots ON   -> always ON
# Writing to HKLM needs admin rights; a single reboot is required to take effect.

$ErrorActionPreference = 'Stop'

# --- Self-elevate to administrator ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

# --- 1) Disable NumLock (0x45) and CapsLock (0x3A) physical keys via Scancode Map ---
# Layout: [version 4B][flags 4B][count 4B][mappings...][terminator 4B]
# One mapping = (new scancode 2B = 00 00 -> disabled)(original scancode 2B)
$map = [byte[]](
    0,0,0,0,
    0,0,0,0,
    3,0,0,0,
    0,0,0x3A,0,
    0,0,0x45,0,
    0,0,0,0
)
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map' -Value $map -Type Binary

# --- 2) Make NumLock ON at boot (logon screen + current user) ---
Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2'
Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2'

# --- 3) Helper that re-asserts NumLock ON / CapsLock OFF at each logon (backup) ---
$dest    = Join-Path $env:LOCALAPPDATA 'KeyLock'
$startup = [Environment]::GetFolderPath('Startup')
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
Copy-Item (Join-Path $PSScriptRoot 'KeyLock.ps1') (Join-Path $dest 'KeyLock.ps1') -Force
$ps1 = Join-Path $dest 'KeyLock.ps1'

$vbs = Join-Path $startup 'KeyLock.vbs'
$launcher = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$ps1""", 0, False
"@
Set-Content -Path $vbs -Value $launcher -Encoding Unicode

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Process wscript.exe -ArgumentList "`"$vbs`""

Write-Host ''
Write-Host '  [OK] Installed.' -ForegroundColor Green
Write-Host '       - NumLock  : always ON  (key disabled at driver level)'
Write-Host '       - CapsLock : always OFF (key disabled at driver level)'
Write-Host ''
Write-Host '  >>> Please REBOOT once to fully disable the keys everywhere. <<<' -ForegroundColor Yellow
Write-Host ''
Read-Host '  Press Enter to close'
