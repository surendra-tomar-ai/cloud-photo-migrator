@echo off
rem Double-click to start (or resume) the migration using config.psd1.
rem Extra arguments are passed through, e.g.  start.cmd -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0migrate.ps1" %*
echo.
pause
