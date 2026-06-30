# install.ps1
# Disables the NumLock/CapsLock keys at the driver level (Scancode Map) and makes
# NumLock stay ON. Applies IMMEDIATELY (no reboot) by restarting the keyboard device
# so the driver re-reads the Scancode Map, plus an elevated low-level hook as backup.
#   - CapsLock: key is dead and OFF  -> always OFF
#   - NumLock : key is dead and ON   -> always ON
# Writing to HKLM needs admin rights.

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

# --- 3) Install the backup helper + register it to run at every logon ---
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

# --- 4) Apply the Scancode Map NOW (no reboot) by restarting the keyboard stack ---
# Disabling/enabling the keyboard device forces the driver to re-read the Scancode Map.
try {
    $kbd = Get-PnpDevice -Class Keyboard -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -eq 'OK' }
    if ($kbd) {
        $kbd | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        $kbd | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
    }
} catch {
} finally {
    # Safety: make sure every keyboard is enabled again no matter what.
    Get-PnpDevice -Class Keyboard -PresentOnly -ErrorAction SilentlyContinue | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
}

# --- 5) Start the helper NOW (elevated, hidden). It forces NumLock ON / CapsLock OFF
#         and, as a backup, blocks the keys in normal + elevated apps immediately. ---
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Process wscript.exe -ArgumentList "`"$vbs`""

Write-Host ''
Write-Host '  [OK] Installed and applied immediately (no reboot needed).' -ForegroundColor Green
Write-Host '       - NumLock  : always ON  (key disabled at driver level)'
Write-Host '       - CapsLock : always OFF (key disabled at driver level)'
Write-Host ''
Write-Host '  Test it now in any app. If a key still works somewhere, reboot once' -ForegroundColor Yellow
Write-Host '  to guarantee it (the driver always reloads the Scancode Map on boot).' -ForegroundColor Yellow
Write-Host ''
Read-Host '  Press Enter to close'
