@echo off
setlocal EnableExtensions
title Docker Lab Studio - Hapus Resource Proyek
cd /d "%~dp0"

echo.
echo  ==============================================================
echo    DOCKER LAB STUDIO - HAPUS RESOURCE DOCKER MILIK PROYEK INI
echo  ==============================================================
echo.
echo  Skrip ini akan:
echo    - Menghentikan dan menghapus container proyek
echo    - Menghapus named volume dbdata BESERTA DATA DATABASE
echo    - Menghapus network Docker Compose milik proyek
echo    - Menghapus image aplikasi lokal yang dibuat oleh Compose
echo    - Menghentikan dashboard controller proyek ini
echo.
echo  Skrip ini TIDAK menghapus:
echo    - Folder/source code, file .env, laporan, atau screenshot
echo    - Docker Desktop
echo    - Image dasar mysql:8.4
echo    - Container, volume, network, dan image proyek lain
echo.
echo  PERINGATAN: data database pada volume proyek akan hilang permanen.
echo.

if not exist "%~dp0scripts\cleanup-project.ps1" (
  echo [ERROR] File scripts\cleanup-project.ps1 tidak ditemukan.
  echo Pastikan seluruh isi ZIP sudah diekstrak dan file tidak dipindahkan.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\cleanup-project.ps1" -ProjectRoot "%~dp0."
set "CLEANUP_RC=%ERRORLEVEL%"

echo.
if "%CLEANUP_RC%"=="0" (
  echo [SELESAI] Proses pembersihan telah selesai atau dibatalkan oleh pengguna.
) else (
  echo [GAGAL] Pembersihan tidak selesai. Baca pesan di atas dan perbaiki masalahnya.
)
echo.
pause
exit /b %CLEANUP_RC%
