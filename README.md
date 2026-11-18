# GNC Kantor AI — Installer satu perintah

Repo: https://github.com/ferdiptgnc/kantoraignc

Installer satu file untuk memasang **kantor AI kosong** di PC, VM, atau Proxmox CT milik klien. Setelah terpasang, klien menambah "karyawan AI" sendiri lewat menu `kantorai`. Paket ini tidak membawa karyawan, SOUL.md, skill, maupun data GNC: setiap instalasi dimulai dari nol.

## Yang dipasang

| Komponen | Keterangan |
|---|---|
| **Hermes Agent** | Mesin AI tiap karyawan. Gateway Telegram dipasang sebagai *system service* root (`hermes-gateway`). Satu gateway melayani semua karyawan. |
| **Panel Hermes** | Dashboard web resmi Hermes (`kantorai-dashboard`, port 9119) dengan **tema GNC** dan **plugin GNC** (tab *Kantor*, lambang di header, footer). Tidak memakai fork, jadi aman saat `hermes update`. |
| **Kantor 3D** | [Ruang](https://github.com/yugienugraha/ruang) (MIT), port 3001 lewat nginx. Badge GNC disisipkan nginx tanpa mengubah kode Ruang. |
| **Portal kantor** | Halaman depan bermerek (port 8080): pintu ke Kantor 3D dan Panel, daftar karyawan, status layanan. |
| **Pengawas** | Watchdog tanpa AI. Cek tiap 2 menit, restart layanan yang mati (maksimal 3 kali per jam), lapor ke Telegram, laporan harian + backup otomatis pukul 07:05. |
| **Menu `kantorai`** | Menu interaktif (whiptail) dan perintah CLI untuk semua urusan harian. |
| Opsional | Chromium untuk tool browser agen, Cloudflare Tunnel (akun Cloudflare milik klien). |

## Syarat

- Debian 12/13 atau Ubuntu 22.04/24.04 dengan systemd. Proxmox CT dengan template standar sudah memenuhi.
- x86_64 atau aarch64, RAM minimal 2 GB (disarankan 4 GB atau lebih), disk kosong minimal 8 GB (disarankan 20 GB).
- Login sebagai root dan ada koneksi internet.
- Kunci API model AI atau akun provider (OpenRouter, Anthropic, Claude Subscription, Nous Portal, dan lain-lain).
- Bot Telegram dari @BotFather: satu untuk admin, satu untuk tiap karyawan.

## Cara pasang

```bash
# Debian minimal biasanya sudah punya wget
wget -qO- https://raw.githubusercontent.com/ferdiptgnc/kantoraignc/main/install-kantorai.sh | bash

# atau
curl -fsSL https://raw.githubusercontent.com/ferdiptgnc/kantoraignc/main/install-kantorai.sh | bash
```

Wizard akan menanyakan:
1. Nama kantor.
2. Zona waktu.
3. Mode akses web (lokal atau LAN).
4. Komponen yang dipasang dan port.
5. Login web (khusus mode LAN).
6. Bot admin Telegram dan user ID.
7. Model AI, dipilih lewat menu resmi Hermes.

Instalasi memakan waktu sekitar 5–15 menit. Ringkasannya tersimpan di `/etc/kantorai/INSTALL-INFO.txt` (hanya bisa dibaca root), dan log-nya di `/var/log/kantorai.log`.

### Tanpa dialog (banyak klien)

```bash
wget https://raw.githubusercontent.com/ferdiptgnc/kantoraignc/main/install-kantorai.sh
wget https://raw.githubusercontent.com/ferdiptgnc/kantoraignc/main/kantorai.conf.example -O klien-a.conf
nano klien-a.conf          # isi nama kantor, mode akses, token bot, model
chmod 600 klien-a.conf
bash install-kantorai.sh --unattended --config klien-a.conf
shred -u klien-a.conf      # hapus: berisi token & password
```

## Setelah terpasang

```bash
kantorai                   # buka menu
```

Urutan yang disarankan:
1. **Model AI admin**, kalau belum dipilih saat instalasi.
2. **Telegram → Grup forum kantor**:
   1. Buat grup dan aktifkan Topics.
   2. Masukkan bot admin sebagai admin dengan izin *Manage Topics*.
   3. Pilih *Deteksi otomatis*.
3. **Karyawan AI → Tambah karyawan**:
   1. Isi nama profil, jabatan, dan tugas.
   2. Pilih skill bawaan atau profil kosong.
   3. Masukkan token bot karyawan.
   4. Topik grup dibuat otomatis. Model bisa sama dengan admin atau dipilih sendiri.
4. Di @BotFather: matikan *Group Privacy* setiap bot, lalu masukkan bot ke grup sebagai admin.
5. **Telegram → Buat topik Pengawas**, supaya notifikasi Pengawas punya topik sendiri.

Kepribadian dan aturan tiap karyawan ada di `SOUL.md`. Untuk mengubahnya pilih **Karyawan AI → Ubah jabatan & kepribadian** (file terbuka di nano).

## Menu & perintah

```
kantorai                         menu interaktif
kantorai status                  ringkasan status kantor
kantorai restart [semua|gateway|panel|kantor3d|nginx]
kantorai karyawan [daftar|tambah|hapus NAMA]
kantorai model [NAMA]            pilih model AI (tanpa NAMA = admin)
kantorai logs [gateway|errors|panel|kantor3d|pengawas|installer|NAMA]
kantorai backup                  backup sekarang
kantorai restore FILE.zip        pulihkan dari backup
kantorai pengawas [periksa|uji|status]
kantorai web [lokal|lan|password]
kantorai update [hermes|kantor3d|self]
kantorai doctor                  diagnosa
kantorai info                    alamat & info instalasi
kantorai uninstall               hapus GNC Kantor AI
```

Isi menu utama:
- Status
- Karyawan AI: tambah, ubah SOUL, model, token bot, uji jawaban, chat, skill, hapus
- Layanan
- Model
- Telegram: bot admin, grup forum, topik karyawan, topik Pengawas, cek bot
- Web & branding: mode akses, password, port, nama kantor, logo klien, komponen, URL publik, Cloudflare Tunnel
- Log (token disensor otomatis)
- Backup & restore
- Pengawas
- Update
- Diagnosa
- Info

Terminal tanpa whiptail bisa memakai menu teks biasa: `KA_PLAIN=1 kantorai`.

## Mode akses & keamanan

| Mode | Perilaku |
|---|---|
| **lokal** (bawaan) | Semua layanan web hanya mendengarkan di `127.0.0.1`. Buka lewat SSH tunnel; perintah lengkapnya ditampilkan installer dan `kantorai web`. |
| **lan** | Portal dan Kantor 3D dilindungi login nginx. Panel Hermes memakai login bawaan Hermes, dengan username/password yang sama. |

- Token bot dan kunci API hanya disimpan di `~/.hermes/.env` (dan `.env` tiap profil) dengan chmod 600. Token tidak pernah tampil di layar, di log, maupun di argumen perintah. Panggilan ke API Telegram mengirim token lewat stdin `curl`.
- Satu bot hanya boleh dipakai satu karyawan. Menu menolak token yang sudah dipakai karyawan lain.
- Nama karyawan yang sama dengan perintah sistem (mis. `curl`, `nano`) ditolak, karena Hermes membuat perintah `/root/.local/bin/<nama>`.
- Akses dari internet sebaiknya lewat Cloudflare Tunnel **ditambah Cloudflare Access**. Login bawaan Hermes ditujukan untuk jaringan tepercaya, jadi Panel Hermes sebaiknya tetap di LAN/VPN.
- Semua layanan berjalan sebagai root, sesuai standar instalasi GNC.

## Lokasi file

| Path | Isi |
|---|---|
| `/opt/kantorai/` | Salinan repo dan aset |
| `/usr/local/bin/kantorai` | Menu |
| `/usr/local/lib/kantorai/` | `common.sh`, `setup.sh`, `pengawas.sh` |
| `/etc/kantorai/kantorai.conf` | Pengaturan (tanpa rahasia) |
| `/etc/kantorai/INSTALL-INFO.txt` | Ringkasan dan login web (chmod 600) |
| `/etc/kantorai/brand/` | Logo klien |
| `/root/.hermes/` | Data Hermes: karyawan, memori, sesi, skill |
| `/root/.hermes/dashboard-themes/gnc.yaml` | Tema Panel Hermes |
| `/root/.hermes/plugins/gnc-kantor/` | Plugin Panel Hermes |
| `/var/www/kantorai/` | Portal, `status.json`, branding Kantor 3D |
| `/etc/nginx/conf.d/kantorai.conf` | nginx (dibuat ulang otomatis; ubah lewat menu) |
| `/var/backups/kantorai/` | Backup harian dan arsip profil yang dihapus |

## Update, perbaikan, uninstall

```bash
kantorai update hermes        # perbarui Hermes Agent
kantorai update kantor3d      # perbarui Ruang
kantorai update self          # perbarui kantorai dari GitHub (memakai --repair)
bash install-kantorai.sh --repair   # pasang ulang komponen dengan pengaturan tersimpan
kantorai uninstall            # data Hermes & backup tidak dihapus kecuali dipilih
```

## Struktur repo

```
install-kantorai.sh        installer (aman dijalankan via wget | bash)
kantorai                   menu pengelolaan
kantorai.conf.example      contoh config tanpa dialog
lib/common.sh              tampilan, validasi, .env, Telegram, helper Hermes
lib/setup.sh               langkah pemasangan & penerapan konfigurasi (dipakai installer & menu)
lib/pengawas.sh            Pengawas
assets/dashboard/          tema & plugin Panel Hermes
assets/portal/             portal kantor
assets/ruang-brand/        badge GNC untuk Kantor 3D
assets/templates/          SOUL.md karyawan baru
uji/                       uji otomatis dengan Hermes/systemd tiruan
```

## Pengujian

```bash
bash uji/uji_kantorai.sh      # butuh: bash, jq, nginx, openssl, python3, node
```

Uji ini berjalan di folder sementara dengan Hermes, systemd, dan API Telegram tiruan, tanpa menyentuh sistem asli. Yang dicakup:
- instalasi tanpa dialog dan mode perbaikan
- menu karyawan, grup, dan topik
- mode akses, dengan `nginx -t` memakai nginx asli
- Pengawas: pemulihan, notifikasi, dan backup
- API dan render plugin dashboard
- tidak ada token yang bocor ke log atau argumen perintah

## Kredit

- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — Nous Research (MIT)
- [Ruang](https://github.com/yugienugraha/ruang) — Yugie Nugraha (MIT)

GNC Kantor AI · Galura Nexa Core — Technology Infrastructure
