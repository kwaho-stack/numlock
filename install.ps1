# install.ps1
# 넘버락/캡스락 키를 드라이버 단계(Scancode Map)에서 완전히 비활성화하고,
# 부팅 시 넘버락이 항상 ON 이 되도록 설정한다.
#  - 캡스락 : 키가 죽어 있고 기본값이 OFF -> 항상 꺼짐
#  - 넘버락 : 키가 죽어 있고 부팅 시 ON 으로 설정 -> 항상 켜짐
# HKLM 에 쓰기 때문에 관리자 권한이 필요하고, 적용에는 재부팅이 1회 필요하다.

$ErrorActionPreference = 'Stop'

# --- 관리자 권한으로 자동 승격 ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

# --- 1) Scancode Map 으로 넘버락(0x45)/캡스락(0x3A) 물리 키 비활성화 ---
# 형식: [버전 4B][플래그 4B][매핑개수 4B][매핑들...][종료자 4B]
# 매핑 1개 = (새 스캔코드 2B = 00 00 -> 비활성화)(원래 스캔코드 2B)
$map = [byte[]](
    0,0,0,0,          # version
    0,0,0,0,          # flags
    3,0,0,0,          # 매핑 개수 = 비활성화 2개 + 종료자 1개
    0,0,0x3A,0,       # CapsLock(0x3A) -> 비활성화
    0,0,0x45,0,       # NumLock (0x45) -> 비활성화
    0,0,0,0           # 종료자
)
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' `
                 -Name 'Scancode Map' -Value $map -Type Binary

# --- 2) 부팅 시 넘버락 ON (로그인 화면 + 현재 사용자) ---
Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' `
                 -Name 'InitialKeyboardIndicators' -Value '2'
Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' `
                 -Name 'InitialKeyboardIndicators' -Value '2'

# --- 3) 로그인 때마다 넘버락 ON / 캡스락 OFF 를 한 번 더 보장 (재부팅 전 보조) ---
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
Write-Host '      (재부팅을 한 번 해야 모든 곳에서 키가 완전히 먹통이 됩니다.)'
Write-Host ''
Read-Host '  Press Enter to close'
