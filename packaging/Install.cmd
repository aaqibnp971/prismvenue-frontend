@echo off
REM Double-click entry point. A .ps1 opens in Notepad when double-clicked, so
REM the installer is always reached through this wrapper, which also lifts the
REM execution policy for this single call only.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
echo.
pause
