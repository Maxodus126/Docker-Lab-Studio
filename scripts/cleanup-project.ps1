[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace([string]$ProjectRoot)) {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
    }
    # Defend against a literal trailing quote from a malformed Windows batch argument.
    $ProjectRoot = ([string]$ProjectRoot).Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        throw 'Alamat folder proyek kosong.'
    }
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
} catch {
    Write-Host '[ERROR] Alamat folder proyek tidak valid.' -ForegroundColor Red
    Write-Host ("Nilai ProjectRoot yang diterima: <{0}>" -f $ProjectRoot) -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
$ComposeFile = Join-Path $ProjectRoot 'compose.yaml'
$ControllerFile = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'dashboard\controller.ps1'))
$ExpectedProject = 'flask-mysql-docker-lab'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}
function Write-Ok([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
}
function Write-Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}
function Write-Fail([string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Invoke-ProjectCompose {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    # Compose requires interpolated passwords in compose.yaml even for "down".
    # Temporary process-only placeholders let cleanup work even if .env is absent.
    # Existing .env is never read, edited, or deleted by this script.
    $names = @(
        'MYSQL_ROOT_PASSWORD',
        'MYSQL_PASSWORD',
        'MYSQL_DATABASE',
        'MYSQL_USER',
        'FLASK_SECRET_KEY'
    )
    $saved = @{}
    foreach ($name in $names) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }

    try {
        $env:MYSQL_ROOT_PASSWORD = 'cleanup-placeholder-not-a-real-secret'
        $env:MYSQL_PASSWORD = 'cleanup-placeholder-not-a-real-secret'
        $env:MYSQL_DATABASE = 'studentdb'
        $env:MYSQL_USER = 'studentapp'
        $env:FLASK_SECRET_KEY = 'cleanup-placeholder-not-a-real-secret'

        $commandOutput = @(& docker compose --project-directory $ProjectRoot -f $ComposeFile @Arguments 2>&1)
        $commandExitCode = [int]$LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $commandExitCode
            Output = @($commandOutput | ForEach-Object { [string]$_ })
        }
    }
    finally {
        foreach ($name in $names) {
            $oldValue = $saved[$name]
            [Environment]::SetEnvironmentVariable($name, $oldValue, 'Process')
        }
    }
}

Write-Host ''
Write-Host 'Docker Lab Studio - Pembersihan resource proyek' -ForegroundColor Cyan
Write-Host "Folder proyek : $ProjectRoot"
Write-Host "Compose project: $ExpectedProject"
Write-Host ''
Write-Host 'YANG AKAN DIHAPUS:' -ForegroundColor Yellow
Write-Host '  - Container Compose proyek ini'
Write-Host '  - Named volume proyek (termasuk seluruh data database)'
Write-Host '  - Network Compose proyek ini'
Write-Host '  - Image aplikasi lokal yang dikelola Compose'
Write-Host '  - Proses dashboard controller dari folder proyek ini'
Write-Host ''
Write-Host 'YANG DIPERTAHANKAN: source code, .env, laporan, screenshot, Docker Desktop,'
Write-Host 'image dasar mysql:8.4, dan resource Docker dari proyek lain.'
Write-Host ''

if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    Write-Fail "compose.yaml tidak ditemukan di folder proyek: $ProjectRoot"
    exit 1
}

$confirmation = Read-Host 'Jika sudah paham bahwa data database akan dihapus, ketik HAPUS'
if ($confirmation -cne 'HAPUS') {
    Write-Warn 'Dibatalkan. Tidak ada perintah penghapusan yang dijalankan.'
    exit 0
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Fail 'Docker CLI tidak ditemukan. Pastikan Docker Desktop terpasang.'
    exit 1
}

Write-Info 'Memeriksa apakah Docker Engine aktif...'
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Fail 'Docker Engine belum siap. Buka Docker Desktop, tunggu sampai aktif, lalu ulangi.'
    exit 1
}
Write-Ok 'Docker Engine merespons.'

Write-Info 'Memastikan nama proyek Compose sesuai dengan compose.yaml...'
$composeText = Get-Content -LiteralPath $ComposeFile -Raw
$namePattern = '(?m)^\s*name\s*:\s*["'']?flask-mysql-docker-lab["'']?\s*(?:#.*)?$'
if ($composeText -notmatch $namePattern) {
    Write-Fail "compose.yaml tidak menyatakan name: $ExpectedProject. Penghapusan dibatalkan agar proyek lain tidak tersentuh."
    exit 1
}
Write-Ok "Nama proyek terverifikasi: $ExpectedProject."

Write-Host ''
Write-Info 'Menjalankan pembersihan resource proyek: down --volumes --rmi local --remove-orphans'
Write-Host 'Perintah ini dibatasi pada compose.yaml di folder proyek ini.' -ForegroundColor DarkGray

$downResult = Invoke-ProjectCompose -Arguments @('down', '--volumes', '--rmi', 'local', '--remove-orphans')
foreach ($line in $downResult.Output) {
    if (-not [string]::IsNullOrWhiteSpace([string]$line)) { Write-Host ([string]$line) }
}
$downExitCode = [int]$downResult.ExitCode
if ($downExitCode -ne 0) {
    Write-Fail "docker compose down gagal dengan exit code $downExitCode."
    Write-Host 'Dashboard controller sengaja tidak dihentikan agar log masih dapat diperiksa.' -ForegroundColor Yellow
    exit $downExitCode
}
Write-Ok 'Perintah Docker Compose selesai tanpa error.'

# Stop only PowerShell processes whose command line references this project's exact controller file.
# Do not stop arbitrary PowerShell processes or controllers from another project folder.
try {
    $processes = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop
    $stoppedCount = 0
    foreach ($process in $processes) {
        if (-not $process.CommandLine) { continue }
        if ($process.ProcessId -eq $PID) { continue }
        if ($process.CommandLine.IndexOf($ControllerFile, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            try {
                Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
                $stoppedCount++
            }
            catch {
                Write-Warn "Tidak dapat menghentikan controller PID $($process.ProcessId): $($_.Exception.Message)"
            }
        }
    }
    if ($stoppedCount -gt 0) {
        Start-Sleep -Milliseconds 700
        Write-Ok "Dashboard controller proyek dihentikan ($stoppedCount proses)."
    }
    else {
        Write-Info 'Tidak ada proses dashboard controller proyek yang masih berjalan.'
    }
}
catch {
    Write-Warn "Pemeriksaan controller tidak dapat diselesaikan: $($_.Exception.Message)"
}

Write-Host ''
Write-Info 'Memverifikasi container, volume, dan network proyek yang tersisa...'
$verifyResult = Invoke-ProjectCompose -Arguments @('ps', '--all', '--quiet')
$remainingContainers = @($verifyResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$verifyExit = [int]$verifyResult.ExitCode

# Query Docker labels to confirm Compose-managed volumes and networks are gone.
$remainingVolumes = @(& docker volume ls --quiet --filter "label=com.docker.compose.project=$ExpectedProject")
$volumeExit = [int]$LASTEXITCODE
$remainingNetworks = @(& docker network ls --quiet --filter "label=com.docker.compose.project=$ExpectedProject")
$networkExit = [int]$LASTEXITCODE
if ($verifyExit -ne 0 -or $volumeExit -ne 0 -or $networkExit -ne 0) {
    Write-Warn 'Pembersihan sudah dijalankan, tetapi sebagian pemeriksaan akhir tidak dapat diselesaikan.'
    Write-Host 'Jalankan docker compose ps -a dan periksa Docker Desktop secara manual.'
    exit 2
}

$remainingContainers = @($remainingContainers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$remainingVolumes = @($remainingVolumes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$remainingNetworks = @($remainingNetworks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

if ($remainingContainers.Count -eq 0 -and $remainingVolumes.Count -eq 0 -and $remainingNetworks.Count -eq 0) {
    Write-Ok 'Tidak ditemukan container, volume, atau network Compose milik proyek ini.'
    Write-Host ''
    Write-Host 'PEMBERSIHAN SELESAI.' -ForegroundColor Green
    Write-Host 'Resource runtime proyek telah dibersihkan. Folder proyek dan file .env tetap tersedia.'
    Write-Host 'Untuk praktik ulang, klik jalankan-sistem.bat.'
    exit 0
}

Write-Warn 'Masih ada resource yang terdeteksi setelah pembersihan:'
if ($remainingContainers.Count -gt 0) { Write-Host ('  Container: ' + ($remainingContainers -join ', ')) }
if ($remainingVolumes.Count -gt 0) { Write-Host ('  Volume   : ' + ($remainingVolumes -join ', ')) }
if ($remainingNetworks.Count -gt 0) { Write-Host ('  Network  : ' + ($remainingNetworks -join ', ')) }
Write-Host 'Periksa apakah resource dibuat secara manual atau memakai nama proyek yang berbeda.'
exit 2
