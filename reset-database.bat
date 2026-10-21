@echo off
setlocal
title Docker Lab Studio - Reset Database
cd /d "%~dp0"
echo.
echo  PERINGATAN: RESET DATABASE
echo  Perintah ini akan menghapus container, network, dan named volume Compose.
echo  Semua data mahasiswa yang hanya tersimpan pada volume dbdata akan hilang.
echo.
choice /C YN /N /M "Y = lanjutkan reset, N = batalkan: "
if errorlevel 2 (
  echo Reset dibatalkan. Data tidak diubah oleh skrip ini.
  pause
  exit /b 0
)
where docker >nul 2>nul
if errorlevel 1 (
  echo Docker CLI tidak ditemukan. Pasang atau jalankan Docker Desktop terlebih dahulu.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\initialize-env.ps1" -ProjectRoot "%~dp0."
if errorlevel 1 (
  echo Gagal menyiapkan file .env. Reset dibatalkan.
  pause
  exit /b 1
)
docker info >nul 2>nul
if errorlevel 1 (
  echo Docker Engine belum siap. Buka Docker Desktop lalu ulangi.
  pause
  exit /b 1
)
docker compose down -v
if errorlevel 1 (
  echo Reset gagal. Periksa Docker Desktop dan pesan di atas.
  pause
  exit /b 1
)
echo.
echo Volume Compose dihapus. Menjalankan kembali aplikasi...
docker compose up -d --build
if errorlevel 1 (
  echo Aplikasi belum berhasil dijalankan kembali. Periksa error di atas.
  pause
  exit /b 1
)
echo.
echo Reset selesai. Database baru akan dibuat dan tabel mahasiswa kosong.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/version' -TimeoutSec 2; if ($r.version -eq '2.0') { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
if errorlevel 1 (
  echo Dashboard controller belum aktif. Jalankan jalankan-sistem.bat untuk membuka dashboard.
) else (
  start "" "http://127.0.0.1:8765/"
)
pause
