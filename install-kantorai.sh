#!/usr/bin/env bash
#
# ============================================================================
#  install-kantorai.sh — Installer satu perintah GNC Kantor AI
#  Galura Nexa Core — Technology Infrastructure
# ============================================================================
#  Memasang "kantor AI" kosong yang siap diisi karyawan:
#    • Hermes Agent + gateway Telegram (system service, root)
#    • Panel Hermes (dashboard web) dengan tema & plugin GNC
#    • Kantor 3D (Ruang) dengan branding GNC
#    • Portal kantor, Pengawas (watchdog + notifikasi), backup harian
#    • Menu pengelolaan: kantorai
#
#  Cara pakai (sebagai root, Debian 12/13 atau Ubuntu 22.04/24.04):
#    wget -qO- https://raw.githubusercontent.com/ferdiptgnc/kantoraignc/main/install-kantorai.sh | bash
#    curl -fsSL https://raw.githubusercontent.com/ferdiptgnc/kantoraignc/main/install-kantorai.sh | bash
#
#  Tanpa dialog (deploy massal):
#    bash install-kantorai.sh --unattended --config klien.conf
#
#  Server yang SUDAH menjalankan Hermes (tanpa mengubah yang sudah berjalan):
#    bash install-kantorai.sh --adopt --check    # lihat rencana perubahan saja
#    bash install-kantorai.sh --adopt            # terapkan
#
#  Opsi lain: --source DIR (pakai salinan lokal repo), --repair (pasang ulang
#  komponen dengan pengaturan tersimpan), --help
# ============================================================================

set -Euo pipefail

INSTALLER_VERSION="1.2.0"
REPO_DEFAULT="ferdiptgnc/kantoraignc"

b_say() { printf '\e[36m==>\e[0m %s\n' "$*"; }
b_die() { printf '\e[31m[GAGAL]\e[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Installer GNC Kantor AI

Pemakaian (root):
  bash install-kantorai.sh                     instalasi interaktif (dialog)
  bash install-kantorai.sh --unattended --config FILE
                                               instalasi tanpa dialog (lihat kantorai.conf.example)
  bash install-kantorai.sh --repair            pasang ulang komponen dengan pengaturan tersimpan
  bash install-kantorai.sh --adopt [--check] [--yes]
                                               pasang di server yang SUDAH menjalankan Hermes:
                                               gateway, karyawan, Telegram, model, zona waktu,
                                               dan Kantor 3D yang ada tidak disentuh
  bash install-kantorai.sh --source DIR        pakai salinan repo lokal (tanpa unduh dari GitHub)
  bash install-kantorai.sh --repo OWNER/REPO --branch NAMA
  bash install-kantorai.sh --version | --help

Variabel KA_* di kantorai.conf.example bisa juga diberikan lewat environment.
EOF
}

UNATTENDED=0; REPAIR=0; ADOPT=0; CHECK=0; ASSUME_YES=0; SRC=""; CONFIG_FILE=""
parse_args() {
  while (($#)); do
    case $1 in
      --unattended) UNATTENDED=1 ;;
      --repair) REPAIR=1; UNATTENDED=1 ;;
      --adopt) ADOPT=1; UNATTENDED=1 ;;
      --check) CHECK=1 ;;
      -y|--yes) ASSUME_YES=1 ;;
      --config) [[ -n ${2:-} ]] || b_die "--config butuh path file"; CONFIG_FILE=$2; shift ;;
      --source) [[ -n ${2:-} ]] || b_die "--source butuh path folder"; SRC=$2; shift ;;
      --repo) [[ -n ${2:-} ]] || b_die "--repo butuh OWNER/REPO"; KA_REPO=$2; shift ;;
      --branch) [[ -n ${2:-} ]] || b_die "--branch butuh nama branch"; KA_BRANCH=$2; shift ;;
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "$INSTALLER_VERSION"; exit 0 ;;
      *) b_die "Opsi tidak dikenal: $1 (lihat --help)" ;;
    esac
    shift
  done
  if [[ -n $CONFIG_FILE ]]; then
    [[ -r $CONFIG_FILE ]] || b_die "File config tidak bisa dibaca: $CONFIG_FILE"
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi
}

# Saat dijalankan via "wget ... | bash", stdin adalah pipe: sambungkan ke terminal.
attach_tty() {
  if ((ADOPT)); then   # konfirmasi rencana butuh terminal bila ada; tidak wajib (--yes)
    [[ -t 0 ]] || { (: </dev/tty) 2>/dev/null && exec </dev/tty; }
    return 0
  fi
  ((UNATTENDED)) && return 0
  [[ -t 0 ]] && return 0
  if (: </dev/tty) 2>/dev/null; then exec </dev/tty
  else b_die "Tidak ada terminal interaktif. Jalankan 'bash install-kantorai.sh' langsung atau pakai --unattended."
  fi
}

# Ambil isi repo (lib/, assets/, kantorai) — dari folder lokal atau GitHub.
bootstrap_source() {
  local self_dir="" tmp url
  if [[ -z $SRC && -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    [[ -f $self_dir/lib/common.sh && -f $self_dir/kantorai ]] && SRC=$self_dir
  fi
  if [[ -n $SRC ]]; then
    [[ -f $SRC/lib/common.sh ]] || b_die "Folder sumber tidak lengkap: $SRC"
    return 0
  fi
  KA_REPO=${KA_REPO:-$REPO_DEFAULT}; KA_BRANCH=${KA_BRANCH:-main}
  url="https://codeload.github.com/$KA_REPO/tar.gz/refs/heads/$KA_BRANCH"
  tmp=$(mktemp -d /tmp/kantorai-src.XXXXXX)
  b_say "Mengunduh paket GNC Kantor AI ($KA_REPO@$KA_BRANCH)..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 "$url" -o "$tmp/src.tgz" || b_die "Gagal mengunduh $url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp/src.tgz" "$url" || b_die "Gagal mengunduh $url"
  else
    b_die "curl/wget tidak ada. Pasang dulu: apt-get install -y wget"
  fi
  tar -xzf "$tmp/src.tgz" -C "$tmp" || b_die "Arsip paket rusak"
  SRC=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)
  [[ -f $SRC/lib/common.sh ]] || b_die "Isi paket tidak lengkap (lib/common.sh tidak ada)"
}

# ---------------------------------------------------------------------------
# Pemeriksaan awal
# ---------------------------------------------------------------------------
preflight() {
  [[ $EUID -eq 0 ]] || die "Jalankan sebagai root (su - atau sudo -i)."
  command -v apt-get >/dev/null 2>&1 || die "Hanya untuk Debian/Ubuntu (apt-get tidak ditemukan)."
  [[ -d /run/systemd/system || ${KA_ALLOW_NO_SYSTEMD:-0} == 1 ]] || die "systemd tidak berjalan. Untuk Proxmox CT, pakai template Debian/Ubuntu standar (systemd aktif)."
  mkdir -p "$(dirname "$KA_LOG")"; touch "$KA_LOG"; chmod 600 "$KA_LOG"
  logf "===== Mulai instalasi GNC Kantor AI v$KA_VERSION ====="
  export DEBIAN_FRONTEND=noninteractive
}

check_os() {
  local id ver name arch ok=0
  id=$(. /etc/os-release 2>/dev/null; echo "${ID:-}")
  ver=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
  name=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-tidak diketahui}")
  arch=$(uname -m)
  case "$id:$ver" in debian:12|debian:13|ubuntu:22.04|ubuntu:24.04) ok=1 ;; esac
  [[ $arch == x86_64 || $arch == aarch64 ]] || die "Arsitektur $arch tidak didukung (butuh x86_64/aarch64)."
  if ((ok)); then okp "OS: $name ($arch)"; return 0; fi
  warnp "OS $name belum diuji (didukung: Debian 12/13, Ubuntu 22.04/24.04)."
  if ((UNATTENDED)); then [[ ${KA_FORCE_OS:-0} == 1 ]] || die "Set KA_FORCE_OS=1 bila tetap ingin lanjut."
  else ui_yesno "OS belum diuji" "OS terdeteksi: $name\n\nInstaller diuji untuk Debian 12/13 dan Ubuntu 22.04/24.04.\nTetap lanjutkan?" no || exit 1
  fi
}

check_resources() {
  local ram disk w=""
  ram=$(awk '/^MemTotal/{print int($2/1024)}' /proc/meminfo)
  disk=$(df -Pm / | awk 'NR==2{print $4}')
  ((ram < 1800)) && w+="- RAM ${ram} MB (minimal 2 GB, disarankan 4 GB atau lebih)\n"
  ((disk < 8000)) && w+="- Disk kosong ${disk} MB (minimal 8 GB, disarankan 20 GB)\n"
  logf "RAM=${ram}MB disk_free=${disk}MB cpu=$(nproc)"
  [[ -z $w ]] && return 0
  warnp "Sumber daya terbatas:"; printf '%b' "$w" >&2
  if ((! UNATTENDED)); then ui_yesno "Sumber daya terbatas" "$w\nTetap lanjutkan?" no || exit 1; fi
}

check_internet() {
  local h
  for h in github.com hermes-agent.nousresearch.com api.telegram.org; do
    getent hosts "$h" >/dev/null 2>&1 || die "Tidak bisa resolve $h. Periksa DNS/internet."
  done
  okp "Koneksi internet tersedia"
}

install_prereqs() {
  NGINX_PRE=$(command -v nginx || true)
  local pk=(ca-certificates curl wget git whiptail jq tar gzip unzip xz-utils openssl procps iproute2 nano less cron)
  if [[ $KA_WITH_PORTAL == yes || $KA_WITH_RUANG == yes ]]; then pk+=(nginx); fi
  say "Paket dasar sistem"
  pr_begin
  pr_task 0 35 25 "Memperbarui daftar paket (apt-get update)" apt-get update \
    || { pr_end 1 "apt-get update gagal (lihat $KA_LOG)"; exit 1; }
  pr_task 35 100 60 "Memasang ${#pk[@]} paket: whiptail, curl, git, jq, nginx, ..." \
    apt-get install -y --no-install-recommends "${pk[@]}" \
    || { pr_end 1 "Gagal memasang paket dasar (lihat $KA_LOG)"; exit 1; }
  pr_end 0 "Paket dasar terpasang"
}

# ---------------------------------------------------------------------------
# Wizard
# ---------------------------------------------------------------------------
pick_free_port() { # pick_free_port PORT -> port itu bila bebas, kalau tidak +1
  local p=$1; while port_busy "$p"; do p=$((p + 1)); done; printf '%s' "$p"
}

collect_interactive() {
  TUI=1
  local sel tz
  whiptail --backtitle "$BT" --title "GNC Kantor AI" --msgbox \
"Selamat datang di installer GNC Kantor AI.

Yang akan dipasang di server ini:
  • Hermes Agent: mesin AI para karyawan, gateway Telegram
  • Panel Hermes: dashboard web bertema GNC
  • Kantor 3D: tampilan kantor virtual para karyawan AI
  • Portal kantor dan Pengawas (pemulihan otomatis + notifikasi)
  • Menu pengelolaan: perintah  kantorai

Kantor dipasang KOSONG. Karyawan AI ditambahkan setelah instalasi lewat
menu kantorai -> Karyawan AI.

Terdeteksi: $(nproc) CPU, $(awk '/^MemTotal/{print int($2/1024)}' /proc/meminfo) MB RAM, IP $(local_ip)" 22 "$W" >"$KA_TTY"

  ui_input KA_OFFICE_NAME "Nama kantor" "Nama kantor / perusahaan yang tampil di portal, panel, dan Kantor 3D:" \
    "$KA_OFFICE_NAME" valid_office "Maksimal 60 karakter, tanpa tanda kutip, \$, \`, < atau >." || exit 1

  tz=$(ui_menu "Zona waktu" "Zona waktu server (dipakai jadwal karyawan & laporan):" \
        Asia/Jakarta "WIB" Asia/Makassar "WITA" Asia/Jayapura "WIT" UTC "UTC") || exit 1
  KA_TZ=$tz

  sel=$(ui_menu "Akses web" "Dari mana panel, portal, dan Kantor 3D dibuka?" \
        local "Hanya dari server ini (lewat SSH tunnel) — paling aman" \
        lan   "Dari jaringan kantor (LAN), wajib login username/password") || exit 1
  KA_ACCESS_MODE=$sel

  sel=$(ui_checklist "Komponen" "Pilih komponen yang dipasang (Spasi = pilih/batal):" \
        dashboard "Panel Hermes (dashboard web) bertema GNC" ON \
        ruang     "Kantor 3D (Ruang)" ON \
        portal    "Portal kantor (halaman depan + status)" ON \
        pengawas  "Pengawas: pulihkan otomatis + notifikasi + backup harian" ON \
        browser   "Browser Chromium untuk agen (butuh ~1 GB disk)" OFF \
        cloudflare "Cloudflare Tunnel (akses dari internet)" OFF) || exit 1
  KA_WITH_DASHBOARD=no; KA_WITH_RUANG=no; KA_WITH_PORTAL=no; KA_WITH_PENGAWAS=no; KA_WITH_BROWSER=no; KA_WITH_CLOUDFLARED=no
  [[ $sel == *dashboard* ]] && KA_WITH_DASHBOARD=yes
  [[ $sel == *ruang* ]] && KA_WITH_RUANG=yes
  [[ $sel == *portal* ]] && KA_WITH_PORTAL=yes
  [[ $sel == *pengawas* ]] && KA_WITH_PENGAWAS=yes
  [[ $sel == *browser* ]] && KA_WITH_BROWSER=yes
  [[ $sel == *cloudflare* ]] && KA_WITH_CLOUDFLARED=yes

  if [[ $KA_WITH_PORTAL == yes ]]; then
    ui_input KA_PORTAL_PORT "Port portal" "Port web portal kantor:" "$(pick_free_port "$KA_PORTAL_PORT")" valid_port || exit 1
  fi
  if [[ $KA_WITH_RUANG == yes ]]; then
    ui_input KA_RUANG_PORT "Port Kantor 3D" "Port web Kantor 3D:" "$(pick_free_port "$KA_RUANG_PORT")" valid_port || exit 1
  fi
  if [[ $KA_WITH_DASHBOARD == yes ]]; then
    ui_input KA_DASH_PORT "Port Panel Hermes" "Port web Panel Hermes:" "$(pick_free_port "$KA_DASH_PORT")" valid_port || exit 1
  fi

  if [[ $KA_ACCESS_MODE == lan ]]; then
    ui_input KA_WEB_USER "Login web" "Username untuk membuka panel, portal, dan Kantor 3D dari LAN:" \
      "$KA_WEB_USER" valid_username "3-32 karakter: huruf, angka, titik, minus, garis bawah." || exit 1
    if ui_yesno "Password web" "Buat password acak yang kuat secara otomatis?\n\n(Pilih No untuk mengetik sendiri.)"; then
      KA_WEB_PASS=$(gen_password 18)
    else
      ui_pass KA_WEB_PASS "Password web" 10 || exit 1
    fi
  fi

  if [[ $KA_WITH_CLOUDFLARED == yes ]]; then
    ui_secret KA_CF_TOKEN "Cloudflare Tunnel" \
"Tempel token tunnel dari Cloudflare Zero Trust -> Networks -> Tunnels -> Create
(bagian 'Install connector', string panjang setelah 'service install').

Kosongkan untuk melewati." || true
    [[ -z $KA_CF_TOKEN ]] && KA_WITH_CLOUDFLARED=no
  fi

  collect_telegram_admin

  sel=$(ui_menu "Model AI" "Bagaimana memilih model AI (otak) kantor?" \
        interactive "Pilih sekarang lewat menu resmi Hermes (disarankan)" \
        skip        "Nanti saja (kantorai -> Model AI)") || exit 1
  KA_MODEL_MODE=$sel
}

collect_telegram_admin() {
  local tok uname ids
  ui_yesno "Bot admin Telegram" \
"Kantor AI dikendalikan lewat Telegram. Bot admin dipakai untuk:
  • chat dengan asisten utama kantor
  • notifikasi Pengawas (layanan mati, disk penuh, laporan harian)

Siapkan dari @BotFather: /newbot -> catat tokennya.
User ID Telegram Anda bisa dilihat lewat @userinfobot.

Atur bot admin sekarang?" || return 0

  while true; do
    ui_secret tok "Token bot admin" "Tempel token bot dari @BotFather (tidak ditampilkan di layar):" || return 0
    [[ -z $tok ]] && return 0
    if ! valid_bot_token "$tok"; then ui_msg "Token tidak valid" "Format token: 123456789:AAH... (dari @BotFather)."; continue; fi
    ui_info "Memeriksa token ke Telegram..."
    if uname=$(tg_bot_username "$tok"); then
      ui_msg "Bot ditemukan" "Token valid: @$uname" 9; KA_TG_ADMIN_TOKEN=$tok; break
    fi
    ui_yesno "Token belum bisa dicek" "Telegram menolak token ini atau server belum bisa menghubungi api.telegram.org.\n\nTetap simpan token ini?" no && { KA_TG_ADMIN_TOKEN=$tok; break; }
  done
  ui_input ids "User ID yang diizinkan" \
"User ID Telegram yang boleh memerintah bot (pisahkan koma bila lebih dari satu).
Contoh: 123456789,987654321" "$KA_TG_USERS" valid_user_ids "Hanya angka, dipisah koma tanpa spasi." || return 0
  KA_TG_USERS=$ids
}

collect_unattended() {
  [[ $KA_ACCESS_MODE == local || $KA_ACCESS_MODE == lan ]] || die "KA_ACCESS_MODE harus local atau lan"
  valid_office "$KA_OFFICE_NAME" || die "KA_OFFICE_NAME tidak valid"
  valid_tz "$KA_TZ" || die "KA_TZ tidak valid: $KA_TZ"
  local p; for p in "$KA_PORTAL_PORT" "$KA_RUANG_PORT" "$KA_DASH_PORT" "$KA_RUANG_INTERNAL_PORT"; do valid_port "$p" || die "Port tidak valid: $p"; done
  if [[ $KA_ACCESS_MODE == lan ]]; then
    valid_username "$KA_WEB_USER" || die "KA_WEB_USER tidak valid"
    [[ -n $KA_WEB_PASS ]] || KA_WEB_PASS=$(gen_password 18)
  fi
  [[ -z $KA_TG_ADMIN_TOKEN ]] || valid_bot_token "$KA_TG_ADMIN_TOKEN" || die "KA_TG_ADMIN_TOKEN tidak valid"
  [[ -z $KA_TG_USERS ]] || valid_user_ids "$KA_TG_USERS" || die "KA_TG_USERS tidak valid"
  [[ $KA_MODEL_MODE == interactive ]] && KA_MODEL_MODE=config
  [[ -z $KA_CF_TOKEN ]] && KA_WITH_CLOUDFLARED=no
  return 0
}

confirm_summary() {
  local s
  s="Nama kantor : $KA_OFFICE_NAME
Zona waktu  : $KA_TZ
Akses web   : $([[ $KA_ACCESS_MODE == lan ]] && echo "LAN (login: $KA_WEB_USER)" || echo "lokal (SSH tunnel)")
Komponen    : Hermes$([[ $KA_WITH_DASHBOARD == yes ]] && echo ", Panel :$KA_DASH_PORT")$([[ $KA_WITH_RUANG == yes ]] && echo ", Kantor 3D :$KA_RUANG_PORT")$([[ $KA_WITH_PORTAL == yes ]] && echo ", Portal :$KA_PORTAL_PORT")
              $([[ $KA_WITH_PENGAWAS == yes ]] && echo "Pengawas") $([[ $KA_WITH_BROWSER == yes ]] && echo "Chromium") $([[ $KA_WITH_CLOUDFLARED == yes ]] && echo "Cloudflare-Tunnel")
Bot admin   : $([[ -n $KA_TG_ADMIN_TOKEN ]] && echo "diatur" || echo "belum (bisa nanti)")
Model AI    : $([[ $KA_MODEL_MODE == interactive ]] && echo "pilih setelah Hermes terpasang" || echo "$KA_MODEL_MODE")

Instalasi memakan waktu 5-15 menit tergantung internet."
  ((UNATTENDED)) && { printf '%s\n' "$s"; return 0; }
  ui_yesno "Konfirmasi" "$s\n\nMulai instalasi?" "" 22 || exit 1
}

# ---------------------------------------------------------------------------
# Langkah instalasi
# ---------------------------------------------------------------------------
STEP=0; STEPS=10; T_START=$SECONDS
step() {
  STEP=$((STEP + 1))
  printf '\n%s[%d/%d]%s %s%s  %s(total %d%% · %s)%s\n' "$C_BLU" "$STEP" "$STEPS" "$C_RST" "$*" "" \
    "$C_DIM" $(( (STEP - 1) * 100 / STEPS )) "$(fmt_dur $(( SECONDS - T_START )))" "$C_RST"
  logf "== $* =="
}
FAILED=()

do_install() {
  TUI=0
  T_START=$SECONDS
  ((! UNATTENDED)) && clear
  show_banner

  step "Menyalin program kantorai"
  ka_install_files "$SRC" || die "Gagal menyalin program kantorai (lihat pesan di atas)."
  ka_save_conf
  okp "Program terpasang di $KA_HOME, menu: kantorai"

  step "Zona waktu: $KA_TZ"
  if ((ADOPT)); then okp "Tidak disentuh (mode adopsi)"
  elif command -v timedatectl >/dev/null 2>&1 && timedatectl set-timezone "$KA_TZ" >>"$KA_LOG" 2>&1; then okp "Zona waktu diatur"
  else ln -sf "/usr/share/zoneinfo/$KA_TZ" /etc/localtime && echo "$KA_TZ" >/etc/timezone && okp "Zona waktu diatur"; fi

  step "Hermes Agent"
  ka_install_hermes || die "Hermes Agent wajib terpasang. Perbaiki masalah di atas lalu jalankan ulang installer."

  step "Telegram & model AI"
  ((ADOPT)) && KA_MODEL_MODE=adopt
  ka_apply_telegram_admin
  [[ -n $KA_TG_ADMIN_TOKEN ]] && okp "Bot admin disimpan ke $(profile_env default) (chmod 600)"
  case $KA_MODEL_MODE in
    interactive)
      printf '\n%sMenu resmi Hermes untuk memilih provider & model akan terbuka.%s\n' "$C_YLW" "$C_RST"
      printf 'Pilih provider (mis. OpenRouter, Anthropic, Claude Subscription, Nous Portal) lalu modelnya.\n\n'
      read -r -p "Tekan Enter untuk membuka pemilih model..." _ || true
      hm model || { warnp "Pemilihan model dibatalkan. Ulangi nanti: kantorai model"; FAILED+=("model"); } ;;
    config)
      if [[ -n $KA_MODEL_PROVIDER || -n $KA_MODEL_NAME ]]; then
        ka_apply_model_config && okp "Model diatur dari file config ($KA_MODEL_PROVIDER ${KA_MODEL_NAME})"
      else
        warnp "Model belum dipilih (KA_MODEL_PROVIDER kosong). Jalankan nanti: kantorai model"
      fi ;;
    adopt) okp "Tidak disentuh: bot, user, dan model karyawan yang ada tetap" ;;
    *) warnp "Model belum dipilih. Jalankan nanti: kantorai model" ;;
  esac

  step "Gateway (system service)"
  if ((ADOPT)) && systemctl cat "$KA_GATEWAY_UNIT" >/dev/null 2>&1; then
    okp "Tidak disentuh, tidak di-restart (berjalan sejak $(systemctl show -p ActiveEnterTimestamp --value "$KA_GATEWAY_UNIT" 2>/dev/null))"
  else
    ka_install_gateway || FAILED+=("gateway")
  fi

  step "Panel Hermes + branding GNC"
  if ka_on "$KA_WITH_DASHBOARD"; then ka_install_branding; okp "Tema '$KA_THEME_NAME' & plugin '$KA_PLUGIN_NAME' terpasang"
    [[ $KA_WITH_DASHBOARD == external ]] && warnp "Panel Hermes yang sudah ada perlu di-restart sendiri agar tema & plugin GNC muncul."
  else okp "Dilewati"; fi

  step "Kantor 3D (Ruang)"
  if [[ $KA_WITH_RUANG == yes ]]; then ka_install_ruang || { FAILED+=("kantor-3d"); KA_WITH_RUANG=no; }
  elif [[ $KA_WITH_RUANG == external ]]; then okp "Memakai Kantor 3D yang sudah ada di port $KA_RUANG_PORT (tidak disentuh)"
  else okp "Dilewati"; fi

  step "Layanan web (panel, Kantor 3D, portal, nginx)"
  ka_apply_web
  if ((ADOPT)) && [[ -z $NGINX_PRE && -L /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default && ka_nginx_reload   # nginx baru: jangan ambil port 80
  fi
  ka_save_conf
  okp "Layanan web diterapkan"

  step "Pengawas & backup harian"
  if [[ $KA_WITH_PENGAWAS == yes ]]; then
    ka_enable_pengawas
    "$KA_LIBDIR/pengawas.sh" periksa --diam >>"$KA_LOG" 2>&1 || true
    if [[ $KA_PENGAWAS_MODE == penuh ]]; then okp "Pengawas aktif (cek tiap 2 menit, laporan + backup tiap 07:05)"
    else okp "Pengawas mode status: hanya mencatat status untuk portal & panel (tanpa restart/notifikasi)"; fi
  else okp "Dilewati"; fi

  step "Cloudflare Tunnel"
  if [[ $KA_WITH_CLOUDFLARED == yes ]]; then ka_install_cloudflared || FAILED+=("cloudflared")
  else okp "Dilewati"; fi

  write_info
}

write_info() {
  info_set "Versi" "GNC Kantor AI $KA_VERSION"
  info_set "Tanggal instalasi" "$(date '+%F %T %Z')"
  info_set "Nama kantor" "$KA_OFFICE_NAME"
  info_set "Mode akses" "$KA_ACCESS_MODE"
  info_set "Portal" "$([[ $KA_WITH_PORTAL == yes ]] && echo "port $KA_PORTAL_PORT" || echo off)"
  info_set "Panel Hermes" "$(ka_on "$KA_WITH_DASHBOARD" && echo "port $KA_DASH_PORT ($KA_WITH_DASHBOARD)" || echo off)"
  info_set "Kantor 3D" "$(ka_on "$KA_WITH_RUANG" && echo "port $KA_RUANG_PORT ($KA_WITH_RUANG)" || echo off)"
  if [[ $KA_ACCESS_MODE == lan ]]; then
    info_set "Login web (username)" "$KA_WEB_USER"
    [[ -n $KA_WEB_PASS ]] && info_set "Login web (password)" "$KA_WEB_PASS"
  fi
  info_set "Data Hermes" "$HERMES_HOME"
  info_set "Log" "$KA_LOG"
}

final_report() {
  local msg st
  msg="GNC Kantor AI selesai dipasang dalam $(fmt_dur $(( SECONDS - T_START ))).

$(ka_urls_text)
"
  if [[ $KA_ACCESS_MODE == lan && -n $KA_WEB_PASS ]]; then
    msg+="
Login web : $KA_WEB_USER / $KA_WEB_PASS
(Tersimpan di $KA_INFO, hanya bisa dibaca root.)
"
  fi
  msg+="
Status layanan:"
  for st in "$KA_GATEWAY_UNIT" "$KA_DASH_UNIT" "$KA_RUANG_UNIT" nginx "$KA_PENGAWAS_UNIT.timer"; do
    case $st in
      "$KA_DASH_UNIT") [[ $KA_WITH_DASHBOARD == yes ]] || continue ;;
      "$KA_GATEWAY_UNIT") ;;
      "$KA_RUANG_UNIT") [[ $KA_WITH_RUANG == yes ]] || continue ;;
      nginx) [[ $KA_WITH_PORTAL == yes || $KA_WITH_RUANG == yes ]] || continue ;;
      "$KA_PENGAWAS_UNIT.timer") [[ $KA_WITH_PENGAWAS == yes ]] || continue ;;
    esac
    msg+="
  - $(printf '%-26s' "$st") $(svc_state "$st")"
  done
  if ((${#FAILED[@]})); then
    msg+="

Perlu dicek: ${FAILED[*]}  (detail: tail -80 $KA_LOG)"
  fi
  msg+="

Langkah berikutnya:
  1. Ketik  kantorai  untuk membuka menu pengelolaan.
  2. Karyawan AI -> Tambah karyawan (siapkan bot baru dari @BotFather).
  3. Telegram -> Grup forum, bila tiap karyawan ingin punya topik sendiri."
  printf '\n%s\n' "$msg"
  logf "Instalasi selesai. Gagal: ${FAILED[*]:-tidak ada}"
}

main() {
  parse_args "$@"
  attach_tty
  bootstrap_source
  # shellcheck source=lib/common.sh
  . "$SRC/lib/common.sh"
  # shellcheck source=lib/setup.sh
  . "$SRC/lib/setup.sh"
  preflight

  if ((ADOPT)); then
    adopt_main
    return $?
  fi

  if ((REPAIR)); then
    [[ -r $KA_CONF ]] || die "Belum pernah terpasang ($KA_CONF tidak ada). Jalankan tanpa --repair."
    ka_load_conf
    UNATTENDED=1; KA_MODEL_MODE=skip
    KA_WEB_PASS=""   # password lama tetap dipakai (htpasswd & .env tidak ditimpa)
  else
    ka_defaults
    if [[ -r $KA_CONF ]] && ((! UNATTENDED)); then
      ensure_whiptail
      TUI=1
      ui_yesno "Sudah terpasang" "GNC Kantor AI sudah terpasang di server ini.\n\nUntuk perubahan pengaturan, pakai menu:  kantorai\nUntuk memperbaiki/memperbarui program:  bash install-kantorai.sh --repair\n\nTetap jalankan instalasi baru (data karyawan TIDAK dihapus)?" no || exit 0
    fi
  fi

  check_internet
  if ((REPAIR)); then
    install_prereqs
  elif ((UNATTENDED)); then
    collect_unattended; install_prereqs; check_os; check_resources
  else
    install_prereqs; TUI=1; check_os; check_resources; collect_interactive
  fi
  confirm_summary
  do_install
  final_report
}

# ---------------------------------------------------------------------------
# Mode adopsi: pasang di server yang sudah menjalankan Hermes tanpa mengubah
# yang sudah berjalan (gateway, karyawan, Telegram, model, zona waktu, Kantor 3D).
# ---------------------------------------------------------------------------
port_owner() { # -> "nama-proses (pid N)" pemakai port, kosong bila bebas
  ss -Hltnp "sport = :$1" 2>/dev/null | sed -n 's/.*users:(("\([^"]*\)",pid=\([0-9]*\).*/\1 (pid \2)/p' | head -1
}
ours_nginx_port() { [[ -f $KA_NGINX_CONF ]] && grep -q "listen [0-9.]*:$1;" "$KA_NGINX_CONF"; }

ADOPT_KEEP=(); ADOPT_ADD=(); ADOPT_WARN=()
adopt_detect() {
  local o p list gw_since other
  # Gateway & karyawan
  if systemctl cat "$KA_GATEWAY_UNIT" >/dev/null 2>&1; then
    gw_since=$(systemctl show -p ActiveEnterTimestamp --value "$KA_GATEWAY_UNIT" 2>/dev/null)
    ADOPT_KEEP+=("Gateway Hermes ($(svc_state "$KA_GATEWAY_UNIT") sejak ${gw_since:-?}): tidak di-restart")
  else
    ADOPT_WARN+=("Service $KA_GATEWAY_UNIT tidak ditemukan: gateway akan dipasang sebagai system service root")
  fi
  list=$(list_profiles | paste -sd, - | sed 's/,/, /g')
  ADOPT_KEEP+=("Karyawan: default${list:+, $list} (SOUL, memori, skill, cron, token bot tidak disentuh)")
  ADOPT_KEEP+=("Telegram (bot, user, grup, topik di config.yaml), model AI, zona waktu, .env")
  ADOPT_KEEP+=("Hermes Agent $(hm --version 2>/dev/null | head -1 | sed 's/^Hermes Agent //'): tidak di-update")

  # Kantor 3D
  if [[ $KA_WITH_RUANG == yes ]] && ! systemctl cat "$KA_RUANG_UNIT" >/dev/null 2>&1; then
    o=$(port_owner "$KA_RUANG_PORT")
    if [[ -n $o ]] && ! ours_nginx_port "$KA_RUANG_PORT"; then
      KA_WITH_RUANG=external
      ADOPT_KEEP+=("Kantor 3D yang sudah ada di port $KA_RUANG_PORT ($o): hanya ditautkan dari portal & panel")
    else
      ADOPT_ADD+=("Kantor 3D baru (Ruang) di port $KA_RUANG_PORT")
    fi
  fi
  # Panel Hermes
  if [[ $KA_WITH_DASHBOARD == yes ]] && ! systemctl cat "$KA_DASH_UNIT" >/dev/null 2>&1; then
    o=$(pgrep -af 'hermes[^ ]* dashboard|hermes_cli.main dashboard' 2>/dev/null | grep -v pgrep | head -1)
    if [[ -n $o ]]; then
      KA_WITH_DASHBOARD=external
      ADOPT_KEEP+=("Panel Hermes yang sudah berjalan (pid ${o%% *}): tidak diganti; tema & plugin GNC ditambahkan")
    else
      if port_busy "$KA_DASH_PORT"; then p=$(pick_free_port "$KA_DASH_PORT"); ADOPT_WARN+=("Port $KA_DASH_PORT dipakai $(port_owner "$KA_DASH_PORT"); Panel Hermes memakai port $p"); KA_DASH_PORT=$p; fi
      ADOPT_ADD+=("Panel Hermes (service $KA_DASH_UNIT) di port $KA_DASH_PORT, $([[ $KA_ACCESS_MODE == lan ]] && echo LAN || echo "127.0.0.1")")
    fi
  fi
  ka_on "$KA_WITH_DASHBOARD" && ADOPT_ADD+=("Tema 'gnc' & plugin 'gnc-kantor' di ~/.hermes; config.yaml admin: dashboard.theme=gnc, plugins.enabled += gnc-kantor")
  # Portal
  if [[ $KA_WITH_PORTAL == yes ]]; then
    if port_busy "$KA_PORTAL_PORT" && ! ours_nginx_port "$KA_PORTAL_PORT"; then
      p=$(pick_free_port "$KA_PORTAL_PORT"); ADOPT_WARN+=("Port $KA_PORTAL_PORT dipakai $(port_owner "$KA_PORTAL_PORT"); portal memakai port $p"); KA_PORTAL_PORT=$p
    fi
    ADOPT_ADD+=("Portal kantor (nginx) di port $KA_PORTAL_PORT")
    command -v nginx >/dev/null 2>&1 || ADOPT_ADD+=("Paket nginx (baru; situs bawaan port 80 dinonaktifkan)")
  fi
  # Pengawas
  if [[ $KA_WITH_PENGAWAS == yes ]]; then
    other=$(systemctl list-units --all --plain --no-legend 2>/dev/null | awk '{print $1}' | grep -iE 'pengawas|watchdog' | grep -v "^$KA_PENGAWAS_UNIT" | paste -sd, -)
    [[ -n $other ]] && ADOPT_KEEP+=("Watchdog yang sudah ada: $other")
    ADOPT_ADD+=("Pengawas GNC Kantor AI mode '$KA_PENGAWAS_MODE'$([[ $KA_PENGAWAS_MODE == status ]] && echo ': hanya menulis status untuk portal/panel, tanpa restart & notifikasi')")
  fi
  ADOPT_ADD+=("Menu kantorai, /opt/kantorai, /etc/kantorai, paket pendukung (whiptail, jq, ...)")
  return 0
}

adopt_plan_text() {
  local x
  printf 'RENCANA PERUBAHAN (mode adopsi)\n\n'
  printf 'Tidak disentuh:\n'; for x in "${ADOPT_KEEP[@]}"; do printf '  = %s\n' "$x"; done
  printf '\nDitambahkan:\n'; for x in "${ADOPT_ADD[@]}"; do printf '  + %s\n' "$x"; done
  if ((${#ADOPT_WARN[@]})); then printf '\nPerhatian:\n'; for x in "${ADOPT_WARN[@]}"; do printf '  ! %s\n' "$x"; done; fi
  printf '\nAkses web: %s\n' "$([[ $KA_ACCESS_MODE == lan ]] && echo "LAN (login $KA_WEB_USER)" || echo "lokal (127.0.0.1, lewat SSH tunnel)")"
  printf 'Batalkan kapan saja: kantorai uninstall (jawab N untuk Hermes & Kantor 3D)\n'
}

adopt_main() {
  hermes_ok || die "Hermes Agent belum terpasang. Mode --adopt hanya untuk server yang sudah menjalankan Hermes; pakai instalasi biasa."
  # Bawaan mode adopsi (bisa diubah lewat --config / environment)
  : "${KA_PENGAWAS_MODE:=status}"
  : "${KA_MODEL_MODE:=skip}"
  if [[ -r $KA_CONF ]]; then ka_load_conf; else ka_defaults; fi
  KA_TG_ADMIN_TOKEN=""; KA_TG_USERS=""; KA_MODEL_MODE=skip
  [[ $KA_ACCESS_MODE == lan && -z $KA_WEB_PASS && ! -s $KA_HTPASSWD ]] && KA_WEB_PASS=$(gen_password 18)
  adopt_detect
  printf '\n'; adopt_plan_text; printf '\n'
  ((CHECK)) && { echo "(--check: tidak ada yang diubah)"; return 0; }
  if ((! ASSUME_YES)); then
    if [[ -t 0 ]]; then
      local a; read -r -p "Terapkan rencana di atas? [y/N] " a; [[ $a =~ ^[YyJj] ]] || { echo "Batal, tidak ada yang diubah."; return 0; }
    else
      die "Tidak ada terminal untuk konfirmasi. Tambahkan --yes setelah memeriksa rencana dengan --check."
    fi
  fi
  check_internet
  install_prereqs
  do_install
  conf_set KA_ADOPTED yes
  final_report
}

ensure_whiptail() {
  command -v whiptail >/dev/null 2>&1 && return 0
  apt-get update >>"$KA_LOG" 2>&1 && apt-get install -y whiptail >>"$KA_LOG" 2>&1
}

# Semua logika ada di dalam fungsi dan main dipanggil di baris terakhir,
# supaya aman dijalankan via "wget ... | bash".
main "$@"; exit $?
