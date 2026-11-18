#!/usr/bin/env bash
# ============================================================================
#  pengawas.sh — Pengawas GNC Kantor AI (watchdog non-AI)
#  Galura Nexa Core — Technology Infrastructure
# ============================================================================
#  pengawas.sh periksa [--diam]   cek layanan, pulihkan, tulis status.json  (timer 2 menit)
#  pengawas.sh harian             laporan harian ke Telegram + backup otomatis (timer 07:05)
#  pengawas.sh uji                kirim pesan uji ke Telegram
#  pengawas.sh status             tampilkan status terakhir (JSON)
#
#  Notifikasi dikirim lewat bot admin (TELEGRAM_BOT_TOKEN di ~/.hermes/.env)
#  ke grup kantor (topik Pengawas) atau ke user admin pertama.
#  Pengawas tidak pernah memakai AI dan tidak mengubah konfigurasi.
# ============================================================================

set -uo pipefail

KA_LIBDIR=${KA_LIBDIR:-/usr/local/lib/kantorai}
# shellcheck source=common.sh
. "${KA_COMMON:-$KA_LIBDIR/common.sh}"

STATE_DIR=$KA_VAR/pengawas
STATUS_JSON=$KA_WWW/status.json
MAX_RESTART_PER_HOUR=${KA_MAX_RESTART_PER_HOUR:-3}
DISK_WARN=${KA_DISK_WARN:-90}
MEM_WARN=${KA_MEM_WARN:-92}
QUIET=0
MODE=$(conf_get KA_PENGAWAS_MODE penuh)   # penuh | status (server dengan watchdog lain: hanya tulis status.json)
[[ $MODE == status ]] && QUIET=1

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/.lock"
flock -n 9 || exit 0   # satu Pengawas saja dalam satu waktu

now() { date +%s; }
st_get() { cat "$STATE_DIR/$1" 2>/dev/null || true; }
st_set() { printf '%s' "$2" >"$STATE_DIR/$1"; }

# ---------------------------------------------------------------------------
# Notifikasi
# ---------------------------------------------------------------------------
notify_target() { # -> "TOKEN<TAB>CHAT<TAB>THREAD"
  local envf tok chat thread
  envf=$(profile_env default)
  tok=$(envget "$envf" TELEGRAM_BOT_TOKEN)
  [[ -n $tok ]] || return 1
  chat=$(conf_get KA_TG_GROUP_ID)
  thread=$(conf_get KA_PENGAWAS_THREAD)
  if [[ -z $chat ]]; then
    chat=$(envget "$envf" TELEGRAM_ALLOWED_USERS); chat=${chat%%,*}; thread=""
  fi
  [[ -n $chat ]] || return 1
  printf '%s\t%s\t%s' "$tok" "$chat" "$thread"
}

notify() { # notify "teks"
  local t tok chat thread office
  ((QUIET)) && { logf "pengawas(diam): $1"; return 0; }
  t=$(notify_target) || { logf "pengawas: notifikasi dilewati (bot admin/chat belum diatur): $1"; return 0; }
  IFS=$'\t' read -r tok chat thread <<<"$t"
  office=$(conf_get KA_OFFICE_NAME "Kantor AI")
  if ! tg_send "$tok" "$chat" "🛡️ Pengawas · $office
$1" "$thread"; then
    # topik mungkin sudah dihapus: coba tanpa topik
    [[ -n $thread ]] && tg_send "$tok" "$chat" "🛡️ Pengawas · $office
$1" || logf "pengawas: gagal kirim Telegram"
  fi
  logf "pengawas: $1"
}

# ---------------------------------------------------------------------------
# Daftar layanan yang diawasi
# ---------------------------------------------------------------------------
watched_units() {
  printf '%s|Gateway Hermes (bot Telegram)\n' "$KA_GATEWAY_UNIT"
  [[ $(conf_get KA_WITH_DASHBOARD yes) == yes ]] && printf '%s|Panel Hermes\n' "$KA_DASH_UNIT"
  [[ $(conf_get KA_WITH_RUANG yes) == yes ]] && printf '%s|Kantor 3D\n' "$KA_RUANG_UNIT"
  if [[ $(conf_get KA_WITH_PORTAL yes) == yes || $(conf_get KA_WITH_RUANG yes) == yes ]]; then printf 'nginx|Server web (nginx)\n'; fi
  [[ $(conf_get KA_WITH_CLOUDFLARED no) == yes ]] && printf 'cloudflared|Cloudflare Tunnel\n'
  return 0
}

restart_allowed() { # maksimal N restart per jam per layanan
  local u=$1 f="restarts.$1" list=() t n cutoff
  cutoff=$(( $(now) - 3600 ))
  for t in $(st_get "$f"); do ((t > cutoff)) && list+=("$t"); done
  n=${#list[@]}
  ((n < MAX_RESTART_PER_HOUR)) || return 1
  list+=("$(now)"); st_set "$f" "${list[*]}"
  return 0
}

check_units() {
  local u label state prev
  SERVICES_JSON="[]"
  while IFS='|' read -r u label; do
    [[ -n $u ]] || continue
    systemctl cat "$u" >/dev/null 2>&1 || continue   # belum terpasang
    state=$(svc_state "$u")
    prev=$(st_get "state.$u")
    if [[ $MODE == status ]]; then
      :   # mode status: hanya mencatat, tidak me-restart apa pun
    elif [[ $state != active ]]; then
      if restart_allowed "$u"; then
        logf "pengawas: $u $state -> restart"
        if [[ $u == "$KA_GATEWAY_UNIT" ]]; then gateway_restart; else systemctl restart "$u" >>"$KA_LOG" 2>&1; fi
        sleep 5
        state=$(svc_state "$u")
        if [[ $state == active && $prev == down ]]; then
          notify "✅ $label kembali normal (dipulihkan otomatis)."
        elif [[ $state == active ]]; then
          notify "⚠️ $label sempat mati, sudah dipulihkan otomatis."
        elif [[ $prev != down ]]; then
          notify "🔴 $label MATI dan gagal dipulihkan.
Periksa di server: kantorai logs $( [[ $u == "$KA_GATEWAY_UNIT" ]] && echo gateway || echo "${u#kantorai-}")"
        fi
      elif [[ $prev != down ]]; then
        notify "🔴 $label mati terus (sudah $MAX_RESTART_PER_HOUR kali di-restart dalam 1 jam). Pemulihan otomatis dihentikan sementara."
      fi
    elif [[ $prev == down ]]; then
      notify "✅ $label kembali normal."
    fi
    st_set "state.$u" "$([[ $state == active ]] && echo up || echo down)"
    SERVICES_JSON=$(jq -c --arg u "$u" --arg l "$label" --arg s "$state" '. + [{unit:$u, label:$l, state:$s}]' <<<"$SERVICES_JSON")
  done < <(watched_units)
}

check_resources() {
  local disk mem_total mem_avail mem_used last
  disk=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
  mem_total=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
  mem_avail=$(awk '/^MemAvailable/{print $2}' /proc/meminfo)
  mem_used=$(( (mem_total - mem_avail) * 100 / mem_total ))
  DISK_PCT=$disk; MEM_PCT=$mem_used
  if ((disk >= DISK_WARN)); then
    last=$(st_get alert.disk)
    if (( $(now) - ${last:-0} > 21600 )); then
      notify "💾 Disk hampir penuh: ${disk}% terpakai. Hapus backup lama (kantorai backup) atau perbesar disk."
      st_set alert.disk "$(now)"
    fi
  fi
  if ((mem_used >= MEM_WARN)); then
    last=$(st_get alert.mem)
    if (( $(now) - ${last:-0} > 21600 )); then
      notify "🧠 RAM hampir habis: ${mem_used}% terpakai. Kurangi karyawan aktif atau tambah RAM."
      st_set alert.mem "$(now)"
    fi
  fi
}

profiles_json() {
  local p arr="[]" envf has desc model
  for p in default $(list_profiles); do
    envf=$(profile_env "$p")
    has=false; [[ -n $(envget "$envf" TELEGRAM_BOT_TOKEN) ]] && has=true
    desc=$(profile_desc "$p"); model=$(profile_model "$p")
    [[ $p == default ]] && desc=${desc:-Asisten utama & admin kantor}
    arr=$(jq -c --arg n "$p" --arg d "$desc" --arg m "$model" --argjson b "$has" \
          '. + [{name:$n, description:$d, model:$m, telegram:$b}]' <<<"$arr")
  done
  printf '%s' "$arr"
}

write_status() {
  local tmp up load
  up=$(awk '{print int($1)}' /proc/uptime)
  load=$(awk '{print $1}' /proc/loadavg)
  mkdir -p "$(dirname "$STATUS_JSON")"
  tmp=$(mktemp "$STATUS_JSON.XXXX")
  jq -n --arg host "$(hostname)" --arg ver "$KA_VERSION" --arg office "$(conf_get KA_OFFICE_NAME "Kantor AI")" \
     --argjson services "${SERVICES_JSON:-[]}" --argjson profiles "$(profiles_json)" \
     --argjson disk "${DISK_PCT:-0}" --argjson mem "${MEM_PCT:-0}" --argjson up "$up" --arg load "$load" \
     --arg at "$(date -Iseconds)" \
     '{generated_at:$at, office:$office, hostname:$host, version:$ver, uptime_s:$up, load:$load,
       disk_pct:$disk, mem_pct:$mem, services:$services, crew:$profiles}' >"$tmp" \
    && chmod 644 "$tmp" && mv -f "$tmp" "$STATUS_JSON"
  cp -f "$STATUS_JSON" "$KA_VAR/status.json" 2>/dev/null || true
}

do_periksa() {
  [[ ${1:-} == --diam ]] && QUIET=1
  check_units
  check_resources
  write_status
}

do_backup() {
  local keep out
  keep=$(conf_get KA_BACKUP_KEEP 7)
  mkdir -p "$KA_BACKUP_DIR"; chmod 700 "$KA_BACKUP_DIR"
  out="$KA_BACKUP_DIR/hermes-backup-$(date +%Y%m%d-%H%M%S).zip"
  if hm backup -o "$out" -k "$keep" >>"$KA_LOG" 2>&1; then
    chmod 600 "$out"
    # simpan juga pengaturan kantorai
    tar -czf "${out%.zip}-kantorai-etc.tgz" -C / "${KA_ETC#/}" 2>/dev/null && chmod 600 "${out%.zip}-kantorai-etc.tgz"
    find "$KA_BACKUP_DIR" -name 'hermes-backup-*-kantorai-etc.tgz' -printf '%T@ %p\n' | sort -rn | tail -n +$((keep + 1)) | cut -d' ' -f2- | xargs -r rm -f
    printf '%s' "$out"; return 0
  fi
  return 1
}

do_harian() {
  local crew="" p desc bk="" svc
  do_periksa
  for p in $(list_profiles); do
    desc=$(profile_desc "$p"); crew+="
  • $p${desc:+ — $desc}"
  done
  svc=$(jq -r '.services[] | "  • \(.label): \(if .state == "active" then "normal" else .state end)"' "$STATUS_JSON" 2>/dev/null)
  if [[ $MODE == penuh && $(conf_get KA_AUTO_BACKUP yes) == yes ]]; then
    if bk=$(do_backup); then bk="✅ Backup harian: $(basename "$bk") ($(du -h "$bk" | cut -f1))"
    else bk="⚠️ Backup harian GAGAL (cek kantorai logs installer)"; fi
  fi
  notify "📋 Laporan harian $(date '+%A, %d %B %Y')
Layanan:
${svc:-  (tidak ada data)}
Disk ${DISK_PCT}% · RAM ${MEM_PCT}% · uptime $(( $(awk '{print int($1)}' /proc/uptime) / 86400 )) hari
Karyawan AI:${crew:-
  (belum ada karyawan)}
${bk}"
}

case ${1:-periksa} in
  periksa) do_periksa "${2:-}" ;;
  harian) do_harian ;;
  backup) do_backup && echo ;;
  uji) QUIET=0; t=$(notify_target) || { echo "Bot admin atau chat tujuan belum diatur (kantorai → Telegram)." >&2; exit 1; }
       IFS=$'\t' read -r tok chat thread <<<"$t"
       tg_send "$tok" "$chat" "🛡️ Pengawas · $(conf_get KA_OFFICE_NAME "Kantor AI")
✅ Uji notifikasi berhasil. Pengawas akan melapor ke sini." "$thread" && echo "Terkirim." || { echo "Gagal mengirim (cek token/ID chat, dan bot sudah ada di grup)." >&2; exit 1; } ;;
  status) cat "$STATUS_JSON" 2>/dev/null || echo '{}' ;;
  *) echo "Pemakaian: pengawas.sh periksa [--diam] | harian | backup | uji | status" >&2; exit 2 ;;
esac
