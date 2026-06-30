@echo off
rem ASCII-only launcher. Real work is done by uninstall.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
pause
