@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-bookmarks.ps1"
if %errorlevel% neq 0 pause
