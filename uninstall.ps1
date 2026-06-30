# uninstall.ps1
# Scancode Map(키 비활성화)을 제거하고, 시작프로그램 등록/실행/파일을 모두 정리한다.
# HKLM 을 수정하므로 관리자 권한이 필요하고, 키 복구에는 재부팅이 1회 필요하다.

$ErrorActionPreference = 'SilentlyContinue'

# --- 관리자 권한으로 자동 승격 ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

# --- 1) Scancode Map 제거 -> 넘버락/캡스락 키 다시 활성화 ---
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' `
                    -Name 'Scancode Map' -ErrorAction SilentlyContinue

# --- 2) 시작프로그램 등록/실행 프로세스/파일 정리 ---
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
Write-Host '      (재부팅을 한 번 해야 키가 원래대로 돌아옵니다.)'
Write-Host ''
Read-Host '  Press Enter to close'
