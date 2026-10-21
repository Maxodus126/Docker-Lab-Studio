[CmdletBinding()]
param(
    [ValidateSet('ALL','T01','T02','T03','T04','T05','T06','T07','T08','T09','T10')]
    [string]$TestId = 'ALL',
    [switch]$AllowDestructive
)

$ErrorActionPreference = 'Stop'
$controllerUrl = 'http://127.0.0.1:8765'

try {
    $version = Invoke-RestMethod -Uri "$controllerUrl/api/version" -TimeoutSec 5
    if ($version.version -ne '2.0') {
        throw 'Controller Docker Lab Studio versi 2.0 tidak ditemukan. Jalankan jalankan-sistem.bat terlebih dahulu.'
    }

    if ($TestId -eq 'T06') {
        if (-not $AllowDestructive) {
            throw 'T06 menghapus named volume. Jika sudah mencadangkan data, jalankan kembali dengan -AllowDestructive.'
        }
        Write-Host 'PERINGATAN: T06 akan menghapus semua data dalam named volume proyek.' -ForegroundColor Yellow
        $confirmation = Read-Host 'Ketik RESET untuk melanjutkan'
        if ($confirmation -cne 'RESET') {
            Write-Host 'Tes T06 dibatalkan; data tidak diubah oleh skrip ini.' -ForegroundColor Yellow
            exit 1
        }
    }

    $payload = @{
        testId = $TestId
        allowDestructive = [bool]$AllowDestructive
    } | ConvertTo-Json -Compress

    Write-Host ''
    Write-Host "Docker Lab Studio - Test Center ($TestId)" -ForegroundColor Cyan
    Write-Host 'Mengirim permintaan ke controller lokal. Jangan tutup dashboard selama tes berjalan.'
    $run = Invoke-RestMethod -Uri "$controllerUrl/api/test/run" -Method Post `
        -ContentType 'application/json' -Body $payload -TimeoutSec 900

    if (-not $run.report) {
        throw $(if ($run.message) { $run.message } else { 'Controller tidak mengembalikan laporan.' })
    }

    $report = $run.report
    $summary = $report.summary
    Write-Host ''
    Write-Host "Run ID   : $($report.runId)"
    Write-Host "Mode     : $($report.mode)"
    Write-Host "Total    : $($summary.total)"
    Write-Host "PASS     : $($summary.passed)" -ForegroundColor Green
    Write-Host "FAIL     : $($summary.failed)" -ForegroundColor $(if ([int]$summary.failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host "SKIPPED  : $($summary.skipped)" -ForegroundColor Yellow
    Write-Host ''
    $report.results | Select-Object id, status, title, durationMs, actual | Format-Table -Wrap -AutoSize
    if ($report.reportFile) { Write-Host "Laporan JSON: $($report.reportFile)" -ForegroundColor Cyan }
    Write-Host 'Ekspor HTML/CSV/JSON juga tersedia di dashboard > Reports & evidence.'

    if ([int]$summary.failed -gt 0) {
        Write-Host 'Satu atau lebih tes gagal. Buka detail hasil di dashboard dan periksa log.' -ForegroundColor Red
        exit 2
    }
    Write-Host 'Run selesai tanpa tes FAIL. Periksa juga status SKIPPED dan catatan tiap tes.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
