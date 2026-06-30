@echo off
chcp 65001 >nul
setlocal
title KeyLock 설치

set "DEST=%LOCALAPPDATA%\KeyLock"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

echo.
echo  넘버락(ON) / 캡스락(OFF) 고정 프로그램을 설치합니다...
echo.

rem 1) 설치 폴더에 스크립트 복사
if not exist "%DEST%" mkdir "%DEST%"
copy /Y "%~dp0KeyLock.ps1" "%DEST%\KeyLock.ps1" >nul

rem 2) 시작프로그램에 숨김 실행용 런처(.vbs) 생성 -> 재부팅해도 자동 실행
> "%STARTUP%\KeyLock.vbs" echo Set sh = CreateObject("WScript.Shell")
>> "%STARTUP%\KeyLock.vbs" echo sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%DEST%\KeyLock.ps1""", 0, False

rem 3) 지금 바로 실행
wscript "%STARTUP%\KeyLock.vbs"

echo  설치 완료!
echo   - 넘버락: 항상 켜짐(ON) 고정
echo   - 캡스락: 항상 꺼짐(OFF) 고정
echo   - 컴퓨터를 껐다 켜도 자동으로 적용됩니다.
echo.
echo  해제하려면 "제거.bat" 를 실행하세요.
echo.
pause
