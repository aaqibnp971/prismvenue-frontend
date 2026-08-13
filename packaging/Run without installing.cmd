@echo off
REM Launches the app straight out of the extracted folder - no install, no
REM shortcuts, nothing written outside the app's own data directory. Useful for
REM a USB stick or a machine you do not want to leave anything on.
start "" "%~dp0app\prism_venues.exe"
