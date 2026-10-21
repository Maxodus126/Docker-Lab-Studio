DOCKER LAB STUDIO — PAKET TERPADU WEB + TERMINAL
=================================================

MULAI CEPAT
1. Ekstrak ZIP ini ke folder biasa, misalnya C:\DockerLabStudio.
2. Buka Docker Desktop dan tunggu Docker Engine siap.
3. Klik dua kali jalankan-sistem.bat.
4. Dashboard kontrol: http://127.0.0.1:8765/
5. Aplikasi mahasiswa: http://127.0.0.1:5000/
6. Jalankan semua tes non-destruktif dari PowerShell: .\uji-semua-tes.ps1
   atau klik uji-semua-tes.bat.
7. Tes individual: .\uji-semua-tes.ps1 -TestId T03.
8. T06 menghapus named volume; hanya jalankan setelah backup, bukti T04 tersimpan,
   dan konfirmasi eksplisit dilakukan.

ISI ZIP
- Source aplikasi Flask + MySQL 8.4 + Docker Compose.
- Dashboard kontrol, Test Center, Command Center, dan CRUD mahasiswa.
- jalankan-sistem.bat, hentikan-sistem.bat, reset-database.bat,
  HAPUS-SELURUH-DATA-DOCKER.bat, uji-semua-tes.ps1, dan uji-semua-tes.bat.
- Laporan Word/PDF terpadu, screenshot web dan terminal, transkrip,
  contoh JSON/CSV, serta hasil audit statis.

KETERANGAN PENTING
- Screenshot web dan terminal pada folder Bukti merupakan simulasi visual untuk bahan belajar.
  Caption laporan menandai setiap gambar sebagai simulasi.
- Audit statis edisi perbaikan: 65 PASS, 0 FAIL, 5 BLOCKED runtime dari 70 pemeriksaan.
- Docker runtime belum dapat dijalankan di lingkungan penyusunan karena Docker CLI/Engine
  dan Windows PowerShell tidak tersedia. Saat dijalankan di laptop, status aktual berasal
  dari perintah Docker dan HTTP yang dieksekusi controller lokal.
- Jangan membagikan file .env atau password database.

Keterangan bukti: screenshot contoh di folder Bukti adalah visual simulasi untuk bahan belajar; caption laporan menyebutkan simulasi. Untuk bukti runtime aktual, ambil screenshot dari laptop setelah menjalankan tes.

PEMBERSIHAN RESOURCE DOCKER
- Klik HAPUS-SELURUH-DATA-DOCKER.bat untuk menghapus container, volume database, network, dan image aplikasi lokal milik proyek ini.
- Skrip meminta konfirmasi dengan mengetik HAPUS. Data dalam volume database akan hilang permanen.
- Source code, .env, laporan, screenshot, Docker Desktop, image mysql:8.4, dan resource proyek lain tetap dipertahankan.
- Baca PANDUAN-HAPUS-RESOURCE-DOCKER.txt sebelum menjalankan pembersihan.


Jika startup gagal dengan error GetFullPath / Illegal characters in path, lihat PERBAIKAN-WINDOWS11-PATH.txt.
