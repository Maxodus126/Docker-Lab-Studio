# Docker Lab Studio — Flask + MySQL + Docker Compose

Dashboard praktikum Docker Compose untuk Windows dengan antarmuka cerah, peta arsitektur runtime, kontrol Docker lokal, Test Center, serta ekspor laporan pengujian.

## Yang ada di dalam paket

- **Flask web app** dengan CRUD daftar mahasiswa.
- **MySQL 8.4** sebagai service database terpisah.
- **Named volume `dbdata`** untuk menunjukkan persistensi data.
- **Docker network `appnet`** untuk komunikasi internal service menggunakan nama `db`.
- **Dashboard kontrol lokal** yang mengambil status Docker aktual dan menjalankan perintah Compose dari daftar aksi yang diizinkan.
- **Test Center**: tes individual dan `Jalankan Semua Tes` untuk semua tes non-destruktif.
- **Laporan lengkap** berisi status PASS/FAIL/SKIPPED, langkah, hasil yang diharapkan, hasil aktual, waktu mulai/selesai, durasi, bukti command/health/log, dan pesan error.
- Ekspor laporan **HTML, CSV, dan JSON**. File JSON hasil run juga disimpan di folder `reports`.
- Skrip Windows `jalankan-sistem.bat`, `hentikan-sistem.bat`, `reset-database.bat`, `uji-semua-tes.bat`, dan `uji-semua-tes.ps1` untuk menjalankan proyek dan pengujian.

## Persyaratan

1. Windows 10/11 yang didukung Docker Desktop.
2. Docker Desktop terpasang dan Docker Engine dapat berjalan (umumnya backend WSL 2).
3. Virtualisasi dan komponen Windows yang diperlukan Docker Desktop aktif.
4. Koneksi internet pada build pertama jika image MySQL/Python atau dependensi belum tersedia.

MySQL tidak perlu diinstal manual. Saat startup, skrip membuat `.env` lokal dengan password acak jika file itu belum ada. Jangan mengunggah `.env` ke repository publik atau membagikan password database.

## Menjalankan aplikasi

1. Ekstrak ZIP ke folder yang mudah diakses, misalnya `C:\DockerLabStudio`.
2. Klik dua kali `jalankan-sistem.bat`.
3. Skrip memeriksa Docker CLI, mencoba membuka Docker Desktop jika Engine belum aktif, membuat `.env`, menyalakan controller lokal, menjalankan Compose, menunggu health Flask/MySQL, lalu membuka dashboard.
4. Dashboard kontrol: `http://127.0.0.1:8765/`.
5. Aplikasi mahasiswa: `http://127.0.0.1:5000/`.

Build pertama bisa membutuhkan beberapa menit. Jangan tutup Docker Desktop saat praktikum berlangsung.

## Menu dashboard

- **Ringkasan**: status Flask, MySQL, named volume, network, health database, jumlah mahasiswa, dan hasil tes terakhir.
- **Arsitektur**: Browser → Flask → MySQL, koneksi network internal, dan volume `dbdata`.
- **Test Center**: sepuluh skenario tes dengan tombol individual serta satu tombol untuk menjalankan seluruh tes non-destruktif.
- **Execution results**: status setiap tes, waktu, durasi, hasil aktual, dan detail langkah/bukti/log.
- **Command Center**: `up -d --build`, `ps`, `stop db`, `start db`, `down`, `down -v`, dan `logs`.
- **Aplikasi mahasiswa**: preview CRUD Flask aktual.
- **Reports & evidence**: unduh laporan HTML/CSV/JSON dan lihat jejak aktivitas controller.

## Matriks pengujian

| ID | Pengujian | Pemeriksaan utama | Otomatis saat Jalankan Semua Tes? |
|---|---|---|---|
| T01 | Prasyarat & konfigurasi | Docker Engine, `.env`, validitas Compose | Ya |
| T02 | Build & startup | Build, container, endpoint health | Ya |
| T03 | CRUD mahasiswa | Tambah, baca, hapus data uji | Ya |
| T04 | Persistensi volume | Buat marker, `down`, `up`, cek marker masih ada | Ya |
| T05 | Pemulihan MySQL | Stop DB, liveness/degraded health, start dan pulih | Ya |
| T06 | Reset volume | `down -v`, start ulang, verifikasi database baru kosong | **Tidak — destruktif** |
| T07 | Network internal | DNS `db` dan koneksi MySQL dari container web | Ya |
| T08 | Snapshot diagnostik | Status, log, daftar volume dan network | Ya |
| T09 | Port & storage | Web hanya loopback, DB tanpa port host, named volume | Ya |
| T10 | Validasi input | Input kosong dan NIM duplikat ditolak; record uji dibersihkan | Ya |

### Tentang hasil pengujian

- `PASS` berarti pemeriksaan aktual yang ditentukan oleh tes lulus.
- `FAIL` berarti setidaknya satu pemeriksaan gagal; buka detail untuk membaca hasil aktual dan log.
- `SKIPPED` berarti tes tidak dijalankan. Pada mode semua tes, T06 sengaja dilewati karena berpotensi menghapus data.
- Tes integrasi menjalankan perintah Docker dan HTTP sungguhan. Tes membutuhkan Docker Engine aktif, port `5000` dan `8765` tersedia, dan `.env` valid.
- Tes CRUD dan persistensi membuat data sementara berawalan `Docker Lab Test` dengan NIM `DLT...`, lalu mencoba menghapusnya setelah verifikasi.
- T04 akan menjalankan `docker compose down` lalu `up -d`, sehingga aplikasi bisa tidak tersedia sementara.
- T05 menghentikan MySQL sementara dan mencoba memulihkannya otomatis. Hindari menjalankan tes saat ada aktivitas database penting.

## PERINGATAN: T06 dan `down -v`

`docker compose down -v` menghapus named volume database proyek. Data mahasiswa yang tersimpan di volume tersebut dapat hilang permanen. T06 hanya tersedia sebagai tes individual setelah dialog konfirmasi. **Jangan jalankan T06 sebelum bukti persistensi T04 sudah didapat dan data penting sudah dicadangkan.** `Jalankan Semua Tes` tidak menjalankan T06.

`reset-database.bat` juga merupakan tindakan destruktif. Baca konfirmasi sebelum melanjutkan.

## Laporan dan bukti

Setiap run yang selesai akan menyimpan JSON di `reports\test-report-<runId>.json`. Dari dashboard, kamu juga dapat mengunduh:

- **HTML** — cocok dibuka di browser atau dicetak menjadi PDF.
- **CSV** — cocok dibuka di Excel untuk rekap PASS/FAIL dan durasi.
- **JSON** — struktur lengkap untuk arsip atau pemrosesan lanjutan.

Bukti otomatis meliputi output perintah Docker, response endpoint health, hasil pengecekan data, dan potongan log. Jika instruksi dosen meminta **screenshot visual**, ambil screenshot aktual dari dashboard, terminal, dan aplikasi mahasiswa menggunakan Snipping Tool/`Win + Shift + S`, lalu lampirkan bersama laporan. Screenshot contoh yang disertakan dalam folder `Bukti` adalah visual simulasi untuk bahan belajar, bukan bukti runtime aktual. Caption pada laporan menandai gambar tersebut sebagai simulasi. Dashboard live sendiri menampilkan data yang diterima dari controller dan service lokal.

## Menjalankan tes dari terminal

Setelah `jalankan-sistem.bat` berhasil membuka dashboard, buka PowerShell di folder proyek lalu jalankan:

```powershell
.\uji-semua-tes.ps1
```

Perintah di atas menjalankan seluruh tes non-destruktif (T06 dilewati). Untuk satu tes saja, misalnya T03:

```powershell
.\uji-semua-tes.ps1 -TestId T03
```

T06 menghapus volume dan hanya dapat dijalankan dengan konfirmasi tambahan setelah backup:

```powershell
.\uji-semua-tes.ps1 -TestId T06 -AllowDestructive
```

Jangan jalankan T06 sebelum bukti persistensi T04 disimpan dan data penting dicadangkan.

## Perintah manual

Jalankan dari folder yang berisi `compose.yaml`:

```powershell
docker compose up -d --build
docker compose ps --all
docker compose logs --tail 80
docker compose stop db
docker compose start db
docker compose down
```

Gunakan `docker compose down -v` hanya jika memang ingin menghapus data volume.

## Menghentikan atau mereset

- `hentikan-sistem.bat`: menjalankan `docker compose down`; named volume tetap dipertahankan.
- `reset-database.bat`: meminta konfirmasi, lalu menghapus volume dan menjalankan stack baru.
- Untuk menutup dashboard controller, tutup jendela proses PowerShell controller. Jika ingin memulai kembali, jalankan `jalankan-sistem.bat`. Jika controller versi lama masih berjalan di port 8765, tutup jendela PowerShell controller lama sebelum menjalankan versi baru.

## Struktur proyek

```text
flask-mysql-docker-lab/
├── jalankan-sistem.bat
├── hentikan-sistem.bat
├── reset-database.bat
├── Dockerfile
├── compose.yaml
├── requirements.txt
├── .env.example
├── .dockerignore
├── .gitignore
├── app/
│   ├── app.py
│   └── templates/
│       ├── index.html
│       └── error.html
├── dashboard/
│   ├── index.html
│   └── controller.ps1
├── scripts/
│   └── initialize-env.ps1
└── reports/                 # dibuat setelah tes dijalankan
```

## Koreksi dan pengamanan versi ini

- Proses pembersihan data uji sekarang tidak sengaja menghapus record yang sama dua kali; jika langkah tes gagal, controller mencoba cleanup ulang dan menulis peringatan bila data mungkin masih tersisa.
- Tes T04 dan T05 menandai service sebagai perlu dipulihkan sebelum menjalankan langkah yang berisiko menghentikan container/database.
- Tindakan `down -v` pada Command Center membutuhkan konfirmasi UI dan penanda konfirmasi pada permintaan controller. Tetap anggap tindakan ini destruktif.
- Ekspor CSV menggunakan BOM UTF-8 agar karakter lebih konsisten saat dibuka di Excel.
- Jika file JSON laporan gagal disimpan, dashboard menampilkan peringatan dan tidak menampilkan tautan file yang sebenarnya tidak ada.
- Skrip reset memeriksa Docker Engine dan menyiapkan `.env`; dashboard hanya dibuka otomatis jika controller aktif.

## Keamanan dan batasan

- Controller PowerShell hanya bind ke `127.0.0.1:8765`. Jangan mengubahnya ke `0.0.0.0`.
- API controller hanya menerima aksi Docker yang ditentukan; tidak ada endpoint untuk menjalankan shell bebas.
- Password dibuat di `.env` lokal. `.env` tidak dimasukkan ke ZIP.
- Status dashboard berasal dari Docker Compose dan endpoint Flask aktual, bukan indikator dekoratif.
- Paket ini telah diperiksa secara statis di lingkungan pembuatan. Pengujian end-to-end Windows/Docker Desktop harus dilakukan di laptop pengguna karena lingkungan ini tidak menyediakan Docker Desktop/Windows PowerShell.


## Hasil validasi edisi perbaikan

Audit statis terbaru menjalankan **70 pemeriksaan: 65 PASS, 0 FAIL, dan 5 BLOCKED runtime**. Pemeriksaan mencakup sintaks Python dan JavaScript, parse YAML, konfigurasi port/volume/healthcheck, katalog tes, pengamanan reset, pembersihan data uji, ekspor laporan, serta konsistensi materi. Lima pemeriksaan runtime berstatus BLOCKED karena lingkungan penyusunan tidak menyediakan Docker CLI/Engine, Windows PowerShell, dependensi Flask/MySQL, atau runtime Windows. Ini bukan klaim bahwa container sudah berhasil dijalankan.

Lihat `Dokumentasi/Hasil_Audit_Statis_Aktual.json`, `Dokumentasi/Hasil_Audit_Statis_Aktual.csv`, dan `Dokumentasi/KOREKSI-DAN-VALIDASI.md` untuk rincian.


## Membersihkan seluruh resource Docker proyek

Jalankan `HAPUS-SELURUH-DATA-DOCKER.bat` dari folder proyek. Skrip meminta konfirmasi
dengan mengetik `HAPUS`, lalu menjalankan cleanup yang dibatasi pada `compose.yaml`
proyek ini. Container, named volume database, network, dan image aplikasi lokal milik
proyek dibersihkan; dashboard controller proyek juga dihentikan.

**Peringatan:** data dalam volume database proyek akan hilang. Source code, `.env`,
laporan, screenshot, Docker Desktop, image dasar `mysql:8.4`, dan resource Docker
proyek lain tetap dipertahankan. Jangan gunakan perintah pembersihan Docker global.
Baca `PANDUAN-HAPUS-RESOURCE-DOCKER.txt`.


Jika startup gagal dengan error GetFullPath / Illegal characters in path, lihat PERBAIKAN-WINDOWS11-PATH.txt.
