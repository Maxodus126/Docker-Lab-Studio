param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = "Stop"
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
$envPath = Join-Path $ProjectRoot ".env"

if (Test-Path $envPath) {
    Write-Host ".env sudah tersedia; tidak diubah." -ForegroundColor Green
    exit 0
}

function New-RandomHex([int]$ByteCount = 24) {
    $buffer = New-Object byte[] $ByteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($buffer)).Replace("-", "").ToLowerInvariant()
}

$rootPassword = New-RandomHex 24
$appPassword = New-RandomHex 24
$flaskSecret = New-RandomHex 32
$content = @"
MYSQL_ROOT_PASSWORD=$rootPassword
MYSQL_PASSWORD=$appPassword
MYSQL_DATABASE=studentdb
MYSQL_USER=studentapp
FLASK_SECRET_KEY=$flaskSecret
"@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envPath, $content, $utf8NoBom)
Write-Host ".env dibuat dengan password acak lokal. Jangan bagikan file ini." -ForegroundColor Green
