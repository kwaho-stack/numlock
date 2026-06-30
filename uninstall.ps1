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

# --- 1b) Apply immediately (no reboot) by restarting the keyboard stack ---
try {
    $kbd = Get-PnpDevice -Class Keyboard -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -eq 'OK' }
    if ($kbd) {
        $kbd | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        $kbd | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {
} finally {
    Get-PnpDevice -Class Keyboard -PresentOnly -ErrorAction SilentlyContinue | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
}

# --- 2) Remove the scheduled task, running process, startup entry, and files ---
Unregister-ScheduledTask -TaskName 'KeyLock' -Confirm:$false -ErrorAction SilentlyContinue

$dest    = Join-Path $env:LOCALAPPDATA 'KeyLock'
$startup = [Environment]::GetFolderPath('Startup')
Remove-Item (Join-Path $startup 'KeyLock.vbs') -Force   # old launcher from earlier versions

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item $dest -Recurse -Force

Write-Host ''
Write-Host '  [OK] Uninstalled. NumLock/CapsLock keys are free again.' -ForegroundColor Green
Write-Host '       (CapsLock fully restores after a reboot, or right away on most PCs.)' -ForegroundColor Yellow
Write-Host ''
Read-Host '  Press Enter to close'
