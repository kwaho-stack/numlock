@echo off
chcp 65001 >nul
setlocal
title KeyLock 제거

set "DEST=%LOCALAPPDATA%\KeyLock"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

echo.
echo  넘버락/캡스락 고정 프로그램을 제거합니다...
echo.

rem 1) 시작프로그램 등록 삭제
del /Q "%STARTUP%\KeyLock.vbs" 2>nul

rem 2) 실행 중인 프로세스 종료 (KeyLock.ps1 을 실행 중인 powershell 만)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*KeyLock.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" 2>nul

rem 3) 설치 폴더 삭제
rmdir /S /Q "%DEST%" 2>nul

echo  제거 완료! 이제 넘버락/캡스락 키를 다시 자유롭게 쓸 수 있습니다.
echo.
pause
