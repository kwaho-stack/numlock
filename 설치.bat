@echo off
rem ASCII-only launcher. Real work is done by install.ps1 (encoding-safe).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
pause
