param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

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
$DashboardFile = Join-Path $PSScriptRoot "index.html"
$ProjectName = "flask-mysql-docker-lab"
$script:RecentLog = New-Object System.Collections.ArrayList
$script:StartedAt = Get-Date
$script:TestRunning = $false
$script:LastReport = $null
$script:LastTestResults = @()
$script:ReportsDirectory = Join-Path $ProjectRoot "reports"

$script:TestCatalog = @(
    @{ id = "T01"; title = "Prasyarat & konfigurasi"; category = "Environment"; description = "Memeriksa Docker Engine, Docker Compose, file .env, dan validitas compose.yaml."; expected = "Docker Engine merespons; .env tersedia; Compose config valid."; destructive = $false },
    @{ id = "T02"; title = "Build & startup service"; category = "Startup"; description = "Build image Flask, jalankan service, lalu tunggu endpoint health siap."; expected = "Service web dan db berjalan; /health berstatus ok."; destructive = $false },
    @{ id = "T03"; title = "Create, read & delete mahasiswa"; category = "Application"; description = "Membuat data uji lewat formulir web, memastikan data tampil, lalu menghapus data uji."; expected = "Create, read, dan delete berhasil; data uji dibersihkan."; destructive = $false },
    @{ id = "T04"; title = "Persistensi named volume"; category = "Persistence"; description = "Membuat marker uji, menjalankan down lalu up, dan memverifikasi marker masih tersimpan."; expected = "Data marker tetap ada setelah container dibuat ulang; marker kemudian dibersihkan."; destructive = $false },
    @{ id = "T05"; title = "Pemulihan MySQL"; category = "Recovery"; description = "Stop database, periksa liveness dan degraded health, lalu start kembali dan tunggu sehat."; expected = "Flask tetap hidup saat DB berhenti dan kembali terhubung setelah DB pulih."; destructive = $false },
    @{ id = "T06"; title = "Reset volume database"; category = "Destructive"; description = "Menghapus volume dengan down -v, membuat ulang stack, lalu memastikan database baru kosong."; expected = "Volume lama dihapus dan database baru kosong."; destructive = $true },
    @{ id = "T07"; title = "Network internal & koneksi DB"; category = "Networking"; description = "Memeriksa resolusi DNS service db dan koneksi MySQL dari container Flask."; expected = "Hostname db ter-resolve dan koneksi MySQL berhasil dari container web."; destructive = $false },
    @{ id = "T08"; title = "Snapshot diagnostik"; category = "Diagnostics"; description = "Mengumpulkan status container, log service, volume, dan network untuk bukti pengujian."; expected = "Perintah diagnostik berjalan dan bukti aktual tercatat dalam laporan."; destructive = $false },
    @{ id = "T09"; title = "Port & storage configuration"; category = "Configuration"; description = "Memastikan Flask hanya dipublikasikan ke loopback, MySQL tidak dipublikasikan ke host, dan data memakai named volume."; expected = "Port web dibatasi ke 127.0.0.1; db tidak punya port host; dbdata dipasang ke /var/lib/mysql."; destructive = $false },
    @{ id = "T10"; title = "Validasi input & NIM duplikat"; category = "Validation"; description = "Menguji penolakan input kosong dan NIM duplikat melalui endpoint form, lalu membersihkan data uji."; expected = "Input kosong ditolak; NIM duplikat ditolak; hanya satu record uji tersimpan."; destructive = $false }
)

function Add-Log([string]$Message) {
    $stamp = (Get-Date).ToString("HH:mm:ss")
    [void]$script:RecentLog.Add("[$stamp] $Message")
    while ($script:RecentLog.Count -gt 240) { $script:RecentLog.RemoveAt(0) }
}

function Send-Response($Context, [int]$StatusCode, [string]$ContentType, [string]$Body, [string]$DownloadName = "") {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.Headers["Cache-Control"] = "no-store"
    if ($DownloadName) { $Context.Response.Headers["Content-Disposition"] = "attachment; filename=`"$DownloadName`"" }
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Send-Bytes($Context, [int]$StatusCode, [string]$ContentType, [byte[]]$Bytes, [string]$DownloadName = "") {
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentLength64 = $Bytes.Length
    $Context.Response.Headers["Cache-Control"] = "no-store"
    if ($DownloadName) { $Context.Response.Headers["Content-Disposition"] = "attachment; filename=`"$DownloadName`"" }
    $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Send-Json($Context, [int]$StatusCode, $Object) {
    $json = ConvertTo-Json -InputObject $Object -Depth 12 -Compress
    Send-Response $Context $StatusCode "application/json; charset=utf-8" $json
}

function Invoke-Docker([string[]]$DockerArgs) {
    try {
        $outputLines = @(& docker @DockerArgs 2>&1 | ForEach-Object { "$($_)" })
        $exitCode = $LASTEXITCODE
        $outputText = ($outputLines -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($outputText)) { $outputText = "(Tidak ada output.)" }
        Add-Log ("docker " + ($DockerArgs -join " ") + "  [exit $exitCode]")
        foreach ($line in ($outputText -split "`r?`n")) { if (-not [string]::IsNullOrWhiteSpace($line)) { Add-Log $line } }
        return @{ output = $outputText; exitCode = [int]$exitCode }
    } catch {
        Add-Log ("ERROR docker: " + $_.Exception.Message)
        return @{ output = $_.Exception.Message; exitCode = 1 }
    }
}

function Invoke-Compose([string[]]$ComposeArgs) {
    Push-Location $ProjectRoot
    try {
        $outputLines = @(& docker compose @ComposeArgs 2>&1 | ForEach-Object { "$($_)" })
        $exitCode = $LASTEXITCODE
        $outputText = ($outputLines -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($outputText)) { $outputText = "(Tidak ada output.)" }
        Add-Log ("docker compose " + ($ComposeArgs -join " ") + "  [exit $exitCode]")
        foreach ($line in ($outputText -split "`r?`n")) { if (-not [string]::IsNullOrWhiteSpace($line)) { Add-Log $line } }
        return @{ output = $outputText; exitCode = [int]$exitCode }
    } catch {
        Add-Log ("ERROR Compose: " + $_.Exception.Message)
        return @{ output = $_.Exception.Message; exitCode = 1 }
    } finally { Pop-Location }
}

function Get-HttpHealth([string]$Path = "/health", [int]$TimeoutSec = 3) {
    try {
        $response = Invoke-RestMethod -Uri ("http://127.0.0.1:5000" + $Path) -TimeoutSec $TimeoutSec
        return @{ ok = $true; data = $response; statusCode = 200; error = "" }
    } catch {
        $statusCode = 0
        try { if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch {}
        return @{ ok = $false; data = $null; statusCode = $statusCode; error = $_.Exception.Message }
    }
}

function Wait-AppReady([int]$TimeoutSeconds = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    do {
        $last = Get-HttpHealth "/health" 3
        if ($last.ok -and $last.data.status -eq "ok" -and $last.data.database -eq "connected") { return @{ ok = $true; health = $last.data; message = "Flask dan MySQL siap." } }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    $detail = if ($last -and $last.error) { $last.error } elseif ($last -and $last.data) { ConvertTo-Json -InputObject $last.data -Compress } else { "Endpoint health belum merespons." }
    return @{ ok = $false; health = $(if ($last) { $last.data } else { $null }); message = $detail }
}

function Get-DashboardStatus {
    $dockerVersion = ""
    try { $dockerVersion = (& docker info --format '{{.ServerVersion}}' 2>$null | Out-String).Trim() } catch { $dockerVersion = "" }
    $dockerAvailable = -not [string]::IsNullOrWhiteSpace($dockerVersion)

    $containers = @()
    if ($dockerAvailable) {
        Push-Location $ProjectRoot
        try {
            $rawLines = @(& docker compose ps --all --format json 2>$null)
            foreach ($rawLine in $rawLines) {
                $line = "$rawLine".Trim()
                if (-not $line) { continue }
                try {
                    $parsed = ConvertFrom-Json -InputObject $line
                    if ($parsed -is [System.Array]) { foreach ($item in $parsed) { $containers += $item } }
                    else { $containers += $parsed }
                } catch {
                    try {
                        $parsedArray = ConvertFrom-Json -InputObject (($rawLines -join "`n").Trim())
                        if ($parsedArray -is [System.Array]) { $containers = @($parsedArray) }
                        elseif ($parsedArray) { $containers = @($parsedArray) }
                    } catch {}
                    break
                }
            }
        } finally { Pop-Location }
    }

    $volumeExists = $false
    $networkExists = $false
    if ($dockerAvailable) {
        try { $volumes = @(& docker volume ls --filter "label=com.docker.compose.project=$ProjectName" --format '{{.Name}}' 2>$null); $volumeExists = (($volumes -join "`n") -match "dbdata") } catch {}
        try { $networks = @(& docker network ls --filter "label=com.docker.compose.project=$ProjectName" --format '{{.Name}}' 2>$null); $networkExists = (($networks -join "`n") -match "appnet") } catch {}
    }

    $appHealth = @{ status = "offline"; database = "unavailable"; students = $null; message = "Aplikasi belum merespons di port 5000." }
    $health = Get-HttpHealth "/health" 2
    if ($health.ok -and $health.data) { $appHealth = $health.data }
    elseif ($health.error) { $appHealth.message = $health.error }

    $testSummary = @{ total = 0; passed = 0; failed = 0; skipped = 0; lastRunAt = $null }
    if ($script:LastReport) { $testSummary = $script:LastReport.summary }

    return @{
        dockerAvailable = $dockerAvailable
        dockerVersion = $dockerVersion
        containers = @($containers)
        volumeExists = [bool]$volumeExists
        networkExists = [bool]$networkExists
        appHealth = $appHealth
        logs = @($script:RecentLog.ToArray())
        projectRoot = $ProjectRoot
        controller = "active"
        testSummary = $testSummary
        testRunning = [bool]$script:TestRunning
        lastRunAt = $(if ($script:LastReport) { $script:LastReport.generatedAt } else { $null })
    }
}

function New-TestResult($Definition, [string]$Status, [datetime]$Started, [datetime]$Finished, [string[]]$Steps, [string]$Actual, [string[]]$Evidence, [string[]]$Logs, [string]$ErrorMessage = "") {
    return [ordered]@{
        id = $Definition.id
        title = $Definition.title
        category = $Definition.category
        status = $Status
        destructive = [bool]$Definition.destructive
        expected = $Definition.expected
        description = $Definition.description
        startedAt = $Started.ToString("yyyy-MM-dd HH:mm:ss")
        finishedAt = $Finished.ToString("yyyy-MM-dd HH:mm:ss")
        durationMs = [int][Math]::Max(0, ($Finished - $Started).TotalMilliseconds)
        steps = @($Steps)
        actual = $Actual
        evidence = @($Evidence)
        logs = @($Logs)
        error = $ErrorMessage
    }
}

function Add-SkippedTest($Definition, [string]$Reason) {
    $now = Get-Date
    $result = New-TestResult $Definition "SKIPPED" $now $now @("Tidak dijalankan oleh suite otomatis.") $Reason @($Reason) @() ""
    [void]$script:RunResults.Add($result)
}

function New-TestStudent([string]$Suffix) {
    $stamp = (Get-Date).ToString("yyyyMMddHHmmss") + (Get-Random -Minimum 100 -Maximum 999)
    $name = "Docker Lab Test $Suffix $stamp"
    $nim = "DLT$stamp"
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:5000/students" -Method Post -Body @{ name = $name; nim = $nim } -MaximumRedirection 5 -TimeoutSec 12 -UseBasicParsing
    $page = Invoke-WebRequest -Uri "http://127.0.0.1:5000/" -TimeoutSec 8 -UseBasicParsing
    if ($page.Content -notmatch [regex]::Escape($nim)) { throw "Data uji dengan NIM $nim tidak ditemukan setelah dikirim ke formulir." }
    $rowPattern = '(?is)<tr\b[^>]*>(?:(?!</tr>).)*?' + [regex]::Escape($nim) + '(?:(?!</tr>).)*?</tr>'
    $studentId = $null
    if ($page.Content -match $rowPattern) {
        $row = $Matches[0]
        if ($row -match 'action="/students/(\d+)/delete"') { $studentId = [int]$Matches[1] }
    }
    return @{ name = $name; nim = $nim; id = $studentId; page = $page.Content }
}

function Remove-TestStudent($Student) {
    if (-not $Student -or -not $Student.id) { return @{ ok = $false; message = "ID data uji tidak berhasil dibaca dari halaman; bersihkan data uji secara manual bila masih terlihat." } }
    try {
        Invoke-WebRequest -Uri ("http://127.0.0.1:5000/students/{0}/delete" -f $Student.id) -Method Post -MaximumRedirection 5 -TimeoutSec 8 -UseBasicParsing | Out-Null
        $page = Invoke-WebRequest -Uri "http://127.0.0.1:5000/" -TimeoutSec 8 -UseBasicParsing
        if ($page.Content -match [regex]::Escape([string]$Student.nim)) { return @{ ok = $false; message = "Permintaan hapus selesai tetapi NIM masih ditemukan." } }
        return @{ ok = $true; message = "Data uji $($Student.nim) berhasil dihapus." }
    } catch { return @{ ok = $false; message = $_.Exception.Message } }
}

function Invoke-OneTest([string]$TestId) {
    $definition = $script:TestCatalog | Where-Object { $_.id -eq $TestId } | Select-Object -First 1
    if (-not $definition) { throw "ID tes tidak dikenal: $TestId" }
    $started = Get-Date
    $steps = New-Object System.Collections.ArrayList
    $evidence = New-Object System.Collections.ArrayList
    $logs = New-Object System.Collections.ArrayList
    $status = "FAIL"
    $actual = "Tes belum selesai."
    $errorMessage = ""
    $student = $null
    $dbWasStopped = $false
    $stackWasDown = $false
    $volumeResetCompleted = $false
    try {
        switch ($TestId) {
            "T01" {
                [void]$steps.Add("Periksa Docker Engine.")
                $engine = Invoke-Docker @("info", "--format", "{{.ServerVersion}}")
                [void]$evidence.Add("docker info --format '{{.ServerVersion}}' => $($engine.output) (exit $($engine.exitCode))")
                [void]$logs.Add($engine.output)
                if ($engine.exitCode -ne 0) { throw "Docker Engine belum siap. Buka Docker Desktop dan coba lagi." }
                [void]$steps.Add("Periksa file .env dan konfigurasi Compose.")
                if (-not (Test-Path (Join-Path $ProjectRoot ".env"))) { throw "File .env belum ada. Jalankan jalankan-sistem.bat untuk membuat konfigurasi." }
                $config = Invoke-Compose @("config", "--quiet")
                [void]$evidence.Add("docker compose config --quiet => exit $($config.exitCode)")
                [void]$logs.Add($config.output)
                if ($config.exitCode -ne 0) { throw "Konfigurasi Compose tidak valid: $($config.output)" }
                $status = "PASS"
                $actual = "Docker Engine $($engine.output) merespons, .env tersedia, dan konfigurasi Compose valid."
            }
            "T02" {
                [void]$steps.Add("Build image dan jalankan service.")
                $up = Invoke-Compose @("up", "-d", "--build")
                [void]$evidence.Add("docker compose up -d --build => exit $($up.exitCode)")
                [void]$logs.Add($up.output)
                if ($up.exitCode -ne 0) { throw "Compose gagal menjalankan service: $($up.output)" }
                [void]$steps.Add("Tunggu endpoint health hingga Flask terhubung ke MySQL.")
                $ready = Wait-AppReady 150
                [void]$evidence.Add("Health result: $(ConvertTo-Json -InputObject $ready.health -Compress)")
                if (-not $ready.ok) { throw "Service belum sehat: $($ready.message)" }
                $ps = Invoke-Compose @("ps", "--all")
                [void]$logs.Add($ps.output)
                [void]$evidence.Add("docker compose ps --all => $($ps.output)")
                $status = "PASS"
                $actual = "Image berhasil dibangun; endpoint /health menunjukkan status ok dan database connected."
            }
            "T03" {
                [void]$steps.Add("Pastikan endpoint health menunjukkan database connected.")
                $health = Get-HttpHealth "/health" 5
                if (-not $health.ok -or $health.data.status -ne "ok") { throw "Aplikasi belum siap untuk CRUD. Jalankan T02 terlebih dahulu. $($health.error)" }
                [void]$steps.Add("Tambah data unik melalui endpoint formulir mahasiswa.")
                $student = New-TestStudent "CRUD"
                [void]$evidence.Add("POST /students diikuti redirect; NIM $($student.nim) muncul pada GET /.")
                [void]$steps.Add("Hapus data uji dan pastikan tidak lagi muncul.")
                $cleanup = Remove-TestStudent $student
                [void]$evidence.Add($cleanup.message)
                if (-not $cleanup.ok) { throw "CRUD create/read berhasil tetapi cleanup gagal: $($cleanup.message)" }
                $student = $null
                $status = "PASS"
                $actual = "Create, read, dan delete melalui aplikasi web berhasil; data uji telah dibersihkan."
            }
            "T04" {
                [void]$steps.Add("Pastikan aplikasi sehat sebelum menguji volume.")
                $health = Get-HttpHealth "/health" 5
                if (-not $health.ok -or $health.data.status -ne "ok") { throw "Stack belum sehat. Jalankan T02 terlebih dahulu." }
                [void]$steps.Add("Buat marker uji melalui aplikasi Flask.")
                $student = New-TestStudent "PERSIST"
                [void]$evidence.Add("Marker dibuat: $($student.nim)")
                [void]$steps.Add("Jalankan docker compose down tanpa -v.")
                $stackWasDown = $true
                $down = Invoke-Compose @("down")
                [void]$logs.Add($down.output)
                [void]$evidence.Add("docker compose down => exit $($down.exitCode)")
                if ($down.exitCode -ne 0) { throw "Compose down gagal: $($down.output)" }
                [void]$steps.Add("Jalankan kembali stack dan tunggu database siap.")
                $up = Invoke-Compose @("up", "-d")
                [void]$logs.Add($up.output)
                [void]$evidence.Add("docker compose up -d => exit $($up.exitCode)")
                if ($up.exitCode -ne 0) { throw "Compose up gagal: $($up.output)" }
                $ready = Wait-AppReady 120
                if (-not $ready.ok) { throw "Stack belum pulih setelah up: $($ready.message)" }
                $stackWasDown = $false
                [void]$steps.Add("Baca kembali marker setelah container dibuat ulang.")
                $page = Invoke-WebRequest -Uri "http://127.0.0.1:5000/" -TimeoutSec 8 -UseBasicParsing
                if ($page.Content -notmatch [regex]::Escape([string]$student.nim)) { throw "Marker $($student.nim) hilang setelah down lalu up." }
                [void]$evidence.Add("GET / setelah up memuat marker $($student.nim). Health: $(ConvertTo-Json -InputObject $ready.health -Compress)")
                $cleanup = Remove-TestStudent $student
                [void]$evidence.Add($cleanup.message)
                if (-not $cleanup.ok) { throw "Persistensi terbukti tetapi cleanup gagal: $($cleanup.message)" }
                $student = $null
                $status = "PASS"
                $actual = "Marker tetap ada setelah down lalu up tanpa -v; data uji dibersihkan setelah verifikasi."
            }
            "T05" {
                [void]$steps.Add("Pastikan stack awal sehat.")
                $health = Get-HttpHealth "/health" 5
                if (-not $health.ok -or $health.data.status -ne "ok") { throw "Stack belum sehat. Jalankan T02 terlebih dahulu." }
                [void]$steps.Add("Hentikan service db saja.")
                $dbWasStopped = $true
                $stop = Invoke-Compose @("stop", "db")
                [void]$logs.Add($stop.output)
                [void]$evidence.Add("docker compose stop db => exit $($stop.exitCode)")
                if ($stop.exitCode -ne 0) { throw "Gagal menghentikan database." }
                Start-Sleep -Seconds 2
                [void]$steps.Add("Pastikan Flask masih hidup dan health menunjukkan degraded/unavailable.")
                $live = Get-HttpHealth "/live" 5
                $degraded = Get-HttpHealth "/health" 5
                [void]$evidence.Add("GET /live => ok=$($live.ok), HTTP=$($live.statusCode)")
                [void]$evidence.Add("GET /health saat DB stop => $(if ($degraded.data) { ConvertTo-Json -InputObject $degraded.data -Compress } else { $degraded.error })")
                if (-not $live.ok) { throw "Flask tidak merespons pada /live ketika MySQL berhenti." }
                if (-not $degraded.ok -or $degraded.data.status -ne "degraded") { throw "Health tidak menunjukkan degraded saat MySQL dihentikan." }
                [void]$steps.Add("Mulai database lagi dan tunggu pulih.")
                $start = Invoke-Compose @("start", "db")
                [void]$logs.Add($start.output)
                [void]$evidence.Add("docker compose start db => exit $($start.exitCode)")
                if ($start.exitCode -ne 0) { throw "Gagal memulai database kembali." }
                $ready = Wait-AppReady 100
                if (-not $ready.ok) { throw "Database belum pulih: $($ready.message)" }
                $dbWasStopped = $false
                [void]$evidence.Add("Health setelah pemulihan => $(ConvertTo-Json -InputObject $ready.health -Compress)")
                $status = "PASS"
                $actual = "Flask tetap hidup saat MySQL stop, melaporkan degraded, lalu kembali connected setelah MySQL start."
            }
            "T06" {
                [void]$steps.Add("Ambil health awal dan pastikan database sedang sehat.")
                $health = Get-HttpHealth "/health" 5
                if (-not $health.ok -or $health.data.status -ne "ok") { throw "Stack belum sehat. Jalankan T02 terlebih dahulu." }
                [void]$steps.Add("Buat marker untuk membuktikan efek penghapusan volume.")
                $student = New-TestStudent "RESET"
                [void]$evidence.Add("Marker sebelum reset: $($student.nim)")
                [void]$steps.Add("Jalankan docker compose down -v. Tindakan ini menghapus semua data di volume proyek.")
                $stackWasDown = $true
                $down = Invoke-Compose @("down", "-v")
                [void]$logs.Add($down.output)
                [void]$evidence.Add("docker compose down -v => exit $($down.exitCode)")
                if ($down.exitCode -ne 0) { throw "Perintah down -v gagal: $($down.output)" }
                $volumeResetCompleted = $true
                [void]$steps.Add("Buat ulang stack dan tunggu MySQL menginisialisasi database kosong.")
                $up = Invoke-Compose @("up", "-d", "--build")
                [void]$logs.Add($up.output)
                if ($up.exitCode -ne 0) { throw "Stack gagal dibuat ulang: $($up.output)" }
                $ready = Wait-AppReady 150
                if (-not $ready.ok) { throw "Stack belum sehat setelah reset: $($ready.message)" }
                $stackWasDown = $false
                $page = Invoke-WebRequest -Uri "http://127.0.0.1:5000/" -TimeoutSec 8 -UseBasicParsing
                if ($page.Content -match [regex]::Escape([string]$student.nim)) { throw "Marker lama masih ditemukan setelah down -v." }
                if ([int]$ready.health.students -ne 0) { throw "Database baru tidak kosong; jumlah data=$($ready.health.students). Pastikan volume benar-benar direset." }
                [void]$evidence.Add("Health setelah reset => $(ConvertTo-Json -InputObject $ready.health -Compress); marker lama tidak ditemukan.")
                $status = "PASS"
                $actual = "Volume dihapus dan database baru kosong. Semua data lama dalam volume proyek telah dihapus sesuai tujuan tes."
            }
            "T07" {
                [void]$steps.Add("Pastikan web dan database siap.")
                $health = Get-HttpHealth "/health" 5
                if (-not $health.ok -or $health.data.status -ne "ok") { throw "Stack belum sehat. Jalankan T02 terlebih dahulu." }
                [void]$steps.Add("Resolve nama service db dari container web.")
                $dns = Invoke-Compose @("exec", "-T", "web", "python", "-c", "import socket; print('db=' + socket.gethostbyname('db'))")
                [void]$logs.Add($dns.output)
                [void]$evidence.Add("DNS lookup dari container web => $($dns.output) (exit $($dns.exitCode))")
                if ($dns.exitCode -ne 0) { throw "Hostname service db tidak dapat di-resolve." }
                [void]$steps.Add("Uji koneksi MySQL dari environment Flask.")
                $code = "import os,mysql.connector; c=mysql.connector.connect(host=os.getenv('DB_HOST','db'),port=int(os.getenv('DB_PORT','3306')),user=os.getenv('DB_USER'),password=os.getenv('DB_PASSWORD'),database=os.getenv('DB_NAME'),connection_timeout=4); c.close(); print('MYSQL_CONNECT_OK')"
                $conn = Invoke-Compose @("exec", "-T", "web", "python", "-c", $code)
                [void]$logs.Add($conn.output)
                [void]$evidence.Add("MySQL connector test => $($conn.output) (exit $($conn.exitCode))")
                if ($conn.exitCode -ne 0 -or $conn.output -notmatch "MYSQL_CONNECT_OK") { throw "Koneksi MySQL dari container web gagal." }
                $status = "PASS"
                $actual = "DNS service db dan koneksi MySQL internal berhasil tanpa mengandalkan IP container tetap."
            }
            "T08" {
                [void]$steps.Add("Ambil status container Compose.")
                $ps = Invoke-Compose @("ps", "--all")
                [void]$logs.Add($ps.output)
                [void]$evidence.Add("docker compose ps --all => exit $($ps.exitCode); $($ps.output)")
                [void]$steps.Add("Ambil log terbaru dari service.")
                $logResult = Invoke-Compose @("logs", "--tail", "80", "--no-color")
                [void]$logs.Add($logResult.output)
                [void]$evidence.Add("docker compose logs --tail 80 --no-color => exit $($logResult.exitCode); log dicatat.")
                [void]$steps.Add("Periksa volume dan network yang dikelola proyek.")
                $vol = Invoke-Docker @("volume", "ls", "--filter", "label=com.docker.compose.project=$ProjectName")
                $net = Invoke-Docker @("network", "ls", "--filter", "label=com.docker.compose.project=$ProjectName")
                [void]$evidence.Add("docker volume ls => $($vol.output)")
                [void]$evidence.Add("docker network ls => $($net.output)")
                if ($ps.exitCode -ne 0 -or $logResult.exitCode -ne 0 -or $vol.exitCode -ne 0 -or $net.exitCode -ne 0) { throw "Satu atau lebih perintah diagnostik gagal." }
                $status = "PASS"
                $actual = "Snapshot status, log, volume, dan network berhasil dikumpulkan sebagai bukti diagnostik."
            }
            "T10" {
                [void]$steps.Add("Pastikan aplikasi dan database sehat.")
                $health = Get-HttpHealth "/health" 5
                if (-not $health.ok -or $health.data.status -ne "ok") { throw "Stack belum sehat. Jalankan T02 terlebih dahulu." }
                [void]$steps.Add("Buat satu data uji dengan NIM unik.")
                $student = New-TestStudent "VALIDATE"
                [void]$evidence.Add("Record awal dibuat: NIM $($student.nim).")
                [void]$steps.Add("Kirim NIM yang sama untuk memastikan constraint UNIQUE ditangani sebagai pesan validasi.")
                $duplicate = Invoke-WebRequest -Uri "http://127.0.0.1:5000/students" -Method Post -Body @{ name = "Docker Lab Duplicate Test"; nim = $student.nim } -MaximumRedirection 5 -TimeoutSec 12 -UseBasicParsing
                if ($duplicate.Content -notmatch 'NIM tersebut sudah terdaftar') { throw "Pesan validasi NIM duplikat tidak ditemukan." }
                $occurrences = [regex]::Matches($duplicate.Content, [regex]::Escape([string]$student.nim)).Count
                if ($occurrences -ne 1) { throw "Ditemukan $occurrences kemunculan NIM; seharusnya hanya satu record yang tampil." }
                [void]$evidence.Add("POST NIM duplikat => pesan penolakan tampil; NIM muncul $occurrences kali pada daftar.")
                [void]$steps.Add("Kirim nama dan NIM kosong untuk memastikan validasi server-side bekerja.")
                $empty = Invoke-WebRequest -Uri "http://127.0.0.1:5000/students" -Method Post -Body @{ name = ""; nim = "" } -MaximumRedirection 5 -TimeoutSec 12 -UseBasicParsing
                if ($empty.Content -notmatch 'Nama dan NIM wajib diisi') { throw "Pesan validasi input kosong tidak ditemukan." }
                [void]$evidence.Add("POST input kosong => pesan 'Nama dan NIM wajib diisi' tampil.")
                [void]$steps.Add("Hapus record uji dan pastikan tidak tersisa.")
                $cleanup = Remove-TestStudent $student
                [void]$evidence.Add($cleanup.message)
                if (-not $cleanup.ok) { throw "Validasi berjalan tetapi cleanup gagal: $($cleanup.message)" }
                $student = $null
                $status = "PASS"
                $actual = "Input kosong dan NIM duplikat ditolak oleh server; hanya satu record uji tersimpan dan kemudian dibersihkan."
            }
            "T09" {
                [void]$steps.Add("Baca compose.yaml dan periksa binding port web.")
                $composeText = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot "compose.yaml"))
                if ($composeText -notmatch '127\.0\.0\.1:5000:5000') { throw "Port Flask tidak dibatasi ke 127.0.0.1:5000." }
                [void]$evidence.Add("Web port binding: 127.0.0.1:5000:5000 ditemukan.")
                [void]$steps.Add("Pastikan service db tidak memiliki port host dan menggunakan named volume.")
                $lines = @($composeText -split "`r?`n")
                $dbStart = -1
                $topVolumes = -1
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match '^  db:\s*$') { $dbStart = $i }
                    if ($dbStart -ge 0 -and $i -gt $dbStart -and $lines[$i] -match '^volumes:\s*$') { $topVolumes = $i; break }
                }
                if ($dbStart -lt 0) { throw "Service db tidak ditemukan di compose.yaml." }
                if ($topVolumes -lt 0) { $topVolumes = $lines.Count }
                $dbBlock = ($lines[$dbStart..($topVolumes - 1)] -join "`n")
                if ($dbBlock -match '(?m)^\s{4}ports:') { throw "Service db tampaknya mempublikasikan port ke host." }
                if ($composeText -notmatch 'dbdata:/var/lib/mysql') { throw "Named volume dbdata tidak dipasang ke /var/lib/mysql." }
                [void]$evidence.Add("Service db tidak memiliki deklarasi ports; dbdata:/var/lib/mysql ditemukan.")
                $status = "PASS"
                $actual = "Port web dibatasi ke loopback, MySQL tidak dipublikasikan ke host, dan penyimpanan menggunakan named volume."
            }
        }
    } catch {
        $status = "FAIL"
        $errorMessage = $_.Exception.Message
        $actual = "Tes gagal: $errorMessage"
        [void]$evidence.Add("ERROR: $errorMessage")
        Add-Log ("TEST $TestId FAIL: " + $errorMessage)
    } finally {
        if ($dbWasStopped) {
            [void]$steps.Add("Pemulihan pengaman: coba start db kembali.")
            $restore = Invoke-Compose @("start", "db")
            [void]$logs.Add($restore.output)
            [void]$evidence.Add("Pemulihan otomatis start db => exit $($restore.exitCode)")
            $restored = Wait-AppReady 100
            if (-not $restored.ok) {
                [void]$evidence.Add("PERINGATAN: pemulihan database belum terkonfirmasi: $($restored.message)")
                Add-Log ("WARNING pemulihan DB setelah $TestId belum terkonfirmasi: " + $restored.message)
            } else { $dbWasStopped = $false }
        }
        if ($stackWasDown) {
            [void]$steps.Add("Pemulihan pengaman: coba jalankan stack kembali.")
            $restore = Invoke-Compose @("up", "-d")
            [void]$logs.Add($restore.output)
            [void]$evidence.Add("Pemulihan otomatis up => exit $($restore.exitCode)")
            $restored = Wait-AppReady 120
            if (-not $restored.ok) {
                [void]$evidence.Add("PERINGATAN: stack belum sehat setelah pemulihan: $($restored.message)")
                Add-Log ("WARNING pemulihan stack setelah $TestId belum terkonfirmasi: " + $restored.message)
            } else {
                $stackWasDown = $false
            }
        }
        # Retry cleanup once if a prior step failed. T06 has no marker to remove after a successful volume reset.
        if ($student -and -not $volumeResetCompleted) {
            $cleanup = Remove-TestStudent $student
            [void]$evidence.Add("Cleanup pengaman: $($cleanup.message)")
            if ($cleanup.ok) { $student = $null }
            else {
                [void]$evidence.Add("PERINGATAN: data uji mungkin masih tersisa; periksa NIM $($student.nim) secara manual.")
                Add-Log ("WARNING cleanup data uji $($student.nim) setelah $TestId gagal: " + $cleanup.message)
            }
        }
    }
    $finished = Get-Date
    $result = New-TestResult $definition $status $started $finished @($steps.ToArray()) $actual @($evidence.ToArray()) @($logs.ToArray()) $errorMessage
    [void]$script:RunResults.Add($result)
    Add-Log ("TEST $TestId $status - $($definition.title) - $([int]($finished - $started).TotalSeconds)s")
    return $result
}

function Save-TestReport([string]$Mode) {
    $now = Get-Date
    $allResults = @($script:RunResults.ToArray())
    $summary = @{
        total = $allResults.Count
        passed = @($allResults | Where-Object { $_.status -eq "PASS" }).Count
        failed = @($allResults | Where-Object { $_.status -eq "FAIL" }).Count
        skipped = @($allResults | Where-Object { $_.status -eq "SKIPPED" }).Count
        lastRunAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
    }
    $report = [ordered]@{
        product = "Docker Lab Studio"
        project = $ProjectName
        runId = $now.ToString("yyyyMMdd-HHmmss")
        mode = $Mode
        generatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
        projectRoot = $ProjectRoot
        summary = $summary
        results = $allResults
        note = "Hasil ini berasal dari pemeriksaan yang dijalankan oleh controller lokal. Simpan juga screenshot browser/terminal jika tugas meminta bukti visual."
    }
    $script:LastReport = $report
    $script:LastTestResults = $allResults
    try {
        if (-not (Test-Path $script:ReportsDirectory)) { New-Item -ItemType Directory -Path $script:ReportsDirectory -Force | Out-Null }
        $path = Join-Path $script:ReportsDirectory ("test-report-{0}.json" -f $report.runId)
        $report["reportFile"] = ("reports\" + (Split-Path -Leaf $path))
        $json = ConvertTo-Json -InputObject $report -Depth 14
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
        $script:LastReport = $report
        Add-Log ("Laporan tes disimpan: reports\$(Split-Path -Leaf $path)")
    } catch {
        if ($report.Contains("reportFile")) { $report.Remove("reportFile") }
        $report["reportWarning"] = "Laporan tersedia pada dashboard, tetapi file JSON gagal disimpan: $($_.Exception.Message)"
        $script:LastReport = $report
        Add-Log ("Gagal menyimpan file laporan: " + $_.Exception.Message)
    }
    return $report
}

function Invoke-TestRun([string]$TestId, [bool]$AllowDestructive) {
    if ($script:TestRunning) { return @{ ok = $false; message = "Pengujian lain sedang berjalan."; report = $script:LastReport } }
    $script:TestRunning = $true
    $script:RunResults = New-Object System.Collections.ArrayList
    try {
        if ($TestId -eq "ALL") {
            foreach ($definition in $script:TestCatalog) {
                if ($definition.destructive) {
                    Add-SkippedTest $definition "Dilewati dari Jalankan Semua Tes karena dapat menghapus seluruh data pada named volume. Jalankan T06 secara individual hanya jika memang ingin menguji reset dan sudah punya cadangan." 
                    continue
                }
                [void](Invoke-OneTest $definition.id)
            }
            $mode = "ALL_NON_DESTRUCTIVE"
        } else {
            $definition = $script:TestCatalog | Where-Object { $_.id -eq $TestId } | Select-Object -First 1
            if (-not $definition) { return @{ ok = $false; message = "ID tes tidak dikenal."; report = $null } }
            if ($definition.destructive -and -not $AllowDestructive) { return @{ ok = $false; message = "Tes ini destruktif dan memerlukan konfirmasi eksplisit."; report = $null } }
            [void](Invoke-OneTest $TestId)
            $mode = "SINGLE_$TestId"
        }
        $report = Save-TestReport $mode
        return @{ ok = $true; message = "Pengujian selesai."; report = $report }
    } finally { $script:TestRunning = $false }
}

function Get-ReportHtml($Report) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Laporan Pengujian Docker Lab Studio</title>')
    [void]$sb.AppendLine('<style>body{font:14px/1.55 Segoe UI,Arial,sans-serif;max-width:1100px;margin:32px auto;padding:0 20px;color:#172b4d}h1{margin-bottom:4px}p{color:#64748b}.summary{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0}.metric{border:1px solid #dfe7f1;border-radius:12px;padding:14px;min-width:120px}.metric b{display:block;font-size:24px}.test{border:1px solid #dfe7f1;border-radius:12px;padding:16px;margin:14px 0;break-inside:avoid}.pass{color:#14795f}.fail{color:#b73348}.skipped{color:#976008}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f8fc;border-radius:8px;padding:12px;font-size:12px}small{color:#64748b}</style></head><body>')
    [void]$sb.AppendLine('<h1>Docker Lab Studio — Laporan Pengujian</h1>')
    [void]$sb.AppendLine(("<p>Run ID: {0} · Mode: {1} · Dibuat: {2}</p>" -f [System.Net.WebUtility]::HtmlEncode([string]$Report.runId), [System.Net.WebUtility]::HtmlEncode([string]$Report.mode), [System.Net.WebUtility]::HtmlEncode([string]$Report.generatedAt)))
    [void]$sb.AppendLine(("<div class='summary'><div class='metric'>Total<b>{0}</b></div><div class='metric'>PASS<b class='pass'>{1}</b></div><div class='metric'>FAIL<b class='fail'>{2}</b></div><div class='metric'>Dilewati<b class='skipped'>{3}</b></div></div>" -f $Report.summary.total, $Report.summary.passed, $Report.summary.failed, $Report.summary.skipped))
    foreach ($r in $Report.results) {
        $safeStatus = [System.Net.WebUtility]::HtmlEncode([string]$r.status)
        $safeTitle = [System.Net.WebUtility]::HtmlEncode("$($r.id) — $($r.title)")
        $safeExpected = [System.Net.WebUtility]::HtmlEncode([string]$r.expected)
        $safeActual = [System.Net.WebUtility]::HtmlEncode([string]$r.actual)
        $details = @("Deskripsi: $($r.description)", "Langkah:", (($r.steps | ForEach-Object { "- $_" }) -join "`n"), "Bukti:", (($r.evidence | ForEach-Object { "- $_" }) -join "`n"), "Log:", (($r.logs | ForEach-Object { "- $_" }) -join "`n"), "Error: $($r.error)") -join "`n"
        $safeDetails = [System.Net.WebUtility]::HtmlEncode($details)
        [void]$sb.AppendLine(("<section class='test'><h2>{0} <small class='{1}'>[{1}]</small></h2><p><b>Ekspektasi:</b> {2}<br><b>Aktual:</b> {3}<br><b>Waktu:</b> {4} – {5} · <b>Durasi:</b> {6} ms</p><details><summary>Langkah, bukti, dan log</summary><pre>{7}</pre></details></section>" -f $safeTitle, $safeStatus.ToLowerInvariant(), $safeExpected, $safeActual, [System.Net.WebUtility]::HtmlEncode([string]$r.startedAt), [System.Net.WebUtility]::HtmlEncode([string]$r.finishedAt), $r.durationMs, $safeDetails))
    }
    [void]$sb.AppendLine('<p><small>Laporan ini merekam hasil aktual dari tes yang dijalankan. Sertakan screenshot browser/terminal terpisah bila diminta oleh instruksi tugas.</small></p></body></html>')
    return $sb.ToString()
}

Add-Log "Docker Lab Studio controller lokal dimulai."
Add-Log "Endpoint dibatasi ke 127.0.0.1:8765; perintah Docker memakai daftar aksi tetap."

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:8765/")
try {
    $listener.Start()
    Add-Log "Dashboard siap di http://127.0.0.1:8765/"
} catch {
    Write-Host "Tidak dapat membuka port 8765. Mungkin dashboard sudah berjalan." -ForegroundColor Yellow
    exit 1
}

while ($listener.IsListening) {
    $context = $null
    try {
        $context = $listener.GetContext()
        $path = $context.Request.Url.AbsolutePath
        $method = $context.Request.HttpMethod.ToUpperInvariant()

        if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
            $html = [System.IO.File]::ReadAllText($DashboardFile, [System.Text.Encoding]::UTF8)
            Send-Response $context 200 "text/html; charset=utf-8" $html
            continue
        }

        if ($method -eq "GET" -and $path -eq "/api/version") {
            Send-Json $context 200 @{ version = "2.0"; product = "Docker Lab Studio"; testApi = $true; reportExport = $true }
            continue
        }

        if ($method -eq "GET" -and $path -eq "/api/status") {
            Send-Json $context 200 (Get-DashboardStatus)
            continue
        }

        if ($method -eq "GET" -and $path -eq "/api/tests") {
            Send-Json $context 200 @{ catalog = @($script:TestCatalog); results = @($script:LastTestResults); report = $script:LastReport; running = [bool]$script:TestRunning }
            continue
        }

        if ($method -eq "GET" -and $path -eq "/api/report") {
            if (-not $script:LastReport) { Send-Json $context 404 @{ ok = $false; message = "Belum ada laporan. Jalankan pengujian terlebih dahulu." }; continue }
            $format = [string]$context.Request.QueryString["format"]
            $baseName = "docker-lab-report-$($script:LastReport.runId)"
            if ($format -eq "json") {
                $body = ConvertTo-Json -InputObject $script:LastReport -Depth 14
                Send-Response $context 200 "application/json; charset=utf-8" $body ($baseName + ".json")
            } elseif ($format -eq "csv") {
                $rows = @()
                foreach ($r in $script:LastReport.results) {
                    $rows += [pscustomobject]@{
                        RunId = $script:LastReport.runId; TestId = $r.id; Title = $r.title; Category = $r.category; Status = $r.status
                        StartedAt = $r.startedAt; FinishedAt = $r.finishedAt; DurationMs = $r.durationMs; Expected = $r.expected; Actual = $r.actual
                        Steps = ($r.steps -join " | "); Evidence = ($r.evidence -join " | "); Logs = ($r.logs -join " | "); Error = $r.error
                    }
                }
                $csvBody = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
                $csv = ([string][char]0xFEFF) + $csvBody
                Send-Response $context 200 "text/csv; charset=utf-8" $csv ($baseName + ".csv")
            } else {
                Send-Response $context 200 "text/html; charset=utf-8" (Get-ReportHtml $script:LastReport) ($baseName + ".html")
            }
            continue
        }

        if ($method -eq "POST" -and $path -eq "/api/action") {
            $reader = New-Object System.IO.StreamReader($context.Request.InputStream, $context.Request.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $requestData = $null
            try { $requestData = ConvertFrom-Json -InputObject $body } catch {}
            $action = ""
            if ($requestData -and $requestData.action) { $action = [string]$requestData.action }
            $allowed = @{
                "up" = @("up", "-d", "--build")
                "ps" = @("ps", "--all")
                "stop-db" = @("stop", "db")
                "start-db" = @("start", "db")
                "down" = @("down")
                "down-v" = @("down", "-v")
                "logs" = @("logs", "--tail", "80", "--no-color")
            }
            if (-not $allowed.ContainsKey($action)) { Send-Json $context 400 @{ ok = $false; output = "Aksi tidak diizinkan."; exitCode = 2 }; continue }
            if ($action -eq "down-v" -and -not ($requestData -and $requestData.confirmDestructive -eq $true)) {
                Send-Json $context 400 @{ ok = $false; output = "Konfirmasi tindakan destruktif belum diterima."; exitCode = 2 }
                continue
            }
            if ($action -eq "down-v") { Add-Log "PERINGATAN: pengguna mengonfirmasi down -v; volume proyek akan dihapus." }
            $result = Invoke-Compose -ComposeArgs $allowed[$action]
            Send-Json $context 200 @{ ok = ($result.exitCode -eq 0); action = $action; output = $result.output; exitCode = $result.exitCode; status = Get-DashboardStatus }
            continue
        }

        if ($method -eq "POST" -and $path -eq "/api/test/run") {
            $reader = New-Object System.IO.StreamReader($context.Request.InputStream, $context.Request.ContentEncoding)
            $body = $reader.ReadToEnd(); $reader.Close()
            $requestData = $null
            try { $requestData = ConvertFrom-Json -InputObject $body } catch {}
            $testId = if ($requestData -and $requestData.testId) { [string]$requestData.testId } else { "ALL" }
            $allowDestructive = [bool]($requestData -and $requestData.allowDestructive -eq $true)
            if ($testId -eq "T06" -and -not $allowDestructive) { Send-Json $context 400 @{ ok = $false; message = "T06 menghapus seluruh data dalam volume. Konfirmasi eksplisit diperlukan." }; continue }
            $result = Invoke-TestRun $testId $allowDestructive
            $code = if ($result.ok) { 200 } else { 400 }
            Send-Json $context $code $result
            continue
        }

        Send-Json $context 404 @{ ok = $false; message = "Endpoint tidak ditemukan." }
    } catch {
        Add-Log ("Request error: " + $_.Exception.Message)
        if ($context -and $context.Response -and $context.Response.OutputStream) { try { Send-Json $context 500 @{ ok = $false; message = "Kesalahan controller lokal."; detail = $_.Exception.Message } } catch {} }
    }
}
