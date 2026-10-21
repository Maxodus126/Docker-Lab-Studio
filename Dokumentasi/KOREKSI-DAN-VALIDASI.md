# Catatan Koreksi dan Validasi — Docker Lab Studio

Tanggal edisi: 21 Oktober 2026

## Koreksi yang diterapkan

1. **Pembersihan data uji** — T03/T04/T10 tidak lagi mencoba menghapus record yang sama setelah cleanup sukses. Jika tes gagal, controller mencoba cleanup ulang dan mencatat peringatan bila NIM mungkin masih tersisa.
2. **Pemulihan service** — T04 menandai stack sebagai perlu dipulihkan sebelum menjalankan `docker compose down`; T05 menandai DB sebagai perlu dipulihkan sebelum `docker compose stop db`. Blok `finally` mencoba menyalakan kembali service saat terjadi kegagalan.
3. **Status HTTP setelah redirect** — `Invoke-WebRequest` mengikuti redirect secara default. Laporan T03 tidak lagi menyebut status akhir GET sebagai status POST; bukti sekarang memverifikasi NIM pada halaman GET.
4. **Operasi destruktif** — `down -v` meminta konfirmasi pada UI dan membutuhkan flag konfirmasi pada API lokal. T06 tetap dikecualikan dari mode semua tes.
5. **Ekspor CSV** — BOM UTF-8 ditambahkan untuk meningkatkan kompatibilitas ketika dibuka di Excel.
6. **Kegagalan penyimpanan laporan** — Jika JSON tidak dapat ditulis, controller menghapus referensi file yang tidak tersedia dan dashboard menampilkan peringatan.
7. **Skrip Windows** — reset memeriksa Docker Engine dan membuat `.env` bila belum ada; skrip stop memeriksa Docker; reset hanya membuka dashboard jika controller aktif.
8. **Materi belajar** — Transkrip memisahkan reset volume manual dari T06 otomatis. Caption screenshot menyatakan bahwa screenshot merupakan simulasi untuk bahan belajar.

## Hasil pemeriksaan statis

- Total pemeriksaan: **70**
- PASS statis: **65**
- FAIL statis: **0**
- BLOCKED runtime: **5**

PASS berarti pemeriksaan statis yang disebutkan benar-benar dijalankan, seperti parsing Python, parsing YAML, pemeriksaan struktur sumber, validasi JavaScript, dan konsistensi data contoh. BLOCKED berarti runtime tidak tersedia di lingkungan penyusunan; status tersebut tidak boleh ditafsirkan sebagai PASS runtime.

## Yang masih perlu diverifikasi di laptop Windows

1. Jalankan `jalankan-sistem.bat` dengan Docker Desktop aktif.
2. Pastikan `http://127.0.0.1:8765/` dan `http://127.0.0.1:5000/` terbuka.
3. Jalankan `uji-semua-tes.bat` atau `.\uji-semua-tes.ps1` dari PowerShell.
4. Pastikan T01–T05 dan T07–T10 menghasilkan status aktual yang diharapkan; T06 seharusnya SKIPPED pada mode semua tes.
5. Jalankan T06 secara individual hanya setelah backup dan setelah bukti T04 disimpan. T06 menghapus seluruh data di named volume proyek.
6. Simpan laporan HTML/CSV/JSON dan ambil screenshot aktual dari laptop jika diminta sebagai bukti runtime.

## Batasan yang dinyatakan

Docker CLI/Engine, Windows PowerShell, serta dependensi Flask dan mysql-connector tidak tersedia di lingkungan penyusunan ini. Karena itu, build image, startup container, koneksi Flask–MySQL, dan skrip Windows belum dapat diklaim berhasil di runtime. Screenshot contoh yang dibundel adalah visual simulasi dan diberi caption di laporan.


## Pembersihan total resource Docker

Ditambahkan `HAPUS-SELURUH-DATA-DOCKER.bat` dengan pendamping `scripts/cleanup-project.ps1`.
Operasi dibatasi ke `compose.yaml` proyek `flask-mysql-docker-lab` dan meminta pengguna
mengetik `HAPUS` sebelum menjalankan penghapusan. Perintah inti:
`docker compose down --volumes --rmi local --remove-orphans`.

Pemeriksaan setelah perintah mengonfirmasi container Compose, named volume, dan network
dengan label proyek. Skrip tidak menjalankan perintah prune global, tidak menghapus `.env`,
source code, laporan, screenshot, Docker Desktop, image dasar `mysql:8.4`, atau resource
proyek lain. Penghapusan volume bersifat destruktif. Pemeriksaan ini merupakan review
statis; runtime Windows harus diverifikasi pada komputer dengan Docker Desktop dan PowerShell.


## Audit statis tambahan pembersihan

Pemeriksaan tambahan pada BAT dan PowerShell cleanup: **18 PASS, 0 FAIL**.
Pemeriksaan mencakup konfirmasi eksplisit, validasi nama proyek, cakupan Compose,
volume/network/container, pembatasan proses controller, dan tidak adanya perintah prune
global. Ini pemeriksaan statis; Docker runtime dan Windows PowerShell belum dijalankan
di lingkungan penyusunan. Rincian ada di `Audit-Pembersihan-Docker.json` dan `.csv`.


## Windows 11 — ProjectRoot path quoting

Corrected the CMD-to-PowerShell argument by passing `-ProjectRoot "%~dp0."` instead of `-ProjectRoot "%~dp0"`. `%~dp0` ends with a backslash, and a backslash directly before a closing quote can make the quote literal under Windows command-line parsing rules. The three PowerShell entry scripts now trim accidental outer quotes, canonicalize the project path in a guarded block, and report the received value on failure. `.env` is not overwritten if it already exists. Static review only; Windows Docker runtime was not executed here.
