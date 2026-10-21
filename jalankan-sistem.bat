@echo off
setlocal EnableExtensions
title Docker Lab Studio - Startup
cd /d "%~dp0"

echo.
echo  ==========================================================
echo    DOCKER LAB STUDIO - FLASK + MYSQL
echo  ==========================================================
echo.

where docker >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Docker CLI tidak ditemukan.
  echo Pasang Docker Desktop untuk Windows terlebih dahulu.
  echo Panduan: https://docs.docker.com/desktop/setup/install/windows-install/
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\initialize-env.ps1" -ProjectRoot "%~dp0."
if errorlevel 1 (
  echo [ERROR] Gagal membuat konfigurasi .env.
  pause
  exit /b 1
)

docker info >nul 2>nul
if errorlevel 1 (
  echo [INFO] Docker Engine belum siap. Mencoba membuka Docker Desktop...
  if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" (
    start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
  ) else if exist "%LOCALAPPDATA%\Docker\Docker Desktop.exe" (
    start "" "%LOCALAPPDATA%\Docker\Docker Desktop.exe"
  ) else (
    echo [ERROR] Docker Desktop tidak ditemukan pada lokasi standar.
    echo Buka Docker Desktop secara manual, lalu jalankan file BAT ini lagi.
    pause
    exit /b 1
  )
)

echo [INFO] Menunggu Docker Engine siap...
set /a attempts=0
:waitdocker
docker info >nul 2>nul
if not errorlevel 1 goto dockerready
set /a attempts+=1
if %attempts% GEQ 60 (
  echo [ERROR] Docker Engine belum siap setelah 2 menit.
  echo Periksa Docker Desktop, WSL 2, virtualisasi, dan koneksi internet.
  pause
  exit /b 1
)
timeout /t 2 /nobreak >nul
goto waitdocker

:dockerready
echo [OK] Docker Engine siap.
echo [INFO] Memulai dashboard kontrol lokal...
start "Docker Lab Controller" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dashboard\controller.ps1" -ProjectRoot "%~dp0."

set /a apiAttempts=0
:waitapi
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/version' -TimeoutSec 2; if ($r.version -eq '2.0') { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
if not errorlevel 1 goto apiready
set /a apiAttempts+=1
if %apiAttempts% GEQ 20 (
  echo [ERROR] Dashboard controller versi 2.0 tidak merespons pada port 8765.
  echo Jika controller versi lama masih berjalan, tutup jendela PowerShell controller lama lalu coba lagi.
  echo Periksa apakah port 8765 sedang dipakai aplikasi lain.
  pause
  exit /b 1
)
timeout /t 1 /nobreak >nul
goto waitapi

:apiready
echo [INFO] Menjalankan Docker Compose. Build pertama dapat memerlukan waktu dan internet...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$body = @{ action = 'up' } | ConvertTo-Json -Compress; $r=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/action' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 900; if ($r.output) { $r.output }; if ($r.exitCode -ne 0) { exit 1 }"
if errorlevel 1 (
  echo.
  echo [WARNING] Perintah Compose mengalami error. Dashboard tetap akan dibuka agar log bisa diperiksa.
)

echo.
echo [INFO] Menunggu Flask dan MySQL siap...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$deadline=(Get-Date).AddSeconds(100); $ready=$false; do { try { $r=Invoke-RestMethod -Uri 'http://127.0.0.1:5000/health' -TimeoutSec 2; if ($r.status -eq 'ok') { $ready=$true; break } } catch {}; Start-Sleep -Seconds 2 } while ((Get-Date) -lt $deadline); if ($ready) { Write-Host '[OK] Flask dan MySQL siap.' -ForegroundColor Green } else { Write-Host '[WARNING] Aplikasi belum melaporkan status siap. Periksa log pada dashboard.' -ForegroundColor Yellow }"

echo [INFO] Membuka dashboard di browser...
start "" "http://127.0.0.1:8765/"

echo.
echo  Dashboard : http://127.0.0.1:8765/
echo  Aplikasi  : http://127.0.0.1:5000/
echo.
echo Jangan menghapus file .env. Gunakan reset-database.bat hanya saat ingin menghapus data.
echo.
pause
