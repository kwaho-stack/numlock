# install.ps1
# CapsLock is disabled at the driver level (Scancode Map). NumLock is kept ON and
# blocked by an ELEVATED low-level keyboard hook (the Scancode Map does not reliably
# disable NumLock on some systems, so the hook is the reliable layer for it).
# The hook runs at every logon via a Scheduled Task with highest privileges, so it
# covers all apps including elevated ones. Applies immediately (no reboot).
# Writing to HKLM and creating the task need admin rights.

$ErrorActionPreference = 'Stop'

# --- Self-elevate to administrator ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

# --- 1) Disable CapsLock (0x3A) and NumLock (0x45) physical keys via Scancode Map ---
# (CapsLock blocks reliably here; NumLock kept too as a bonus but the hook is its real fix.)
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

# --- 3) Install the helper and a hidden launcher ---
$dest = Join-Path $env:LOCALAPPDATA 'KeyLock'
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
Copy-Item (Join-Path $PSScriptRoot 'KeyLock.ps1') (Join-Path $dest 'KeyLock.ps1') -Force
$ps1 = Join-Path $dest 'KeyLock.ps1'
$vbs = Join-Path $dest 'KeyLock.vbs'
$launcher = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$ps1""", 0, False
"@
Set-Content -Path $vbs -Value $launcher -Encoding Unicode

# Clean up the old Startup-folder launcher from previous versions, if present.
$oldVbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'KeyLock.vbs'
if (Test-Path $oldVbs) { Remove-Item $oldVbs -Force -ErrorAction SilentlyContinue }

# --- 4) Register a Scheduled Task: run the helper ELEVATED + hidden at every logon ---
$action    = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbs`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'KeyLock' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

# --- 5) Apply the CapsLock Scancode Map NOW (no reboot) by restarting the keyboard ---
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
    Get-PnpDevice -Class Keyboard -PresentOnly -ErrorAction SilentlyContinue | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
}

# --- 6) Start the helper NOW (elevated) so NumLock is locked immediately ---
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
# Launch directly (this install runs elevated, so the child is elevated too).
Start-Process wscript.exe -ArgumentList "`"$vbs`""
Start-Sleep -Milliseconds 1200
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
           Where-Object { $_.CommandLine -like '*KeyLock.ps1*' }
if (-not $running) {
    Write-Host '  [WARN] Helper did not start via launcher; starting directly...' -ForegroundColor Yellow
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`""
    Start-Sleep -Milliseconds 1200
}

Write-Host ''
Write-Host '  [OK] Installed and applied immediately (no reboot needed).' -ForegroundColor Green
Write-Host '       - NumLock  : always ON  (key blocked by elevated hook)'
Write-Host '       - CapsLock : always OFF (key disabled at driver level)'
Write-Host ''
Write-Host '  Test NumLock/CapsLock in any app now.' -ForegroundColor Yellow
Write-Host '  If something still toggles, see: %LOCALAPPDATA%\KeyLock\error.log' -ForegroundColor Yellow
Write-Host ''
Read-Host '  Press Enter to close'
