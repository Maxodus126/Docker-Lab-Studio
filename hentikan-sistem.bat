@echo off
setlocal
title Docker Lab Studio - Stop
cd /d "%~dp0"
echo.
where docker >nul 2>nul
if errorlevel 1 (
  echo Docker CLI tidak ditemukan. Pastikan Docker Desktop terpasang.
  pause
  exit /b 1
)
docker info >nul 2>nul
if errorlevel 1 (
  echo Docker Engine belum siap. Buka Docker Desktop lalu ulangi.
  pause
  exit /b 1
)
echo Menghentikan container proyek tanpa menghapus volume database...
docker compose down
if errorlevel 1 (
  echo.
  echo Gagal menghentikan proyek. Pastikan Docker Desktop aktif.
  pause
  exit /b 1
)
echo.
echo Selesai. Volume dbdata tetap dipertahankan agar data mahasiswa tidak hilang.
pause
