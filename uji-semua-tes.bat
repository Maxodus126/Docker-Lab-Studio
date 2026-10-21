@echo off
setlocal
title Docker Lab Studio - Jalankan Semua Tes
cd /d "%~dp0"
echo.
echo Docker Lab Studio - Test Center
echo Pastikan jalankan-sistem.bat sudah berhasil dan dashboard terbuka.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uji-semua-tes.ps1" %*
echo.
echo Kode keluar: %ERRORLEVEL%
pause
