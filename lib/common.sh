#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ============================================================================
#  common.sh — fungsi bersama installer, menu kantorai, dan Pengawas
#  GNC Kantor AI · Galura Nexa Core — Technology Infrastructure
# ============================================================================
#  File ini di-source (bukan dijalankan). Semua path bisa di-override lewat
#  environment, terutama untuk pengujian (lihat uji/).
# ============================================================================

KA_VERSION="1.2.0"
: "${KA_REPO:=ferdiptgnc/kantoraignc}"
: "${KA_BRANCH:=main}"
: "${KA_HOME:=/opt/kantorai}"                 # salinan repo + aset
: "${KA_ETC:=/etc/kantorai}"
: "${KA_CONF:=$KA_ETC/kantorai.conf}"         # pengaturan (tanpa rahasia)
: "${KA_INFO:=$KA_ETC/INSTALL-INFO.txt}"      # ringkasan instalasi (chmod 600)
: "${KA_HTPASSWD:=$KA_ETC/web.htpasswd}"
: "${KA_VAR:=/var/lib/kantorai}"
: "${KA_WWW:=/var/www/kantorai}"
: "${KA_BACKUP_DIR:=/var/backups/kantorai}"
: "${KA_LOG:=/var/log/kantorai.log}"
: "${KA_LIBDIR:=/usr/local/lib/kantorai}"
: "${KA_BINDIR:=/usr/local/bin}"
: "${KA_SYSTEMD_DIR:=/etc/systemd/system}"
: "${KA_NGINX_CONF:=/etc/nginx/conf.d/kantorai.conf}"
: "${KA_PROFILE_D:=/etc/profile.d}"
: "${KA_ROOT_HOME:=/root}"
: "${HERMES_HOME:=$KA_ROOT_HOME/.hermes}"
: "${HERMES_BIN:=$KA_ROOT_HOME/.local/bin/hermes}"
: "${KA_RUANG_CMD:=$KA_ROOT_HOME/.local/bin/ruang}"
: "${KA_TG_API:=https://api.telegram.org}"
: "${KA_HERMES_INSTALL_URL:=https://hermes-agent.nousresearch.com/install.sh}"
: "${KA_RUANG_INSTALL_URL:=https://raw.githubusercontent.com/yugienugraha/ruang/main/install.sh}"

KA_PLUGIN_NAME="gnc-kantor"
KA_THEME_NAME="gnc"
KA_GATEWAY_UNIT="hermes-gateway"
KA_DASH_UNIT="kantorai-dashboard"
KA_RUANG_UNIT="kantorai-ruang"
KA_PENGAWAS_UNIT="kantorai-pengawas"
KA_RESERVED_NAMES=" default hermes kantorai root admin all gateway dashboard ruang pengawas "

export PATH="$KA_ROOT_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"

# ---------------------------------------------------------------------------
# Locale: Debian/Ubuntu baru sering memakai POSIX, sehingga whiptail menampilkan
# karakter UTF-8 (• — ·) sebagai <80>. Pakai C.UTF-8 bila ada; kalau tidak ada,
# teks whiptail diubah ke ASCII (KA_ASCII=1 juga bisa dipaksa dari luar).
# ---------------------------------------------------------------------------
ka_setup_locale() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) return 0 ;; esac
  if locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$'; then
    export LANG=C.UTF-8 LC_ALL=C.UTF-8
  else
    KA_ASCII=1
  fi
}
ka_setup_locale
: "${KA_ASCII:=0}"

ascii_text() { # ganti simbol UTF-8 dengan padanan ASCII
  # shellcheck disable=SC1111
  sed -e 's/•/*/g; s/—/-/g; s/–/-/g; s/·/|/g; s/✓/OK/g; s/✗/X/g; s/→/->/g; s/←/<-/g; s/…/.../g' \
      -e "s/[’‘]/'/g; s/[“”]/\"/g" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null
}
# Semua pemanggilan whiptail lewat fungsi ini (mode ASCII bila perlu).
whiptail() {
  if [[ $KA_ASCII == 1 ]]; then
    local a _wt_args=()
    for a in "$@"; do _wt_args+=("$(printf '%s' "$a" | ascii_text)"); done
    command whiptail "${_wt_args[@]}"
  else
    command whiptail "$@"
  fi
}

# ---------------------------------------------------------------------------
# Tampilan
# ---------------------------------------------------------------------------
TUI=${TUI:-0}
# whiptail menggambar ke terminal langsung, supaya tetap tampil walau dipanggil di dalam $(...)
KA_TTY=/dev/tty; [[ -w /dev/tty ]] || KA_TTY=/dev/stderr
W=78
BT=${BT:-"GNC Kantor AI v${KA_VERSION}  |  Galura Nexa Core"}

if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'; C_CYN=$'\e[36m'
  C_BLU=$'\e[1;38;5;33m'; C_BRZ=$'\e[1;38;5;137m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_CYN=""; C_BLU=""; C_BRZ=""; C_DIM=""; C_RST=""
fi

logf()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$KA_LOG" 2>/dev/null || true; }
say()   { printf '%s==>%s %s\n' "$C_CYN" "$C_RST" "$*"; logf "$*"; }
okp()   { printf '%s[ OK ]%s %s\n' "$C_GRN" "$C_RST" "$*"; logf "OK: $*"; }
warnp() { printf '%s[WARN]%s %s\n' "$C_YLW" "$C_RST" "$*" >&2; logf "WARN: $*"; }
errp()  { printf '%s[GAGAL]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; logf "GAGAL: $*"; }
die()   { errp "$*"; exit 1; }

show_banner() {
  local b=$C_BLU r=$C_RST z=$C_BRZ
  printf '\n'
  printf '   %s ██████   ███    ██  ██████%s\n' "$b" "$r"
  printf '   %s██        ████   ██ ██     %s\n' "$b" "$r"
  printf '   %s██   ███  ██ ██  ██ ██     %s   %sK A N T O R   A I%s\n' "$b" "$r" "$b" "$r"
  printf '   %s██    ██  ██  ██ ██ ██     %s\n' "$b" "$r"
  printf '   %s ██████   ██   ████  ██████%s\n' "$b" "$r"
  printf '\n   %sT E C H N O L O G Y   I N F R A S T R U C T U R E%s\n' "$z" "$r"
  printf '   %sGalura Nexa Core · v%s%s\n\n' "$C_DIM" "$KA_VERSION" "$r"
}

trim() { local s=$1; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

ui_msg() {
  if ((TUI)); then whiptail --backtitle "$BT" --title "$1" --msgbox "$2" "${3:-14}" "$W" >"$KA_TTY"
  else printf '\n%s== %s ==%s\n%b\n' "$C_CYN" "$1" "$C_RST" "$2" >&2; fi
  return 0
}
ui_info() {
  if ((TUI)); then whiptail --backtitle "$BT" --title "Mohon tunggu" --infobox "$1" 8 "$W" >"$KA_TTY"
  else say "$1" >&2; fi
  logf "$1"
}
ui_yesno() { # ui_yesno "Judul" "Teks" [no]
  if ((TUI)); then
    local o=(); [[ ${3:-} == no ]] && o=(--defaultno)
    whiptail --backtitle "$BT" --title "$1" "${o[@]}" --yesno "$2" "${4:-14}" "$W" >"$KA_TTY"
  else
    local a d="Y/n"; [[ ${3:-} == no ]] && d="y/N"
    printf '\n%s\n%b\n' "$1" "$2" >&2
    read -r -p "Lanjutkan? [$d] " a || return 1
    a=${a:-$([[ ${3:-} == no ]] && echo n || echo y)}
    [[ $a =~ ^[YyJj] ]]
  fi
}
# ui_menu "Judul" "Teks" tag item [tag item ...]   -> tag terpilih di stdout
ui_menu() {
  local t=$1 x=$2; shift 2
  if ((TUI)); then
    whiptail --backtitle "$BT" --title "$t" --menu "$x" 24 "$W" 14 "$@" 3>&1 1>"$KA_TTY" 2>&3
  else
    local i tags=() a
    printf '\n%s== %s ==%s\n%b\n' "$C_CYN" "$t" "$C_RST" "$x" >&2
    while (($#)); do tags+=("$1"); printf '  %-4s %s\n' "$1" "$2" >&2; shift 2; done
    read -r -p "Pilih: " a || return 1
    for i in "${tags[@]}"; do [[ $i == "$a" ]] && { printf '%s' "$a"; return 0; }; done
    return 1
  fi
}
# ui_checklist "Judul" "Teks" tag item on/off ...  -> tag terpilih (dipisah spasi)
ui_checklist() {
  local t=$1 x=$2; shift 2
  if ((TUI)); then
    whiptail --backtitle "$BT" --title "$t" --separate-output --checklist "$x" 22 "$W" 10 "$@" 3>&1 1>"$KA_TTY" 2>&3 | tr '\n' ' '
  else
    local out="" a
    printf '\n%s== %s ==%s\n%b\n' "$C_CYN" "$t" "$C_RST" "$x" >&2
    while (($#)); do
      read -r -p "  $2 [$([[ $3 == ON ]] && echo Y/n || echo y/N)] " a || return 1
      a=${a:-$([[ $3 == ON ]] && echo y || echo n)}
      [[ $a =~ ^[YyJj] ]] && out+="$1 "
      shift 3
    done
    printf '%s' "$out"
  fi
}
# ui_input VAR "Judul" "Teks" "default" [validator] ["pesan error"]
ui_input() {
  local __v=$1 title=$2 text=$3 def=$4 val=${5:-} err=${6:-"Input tidak valid, silakan ulangi."} out
  while true; do
    if ((TUI)); then
      out=$(whiptail --backtitle "$BT" --title "$title" --inputbox "$text" 16 "$W" "$def" 3>&1 1>"$KA_TTY" 2>&3) || return 1
    else
      printf '\n%s\n%b\n' "$title" "$text" >&2
      read -r -p "[${def}] > " out || return 1
      out=${out:-$def}
    fi
    out=$(trim "$out")
    if [[ -z $val ]] || "$val" "$out"; then printf -v "$__v" '%s' "$out"; return 0; fi
    ui_msg "Input tidak valid" "$err"; def=$out
  done
}
# ui_secret VAR "Judul" "Teks"   -> input tersembunyi, sekali (untuk token)
ui_secret() {
  local __v=$1 title=$2 text=$3 out
  if ((TUI)); then
    out=$(whiptail --backtitle "$BT" --title "$title" --passwordbox "$text" 12 "$W" 3>&1 1>"$KA_TTY" 2>&3) || return 1
  else
    printf '\n%s\n%b\n' "$title" "$text" >&2
    read -r -s -p "> " out || return 1; printf '\n' >&2
  fi
  printf -v "$__v" '%s' "$(trim "$out")"
}
# ui_pass VAR "Judul" minlen   -> password dua kali
ui_pass() {
  local __v=$1 title=$2 min=${3:-10} p1 p2
  while true; do
    ui_secret p1 "$title" "Masukkan password (minimal $min karakter, tanpa spasi):" || return 1
    if ((${#p1} < min)) || [[ $p1 == *[[:space:]]* || $p1 == *:* ]]; then
      ui_msg "Password tidak valid" "Password minimal $min karakter, tanpa spasi dan tanpa titik dua (:)."; continue
    fi
    ui_secret p2 "$title" "Ulangi password:" || return 1
    [[ $p1 == "$p2" ]] || { ui_msg "Password tidak sama" "Kedua password tidak sama, silakan ulangi."; continue; }
    printf -v "$__v" '%s' "$p1"; return 0
  done
}
# ui_text "Judul" file   -> tampilkan isi file
ui_text() {
  if ((TUI)); then
    if [[ $KA_ASCII == 1 ]]; then
      local tmp; tmp=$(mktemp); ascii_text <"$2" >"$tmp"
      whiptail --backtitle "$BT" --title "$1" --scrolltext --textbox "$tmp" 24 "$W" >"$KA_TTY"; rm -f "$tmp"
    else
      whiptail --backtitle "$BT" --title "$1" --scrolltext --textbox "$2" 24 "$W" >"$KA_TTY"
    fi
  else cat "$2"; fi
}
# ui_run "Judul" perintah...  -> jalankan, tampilkan output
ui_run() {
  local t=$1 tmp rc; shift; tmp=$(mktemp)
  ((TUI)) && whiptail --backtitle "$BT" --title "Mohon tunggu" --infobox "Menjalankan: $t ..." 8 "$W" >"$KA_TTY"
  "$@" >"$tmp" 2>&1; rc=$?
  sed -i 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$tmp"
  redact_stream <"$tmp" >"$tmp.r" && mv "$tmp.r" "$tmp"
  [[ -s $tmp ]] || echo "(tidak ada output)" >"$tmp"
  ((rc == 0)) || printf '\n[kode keluar: %s]\n' "$rc" >>"$tmp"
  ui_text "$t" "$tmp"
  rm -f "$tmp"; return $rc
}
# Jalankan program interaktif (hermes model, nano, chat) di luar whiptail.
run_tty() {
  ((TUI)) && clear
  "$@"; local rc=$?
  if ((TUI)); then printf '\n%sTekan Enter untuk kembali ke menu...%s' "$C_DIM" "$C_RST"; read -r _ || true; fi
  return $rc
}

# Sensor token/kunci dari output yang ditampilkan.
redact_stream() {
  sed -E 's#bot[0-9]{6,}:[A-Za-z0-9_-]{20,}#bot***#g;
          s#[0-9]{6,}:[A-Za-z0-9_-]{30,}#***:***#g;
          s#(sk-[A-Za-z0-9_-]{4})[A-Za-z0-9_-]{16,}#\1***#g;
          s#((API_KEY|TOKEN|SECRET|PASSWORD)[A-Z_]*=).+#\1***#g'
}

# ---------------------------------------------------------------------------
# Progress bar untuk proses panjang (installer)
#   pr_begin
#   pr_task DARI% SAMPAI% PERKIRAAN_DETIK "Status" perintah...   (output -> $KA_LOG)
#   pr_end 0|1 "Pesan akhir"
# Di terminal: bar, persen, waktu berjalan, spinner, dan baris terakhir log.
# Tanpa terminal (unattended ke file): satu baris per tahap + kabar tiap 30 detik.
# ---------------------------------------------------------------------------
PR_TTY=0; [[ -t 1 && ${KA_NO_PROGRESS:-0} != 1 ]] && PR_TTY=1
PR_DRAWN=0; PR_T0=0; PR_PCT=0; PR_STATUS=""; PR_LOG_OFF=0
fmt_dur() { printf '%02d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }
pr_cols() { local c; c=$(tput cols 2>/dev/null || echo 80); ((c < 50)) && c=50; ((c > 110)) && c=110; printf '%s' "$c"; }
pr_fit() { local s=$1 n=$2; ((${#s} > n)) && s="${s:0:$((n - 1))}…"; printf '%s' "$s"; }
pr_bar() { # pr_bar PERSEN LEBAR
  local f=$(( $1 * $2 / 100 )) e full empty
  e=$(( $2 - f ))
  printf -v full '%*s' "$f" ''; printf -v empty '%*s' "$e" ''
  if [[ $KA_ASCII == 1 ]]; then printf '%s%s' "${full// /#}" "${empty// /-}"
  else printf '%s%s' "${full// /█}" "${empty// /░}"; fi
}
pr_detail() { # baris terakhir yang berarti dari log (tanpa warna, token disensor)
  tail -c "+$(( PR_LOG_OFF + 1 ))" "$KA_LOG" 2>/dev/null | tail -n 40 | tr '\r' '\n' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
    | grep -v -E '^[[:space:]]*$|^\[[0-9-]{10} [0-9:]{8}\] (==|OK:|WARN:)' | tail -n 1 | redact_stream \
    | sed 's/^[[:space:]]*//'
}
pr_draw() { # pr_draw PERSEN "status" "detail" [ikon]
  local p=$1 st=$2 det=$3 icon=${4:-} cols bw el color=$C_BLU
  cols=$(pr_cols); bw=$(( cols - 30 )); ((bw > 46)) && bw=46
  el=$(( SECONDS - PR_T0 ))
  [[ $icon == ok ]] && { color=$C_GRN; icon="✓"; }
  [[ $icon == fail ]] && { color=$C_RED; icon="✗"; }
  ((PR_DRAWN)) && printf '\e[3F'
  printf '\e[2K  %s%s%s %3d%%  %s%s%s  %s\n' "$color" "$(pr_bar "$p" "$bw")" "$C_RST" "$p" "$C_DIM" "$(fmt_dur "$el")" "$C_RST" "$icon"
  printf '\e[2K  %s\n' "$(pr_fit "$st" $(( cols - 4 )))"
  printf '\e[2K  %s› %s%s\n' "$C_DIM" "$(pr_fit "${det:-…}" $(( cols - 6 )))" "$C_RST"
  PR_DRAWN=1
}
pr_begin() {
  PR_DRAWN=0; PR_T0=$SECONDS; PR_PCT=0
  ((PR_TTY)) && printf '\e[?25l'   # sembunyikan kursor selama progress
  return 0
}
pr_task() { # pr_task DARI SAMPAI PERKIRAAN_DETIK "status" perintah...
  local from=$1 to=$2 expect=$3 st=$4 pid rc t0 t p frames='|/-\' i=0 last=0
  shift 4
  [[ $KA_ASCII == 1 ]] || frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  PR_STATUS=$st
  logf "== $st =="
  PR_LOG_OFF=$(stat -c %s "$KA_LOG" 2>/dev/null || echo 0)
  ( "$@" ) </dev/null >>"$KA_LOG" 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null; printf "\e[?25h\n"; exit 130' INT TERM
  t0=$SECONDS
  ((PR_TTY)) || printf '  ... %s\n' "$st"
  while kill -0 "$pid" 2>/dev/null; do
    t=$(( SECONDS - t0 ))
    # kurva mendekati batas atas tahap tanpa pernah melewatinya
    p=$(( from + (to - from) * t / (t + expect) ))
    ((p >= to)) && p=$(( to - 1 )); ((p < from)) && p=$from
    PR_PCT=$p
    if ((PR_TTY)); then
      pr_draw "$p" "$st" "$(pr_detail)" "${frames:$(( i % ${#frames} )):1}"
      i=$(( i + 1 )); sleep 0.2
    else
      if (( t - last >= 30 )); then printf '      masih berjalan %s · %s\n' "$(fmt_dur "$t")" "$(pr_fit "$(pr_detail)" 70)"; last=$t; fi
      sleep 1
    fi
  done
  wait "$pid"; rc=$?
  trap - INT TERM
  ((rc == 0)) && PR_PCT=$to
  return $rc
}
pr_end() { # pr_end KODE "pesan"
  if ((PR_TTY)); then
    if (($1 == 0)); then pr_draw 100 "$2" "selesai dalam $(fmt_dur $(( SECONDS - PR_T0 )))" ok
    else pr_draw "$PR_PCT" "$2" "$(pr_detail)" fail; fi
    printf '\e[?25h'
  fi
  if ((PR_TTY)); then logf "$2"
  elif (($1 == 0)); then okp "$2"; else errp "$2"; fi
  PR_DRAWN=0
}

# ---------------------------------------------------------------------------
# Validasi
# ---------------------------------------------------------------------------
valid_port()      { [[ $1 =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
valid_username()  { [[ $1 =~ ^[A-Za-z0-9._-]{3,32}$ ]]; }
valid_profile()   { [[ $1 =~ ^[a-z][a-z0-9_-]{1,30}$ ]] && [[ $KA_RESERVED_NAMES != *" $1 "* ]]; }
valid_tz()        { [[ -n $1 && $1 != *..* && -f /usr/share/zoneinfo/$1 ]]; }
valid_nonempty()  { [[ -n $1 ]]; }
valid_office()    { [[ -n $1 && ${#1} -le 60 && $1 != *[\"\\\`\$\<\>]* ]]; }
valid_bot_token() { [[ $1 =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,50}$ ]]; }
valid_user_ids()  { [[ $1 =~ ^[0-9]{4,15}(,[0-9]{4,15})*$ ]]; }
valid_chat_id()   { [[ $1 =~ ^-100[0-9]{6,15}$ ]]; }
valid_thread_id() { [[ $1 =~ ^[0-9]{1,10}$ ]]; }
valid_thread_list() { [[ $1 =~ ^[0-9]{1,10}(,[0-9]{1,10})*$ ]]; }
valid_cf_token()  { [[ $1 =~ ^[A-Za-z0-9_=+/.-]{40,}$ ]]; }
valid_logo()      { [[ -f $1 && $1 =~ \.(svg|png|jpg|jpeg|webp)$ ]] && (( $(stat -c %s "$1") <= 1048576 )); }

# ---------------------------------------------------------------------------
# File KEY=value (.env Hermes) — menjaga permission file asli
# ---------------------------------------------------------------------------
envget() { [[ -f $1 ]] && K="$2" awk 'index($0, ENVIRON["K"] "=") == 1 { v = substr($0, length(ENVIRON["K"]) + 2); gsub(/^["\x27]|["\x27]$/, "", v); print v; exit }' "$1"; return 0; }
envset() {
  local f=$1 tmp; tmp=$(mktemp)
  mkdir -p "$(dirname "$f")"
  [[ -f $f ]] || { (umask 077; : >"$f"); }
  K="$2" V="$3" awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
    index($0, k "=") == 1 { if (!d) { print k "=" v; d = 1 }; next } { print }
    END { if (!d) print k "=" v }' "$f" >"$tmp" && cat "$tmp" >"$f"
  rm -f "$tmp"; chmod 600 "$f" 2>/dev/null || true
}
envdel() {
  local f=$1 tmp; [[ -f $f ]] || return 0; tmp=$(mktemp)
  K="$2" awk 'index($0, ENVIRON["K"] "=") != 1' "$f" >"$tmp" && cat "$tmp" >"$f"
  rm -f "$tmp"
}

# File pengaturan kantorai (format shell: KEY='nilai'), aman di-source.
conf_get() { # conf_get KEY [default]
  local v
  v=$( [[ -r $KA_CONF ]] && K="$1" bash -c '. "$0" 2>/dev/null; printf "%s" "${!K-}"' "$KA_CONF")
  printf '%s' "${v:-${2:-}}"
}
conf_set() { # conf_set KEY nilai
  local f=$KA_CONF tmp q; mkdir -p "$(dirname "$f")"
  [[ -f $f ]] || { printf '# Pengaturan GNC Kantor AI (dibuat otomatis, boleh diedit lewat menu kantorai)\n' >"$f"; chmod 644 "$f"; }
  q=$(printf "%s" "$2" | sed "s/'/'\\\\''/g")
  tmp=$(mktemp)
  K="$1" L="$1='$q'" awk 'BEGIN { k = ENVIRON["K"]; l = ENVIRON["L"] }
    index($0, k "=") == 1 { if (!d) { print l; d = 1 }; next } { print }
    END { if (!d) print l }' "$f" >"$tmp" && cat "$tmp" >"$f"
  rm -f "$tmp"
}
info_set() { # info_set "Label" "nilai"
  mkdir -p "$(dirname "$KA_INFO")"
  [[ -f $KA_INFO ]] || { (umask 077; : >"$KA_INFO"); }
  local tmp; tmp=$(mktemp)
  P="$1" V="$2" awk 'index($0, ENVIRON["P"] ":") == 1 { print ENVIRON["P"] ": " ENVIRON["V"]; f = 1; next } { print }
    END { if (!f) print ENVIRON["P"] ": " ENVIRON["V"] }' "$KA_INFO" >"$tmp" && cat "$tmp" >"$KA_INFO"
  rm -f "$tmp"; chmod 600 "$KA_INFO"
}

gen_secret() { openssl rand -base64 "${1:-32}" | tr -d '\n'; }
gen_password() { LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom 2>/dev/null | head -c "${1:-16}"; }

# ---------------------------------------------------------------------------
# Hermes
# ---------------------------------------------------------------------------
hm() { HOME=$KA_ROOT_HOME HERMES_HOME=$HERMES_HOME "$HERMES_BIN" "$@"; }
hermes_ok() { [[ -x $HERMES_BIN ]]; }

profile_home() { if [[ $1 == default ]]; then printf '%s' "$HERMES_HOME"; else printf '%s/profiles/%s' "$HERMES_HOME" "$1"; fi; }
profile_env()  { printf '%s/.env' "$(profile_home "$1")"; }
profile_cfg()  { printf '%s/config.yaml' "$(profile_home "$1")"; }
profile_exists() { [[ $1 == default ]] || [[ -d $HERMES_HOME/profiles/$1 ]]; }
# Daftar karyawan (profil selain default), satu per baris.
list_profiles() {
  local d
  [[ -d $HERMES_HOME/profiles ]] || return 0
  for d in "$HERMES_HOME"/profiles/*/; do
    [[ -d $d ]] || continue
    d=${d%/}; d=${d##*/}
    [[ $d == .* ]] && continue
    printf '%s\n' "$d"
  done
}
profile_desc() {
  local f; f="$(profile_home "$1")/profile.yaml"
  [[ -f $f ]] || return 0
  awk -F': *' '$1 == "description" { sub(/^description: */, ""); gsub(/^["\x27]|["\x27]$/, ""); print; exit }' "$f"
}
profile_model() { # baris model default dari config.yaml (perkiraan, tanpa parser YAML)
  local f; f=$(profile_cfg "$1")
  [[ -f $f ]] || return 0
  awk '
    /^model:[[:space:]]*[^[:space:]#]/ { sub(/^model:[[:space:]]*/, ""); print; exit }
    /^model:/ { m = 1; next }
    m && /^[^[:space:]]/ { exit }
    m && /^[[:space:]]+(default|model):/ { sub(/^[[:space:]]+(default|model):[[:space:]]*/, ""); gsub(/["\x27]/, ""); print; exit }
  ' "$f"
}

gateway_restart() {
  if hm gateway restart --system -y >>"$KA_LOG" 2>&1; then return 0; fi
  systemctl restart "$KA_GATEWAY_UNIT" >>"$KA_LOG" 2>&1
}
svc_state() { systemctl is-active "$1" 2>/dev/null || true; }
svc_enabled_feature() { [[ $(conf_get "$1" yes) == yes ]]; }

local_ip() { local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}'); printf '%s' "${ip:-127.0.0.1}"; }
port_busy() { ss -Hltn "sport = :$1" 2>/dev/null | grep -q .; }

# ---------------------------------------------------------------------------
# Telegram Bot API (token tidak pernah ditulis ke log / layar)
# ---------------------------------------------------------------------------
tg_call() { # tg_call TOKEN METHOD [curl -d args...]
  local tok=$1 m=$2; shift 2
  curl -fsS -m 20 -K - "$@" <<<"url = \"$KA_TG_API/bot$tok/$m\"" 2>/dev/null
}
tg_bot_username() { # -> @username atau kosong
  local j; j=$(tg_call "$1" getMe) || return 1
  jq -er '.result.username // empty' <<<"$j" 2>/dev/null
}
tg_send() { # tg_send TOKEN CHAT_ID TEKS [THREAD_ID]
  local args=(--data-urlencode "chat_id=$2" --data-urlencode "text=$3" -d disable_web_page_preview=true)
  [[ -n ${4:-} ]] && args+=(-d "message_thread_id=$4")
  tg_call "$1" sendMessage "${args[@]}" >/dev/null
}
