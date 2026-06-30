@echo off
rem Visible test: runs the NumLock/CapsLock locker in a normal window so you can
rem see whether the hook starts and whether NumLock gets locked.
rem While this window is OPEN, press NumLock / numpad keys to test.
rem Close the window to stop the test.
echo ================================================================
echo  TEST MODE - keep this window open and try NumLock / numpad keys
echo  (Run me as Administrator for the most accurate test.)
echo ================================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0KeyLock.ps1"
echo.
echo  (The locker stopped.)
pause
