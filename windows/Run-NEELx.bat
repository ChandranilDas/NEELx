@echo off
title Launching NEELx...
cd /d "%~dp0"
:: Clear Windows Defender SmartScreen Mark-of-the-Web from all extracted files
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | ForEach-Object { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }"
start "" "%~dp0NEELx.Windows.exe"
