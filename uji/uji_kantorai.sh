#!/usr/bin/env bash
# ============================================================================
#  Uji GNC Kantor AI di lingkungan tiruan (tanpa systemd, Hermes, atau internet)
#  Jalankan dari root repo:  bash uji/uji_kantorai.sh
#  Semua file uji ditulis di folder sementara; sistem asli tidak disentuh.
# ============================================================================
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d /tmp/kantorai-uji.XXXXXX)
PASS=0; FAIL=0; FAILS=()

export MOCKS=$REPO/uji/mocks MOCK_STATE=$T/state MOCK_LOG=$T/state/mock.log
export KA_ROOT_HOME=$T/root HERMES_HOME=$T/root/.hermes HERMES_BIN=$T/root/.local/bin/hermes KA_RUANG_CMD=$T/root/.local/bin/ruang
export KA_HOME=$T/opt/kantorai KA_ETC=$T/etc/kantorai KA_VAR=$T/var/lib/kantorai KA_WWW=$T/var/www/kantorai
export KA_BACKUP_DIR=$T/var/backups/kantorai KA_LOG=$T/var/log/kantorai.log KA_LIBDIR=$T/usr/local/lib/kantorai
export KA_BINDIR=$T/usr/local/bin KA_SYSTEMD_DIR=$T/etc/systemd/system KA_NGINX_CONF=$T/etc/nginx/conf.d/kantorai.conf
export KA_PROFILE_D=$T/etc/profile.d KA_HTPASSWD=$T/etc/kantorai/web.htpasswd KA_ALLOW_NO_SYSTEMD=1 KA_CONF=$T/etc/kantorai/kantorai.conf
export KA_INFO=$T/etc/kantorai/INSTALL-INFO.txt
mkdir -p "$MOCK_STATE" "$KA_ROOT_HOME/.local/bin" "$KA_PROFILE_D" "$(dirname "$KA_LOG")"
for m in "$MOCKS"/*; do [[ $(basename "$m") == hermes ]] || cp "$m" "$KA_ROOT_HOME/.local/bin/"; done
export PATH="$KA_ROOT_HOME/.local/bin:$PATH"

ADMIN_TOKEN="1234567890:AAH_admintoken_abcdefghijklmnopqrstu"
EMP_TOKEN="2234567890:AAH_karyawantoken_abcdefghijklmnopq"

ok()   { PASS=$((PASS + 1)); printf '  \e[32m✓\e[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILS+=("$1"); printf '  \e[31m✗ %s\e[0m\n' "$1"; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
has()  { grep -q -- "$2" "$1" 2>/dev/null; }
hasnt() { ! grep -q -- "$2" "$1" 2>/dev/null; }
section() { printf '\n\e[1;36m== %s ==\e[0m\n' "$1"; }
ka() { "$KA_BINDIR/kantorai" "$@"; }

# ---------------------------------------------------------------------------
section "1. Instalasi tanpa dialog (mode LAN, semua komponen)"
cat >"$T/klien.conf" <<EOF
KA_OFFICE_NAME="PT Uji Coba Sejahtera"
KA_ACCESS_MODE="lan"
KA_WEB_USER="admin"
KA_WEB_PASS="RahasiaWeb12345"
KA_TG_ADMIN_TOKEN="$ADMIN_TOKEN"
KA_TG_USERS="111111111,222222222"
KA_MODEL_MODE="config"
KA_MODEL_PROVIDER="openrouter"
KA_MODEL_NAME="anthropic/claude-sonnet-4.5"
KA_MODEL_KEY_VAR="OPENROUTER_API_KEY"
KA_MODEL_KEY="sk-or-v1-kunciujicoba1234567890abcdef"
EOF
bash "$REPO/install-kantorai.sh" --unattended --config "$T/klien.conf" --source "$REPO" >"$T/install.out" 2>&1
check "installer selesai dengan kode 0" test $? -eq 0
check "menu kantorai terpasang" test -x "$KA_BINDIR/kantorai"
check "library & pengawas terpasang" test -f "$KA_LIBDIR/common.sh" -a -x "$KA_LIBDIR/pengawas.sh"
check "salinan repo di KA_HOME" test -f "$KA_HOME/assets/templates/SOUL.md.tpl"
check "PATH profile.d dibuat" test -f "$KA_PROFILE_D/kantorai.sh"
check "pengaturan menyimpan nama kantor" has "$KA_CONF" "KA_OFFICE_NAME='PT Uji Coba Sejahtera'"
check "pengaturan tidak memuat password web" hasnt "$KA_CONF" "RahasiaWeb12345"
ENVF=$HERMES_HOME/.env
check ".env admin berisi token bot" has "$ENVF" "TELEGRAM_BOT_TOKEN=$ADMIN_TOKEN"
check ".env admin berisi user diizinkan" has "$ENVF" "TELEGRAM_ALLOWED_USERS=111111111,222222222"
check ".env admin home channel = user pertama" has "$ENVF" "TELEGRAM_HOME_CHANNEL=111111111"
check ".env admin berisi kunci model" has "$ENVF" "OPENROUTER_API_KEY=sk-or-v1-kunciujicoba"
check ".env admin berisi login dashboard" has "$ENVF" "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=RahasiaWeb12345"
check ".env admin punya secret sesi dashboard" grep -Eq '^HERMES_DASHBOARD_BASIC_AUTH_SECRET=.{30,}' "$ENVF"
check ".env admin chmod 600" test "$(stat -c %a "$ENVF")" = 600
check "model provider diatur lewat hermes config" has "$MOCK_LOG" "hermes config set model.provider openrouter"
check "gateway dipasang sebagai root system service" has "$MOCK_LOG" "gateway install --system --run-as-user root"
check "tema dashboard dipilih" has "$MOCK_LOG" "config set dashboard.theme gnc"
check "plugin dashboard diaktifkan" has "$MOCK_LOG" "plugins enable gnc-kantor"
check "tema GNC tersalin" test -f "$HERMES_HOME/dashboard-themes/gnc.yaml"
check "plugin GNC tersalin" test -f "$HERMES_HOME/plugins/gnc-kantor/dashboard/manifest.json"
DU=$KA_SYSTEMD_DIR/kantorai-dashboard.service
check "unit dashboard: bind LAN + port" has "$DU" "dashboard --no-open --host 0.0.0.0 --port 9119"
check "unit dashboard: EnvironmentFile .env" has "$DU" "EnvironmentFile=-$HERMES_HOME/.env"
check "unit dashboard: berhenti di exit 78" has "$DU" "RestartPreventExitStatus=78"
check "unit Kantor 3D di port internal" has "$KA_SYSTEMD_DIR/kantorai-ruang.service" "--port 3101"
check "timer Pengawas dibuat" test -f "$KA_SYSTEMD_DIR/kantorai-pengawas.timer" -a -f "$KA_SYSTEMD_DIR/kantorai-pengawas-harian.timer"
check "semua layanan aktif" bash -c "for u in hermes-gateway kantorai-dashboard kantorai-ruang nginx kantorai-pengawas.timer; do systemctl is-active \$u >/dev/null || exit 1; done"
check "nginx: portal di 0.0.0.0:8080" has "$KA_NGINX_CONF" "listen 0.0.0.0:8080;"
check "nginx: Kantor 3D di 0.0.0.0:3001 -> 3101" bash -c "grep -q 'listen 0.0.0.0:3001;' '$KA_NGINX_CONF' && grep -q 'proxy_pass http://127.0.0.1:3101;' '$KA_NGINX_CONF'"
check "nginx: login basic auth (mode LAN)" has "$KA_NGINX_CONF" "auth_basic_user_file $KA_HTPASSWD;"
check "nginx: branding disisipkan ke Ruang" has "$KA_NGINX_CONF" "sub_filter '</head>'"
check "nginx -t (nginx asli) lulus" nginx -t
HP=$(cut -d: -f2 "$KA_HTPASSWD"); SALT=$(cut -d'$' -f3 <<<"$HP")
check "htpasswd apr1 cocok dengan password" test "$(openssl passwd -apr1 -salt "$SALT" RahasiaWeb12345)" = "$HP"
check "portal-config.json valid & nama kantor" bash -c "jq -e '.office == \"PT Uji Coba Sejahtera\" and .dashboard.port == 9119 and .ruang.port == 3001' '$KA_WWW/portal/portal-config.json'"
check "konfigurasi branding Ruang disalin" test -f "$KA_WWW/ruang-brand/config.json" -a -f "$KA_WWW/ruang-brand/brand.js"
check "status.json ditulis Pengawas" bash -c "jq -e '(.services | length) >= 4 and (.crew[0].name == \"default\") and .crew[0].telegram == true' '$KA_WWW/status.json'"
check "INSTALL-INFO chmod 600 & berisi password" bash -c "[[ \$(stat -c %a '$KA_INFO') == 600 ]] && grep -q RahasiaWeb12345 '$KA_INFO'"
check "token admin tidak bocor ke log kantorai" hasnt "$KA_LOG" "$ADMIN_TOKEN"
check "token admin tidak muncul di argumen perintah" hasnt "$MOCK_LOG" "$ADMIN_TOKEN"
check "kunci model tidak muncul di argumen perintah" hasnt "$MOCK_LOG" "sk-or-v1-kunciujicoba"
check "output installer tidak memuat token" hasnt "$T/install.out" "$ADMIN_TOKEN"

# ---------------------------------------------------------------------------
section "2. Menu kantorai (CLI)"
ka status >"$T/status.out" 2>&1
check "status: menampilkan gateway aktif" grep -q "Gateway Hermes.*aktif" "$T/status.out"
check "status: menampilkan nama kantor" has "$T/status.out" "PT Uji Coba Sejahtera"
ka karyawan daftar >"$T/daftar.out" 2>&1
check "daftar karyawan memuat admin" grep -q "^  default .*bot ✓" "$T/daftar.out"
ka version | grep -q "GNC Kantor AI 1.0.0"; check "kantorai version" test $? -eq 0
ka perintah-ngawur >/dev/null 2>&1; check "perintah tidak dikenal ditolak (kode 2)" test $? -eq 2

section "3. Tambah karyawan (menu teks, KA_PLAIN=1)"
: >"$MOCK_LOG"
printf '%s\n' "sekretaris" "Sekretaris kantor" "Merangkum email masuk setiap pagi" "y" "$EMP_TOKEN" "n" \
  | KA_PLAIN=1 ka karyawan tambah >"$T/tambah.out" 2>&1
P=$HERMES_HOME/profiles/sekretaris
check "profil sekretaris dibuat" test -d "$P"
check "deskripsi jabatan dikirim ke hermes" has "$MOCK_LOG" "profile create sekretaris --description Sekretaris kantor"
check "skill bawaan aktif (tanpa --no-skills)" hasnt "$MOCK_LOG" "--no-skills"
check "SOUL.md berisi nama, jabatan, kantor, tugas" bash -c "grep -q '# sekretaris — Sekretaris kantor' '$P/SOUL.md' && grep -q 'PT Uji Coba Sejahtera' '$P/SOUL.md' && grep -q 'Merangkum email masuk' '$P/SOUL.md'"
check ".env karyawan berisi token bot" has "$P/.env" "TELEGRAM_BOT_TOKEN=$EMP_TOKEN"
check ".env karyawan menyalin user diizinkan" has "$P/.env" "TELEGRAM_ALLOWED_USERS=111111111,222222222"
check ".env karyawan tidak menyalin token admin" hasnt "$P/.env" "$ADMIN_TOKEN"
check "gateway di-restart setelah tambah" has "$MOCK_LOG" "gateway restart --system -y"
check "token karyawan tidak muncul di argumen perintah" hasnt "$MOCK_LOG" "$EMP_TOKEN"

printf '%s\n' "sales" "Admin penjualan" "Menyiapkan penawaran" "n" "$EMP_TOKEN" "" "n" \
  | KA_PLAIN=1 ka karyawan tambah >"$T/tambah2.out" 2>&1
check "token duplikat ditolak" grep -q "Token sudah dipakai" "$T/tambah2.out"
check "profil sales tetap dibuat tanpa bot" bash -c "test -d '$HERMES_HOME/profiles/sales' && ! grep -q TELEGRAM_BOT_TOKEN '$HERMES_HOME/profiles/sales/.env'"
check "pilihan tanpa skill diteruskan (--no-skills)" has "$MOCK_LOG" "profile create sales --description Admin penjualan --no-skills"
printf '%s\n' "default" "Sekretaris lain" "x" "y" "" "n" | KA_PLAIN=1 ka karyawan tambah >"$T/tambah3.out" 2>&1
check "nama sistem 'default' ditolak" grep -q "Nama tidak valid" "$T/tambah3.out"
printf '%s\n' "nano" | KA_PLAIN=1 ka karyawan tambah >"$T/tambah4.out" 2>&1
check "nama yang bentrok dengan perintah sistem ditolak" bash -c "grep -q 'Nama bentrok' '$T/tambah4.out' && test ! -d '$HERMES_HOME/profiles/nano'"

section "4. Grup forum & topik Telegram (menu utama, teks)"
printf '%s\n' 5 2 2 "-1001234567890" 3 sekretaris 1 "" x 0 | KA_PLAIN=1 ka >"$T/grup.out" 2>&1
check "ID grup tersimpan" has "$KA_CONF" "KA_TG_GROUP_ID='-1001234567890'"
check "pemeriksaan grup: bot admin & kelola topik OK" grep -q "Kelola topik   : ya" "$T/grup.out"
check "topik dibuat lewat bot admin (createForumTopic)" bash -c "grep -c 'curl' '$MOCK_LOG' >/dev/null"
check "karyawan dibatasi ke topiknya" has "$P/.env" "TELEGRAM_ALLOWED_TOPICS=77"
check "laporan karyawan dikirim ke grup/topik" bash -c "grep -q 'TELEGRAM_HOME_CHANNEL=-1001234567890' '$P/.env' && grep -q 'TELEGRAM_HOME_CHANNEL_THREAD_ID=77' '$P/.env'"
check "user grup diizinkan untuk karyawan" has "$P/.env" "TELEGRAM_GROUP_ALLOWED_USERS=111111111,222222222"
check "require_mention dimatikan di topik sendiri" has "$P/.env" "TELEGRAM_REQUIRE_MENTION=false"
printf '%s\n' 5 4 x 0 | KA_PLAIN=1 ka >"$T/topikpengawas.out" 2>&1
check "topik Pengawas tersimpan" has "$KA_CONF" "KA_PENGAWAS_THREAD='77'"
check "pesan uji Pengawas terkirim ke topik" has "$MOCK_STATE/tg.log" "thread:77"

section "5. Mode akses & web"
ka web lokal >"$T/web.out" 2>&1
check "web lokal: nginx hanya 127.0.0.1" bash -c "grep -q 'listen 127.0.0.1:8080;' '$KA_NGINX_CONF' && ! grep -q '0.0.0.0' '$KA_NGINX_CONF'"
check "web lokal: tanpa basic auth" hasnt "$KA_NGINX_CONF" "auth_basic"
check "web lokal: dashboard bind 127.0.0.1" has "$KA_SYSTEMD_DIR/kantorai-dashboard.service" "--host 127.0.0.1"
check "web lokal: menampilkan perintah SSH tunnel" has "$T/web.out" "ssh -L 8080:127.0.0.1:8080"
check "nginx -t tetap lulus (mode lokal)" nginx -t
ka web lan >/dev/null 2>&1
check "web lan: htpasswd lama dipakai lagi" has "$KA_NGINX_CONF" "auth_basic_user_file"
cp "$REPO/assets/portal/logo-gnc.svg" "$T/logo-klien.svg"
printf '%s\n' 6 5 1 "$T/logo-klien.svg" x 0 | KA_PLAIN=1 ka >/dev/null 2>&1
check "logo kantor dipasang ke portal" bash -c "test -f '$KA_ETC/brand/logo.svg' && jq -e '.logo == \"logo-kantor.svg\"' '$KA_WWW/portal/portal-config.json'"

printf '%s\n' 6 7 "" "https://panel.klien.co.id" "" x 0 | KA_PLAIN=1 ka >/dev/null 2>&1
check "URL publik panel diteruskan ke dashboard.public_url" has "$MOCK_LOG" "config set dashboard.public_url https://panel.klien.co.id"
check "URL publik tersimpan di pengaturan" has "$KA_CONF" "KA_URL_DASHBOARD='https://panel.klien.co.id'"

section "6. Pengawas"
: >"$MOCK_STATE/tg.log"
echo failed >"$MOCK_STATE/units/kantorai-dashboard.service"
"$KA_LIBDIR/pengawas.sh" periksa
check "layanan mati dipulihkan otomatis" test "$(systemctl is-active kantorai-dashboard)" = active
check "notifikasi pemulihan terkirim" has "$MOCK_STATE/tg.log" "Panel Hermes sempat mati, sudah dipulihkan"
check "notifikasi dikirim ke topik Pengawas" has "$MOCK_STATE/tg.log" "thread:77"
: >"$MOCK_STATE/tg.log"; : >"$MOCK_LOG"
echo failed >"$MOCK_STATE/units/kantorai-ruang.service"
MOCK_FAIL_UNITS="kantorai-ruang" "$KA_LIBDIR/pengawas.sh" periksa
check "layanan gagal pulih dilaporkan MATI" has "$MOCK_STATE/tg.log" "Kantor 3D MATI"
MOCK_FAIL_UNITS="kantorai-ruang" "$KA_LIBDIR/pengawas.sh" periksa
check "tidak ada notifikasi berulang untuk masalah yang sama" test "$(grep -c 'Kantor 3D MATI' "$MOCK_STATE/tg.log")" -eq 1
MOCK_FAIL_UNITS="kantorai-ruang" "$KA_LIBDIR/pengawas.sh" periksa
check "batas restart per jam dihormati" test "$(grep -c 'systemctl restart kantorai-ruang' "$MOCK_LOG")" -le 3
"$KA_LIBDIR/pengawas.sh" periksa
: >"$MOCK_STATE/tg.log"
rm -f "$KA_VAR/pengawas/restarts.kantorai-ruang"
"$KA_LIBDIR/pengawas.sh" periksa
check "notifikasi kembali normal" has "$MOCK_STATE/tg.log" "Kantor 3D kembali normal"
check "status.json memuat 3 karyawan" bash -c "jq -e '.crew | length == 3' '$KA_WWW/status.json'"
"$KA_LIBDIR/pengawas.sh" harian
check "laporan harian terkirim" has "$MOCK_STATE/tg.log" "Laporan harian"
check "laporan harian menyertakan backup" has "$MOCK_STATE/tg.log" "Backup harian: hermes-backup-"
check "backup zip + pengaturan tersimpan" bash -c "ls '$KA_BACKUP_DIR'/hermes-backup-*.zip && ls '$KA_BACKUP_DIR'/hermes-backup-*-kantorai-etc.tgz"
check "file backup chmod 600" bash -c "for f in '$KA_BACKUP_DIR'/hermes-backup-*; do [[ \$(stat -c %a \"\$f\") == 600 ]] || exit 1; done"

section "7. Hapus karyawan"
printf 'y\n' | KA_PLAIN=1 ka karyawan hapus sales >"$T/hapus.out" 2>&1
check "profil sales dihapus" test ! -d "$HERMES_HOME/profiles/sales"
check "arsip profil disimpan sebelum dihapus" bash -c "ls '$KA_BACKUP_DIR'/profil-sales-*.tar.gz"
printf 'n\n' | KA_PLAIN=1 ka karyawan hapus sekretaris >/dev/null 2>&1
check "batal hapus tidak menghapus apa pun" test -d "$P"

section "8. Mode perbaikan (--repair)"
H1=$(cat "$KA_HTPASSWD")
bash "$REPO/install-kantorai.sh" --repair --source "$REPO" >"$T/repair.out" 2>&1
check "repair selesai dengan kode 0" test $? -eq 0
check "repair tidak mengganti password web" test "$(cat "$KA_HTPASSWD")" = "$H1"
check "repair tidak memanggil installer Hermes lagi" grep -q "Hermes Agent sudah terpasang" "$T/repair.out"
check "repair mempertahankan karyawan" test -d "$P"
check "repair mempertahankan grup" has "$KA_CONF" "KA_TG_GROUP_ID='-1001234567890'"

section "9. API plugin dashboard"
mkdir -p "$T/py/fastapi"
cat >"$T/py/fastapi/__init__.py" <<'EOF'
class APIRouter:
    def get(self, path):
        def deco(fn):
            return fn
        return deco
EOF
KANTORAI_ETC=$KA_ETC KANTORAI_WWW=$KA_WWW KANTORAI_HERMES_HOME=$HERMES_HOME PYTHONPATH="$T/py" python3 - "$REPO" >"$T/api.json" 2>"$T/api.err" <<'EOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("p", sys.argv[1] + "/assets/dashboard/plugin/gnc-kantor/dashboard/plugin_api.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(json.dumps(m.overview()))
EOF
check "overview() berjalan" test -s "$T/api.json"
check "overview: nama kantor & mode" bash -c "jq -e '.office == \"PT Uji Coba Sejahtera\" and .mode == \"lan\"' '$T/api.json'"
check "overview: karyawan sekretaris dengan topik 77" bash -c "jq -e '[.crew[] | select(.name == \"sekretaris\" and .telegram == true and .topics == [\"77\"])] | length == 1' '$T/api.json'"
check "overview: logo kantor sebagai data URI" bash -c "jq -e '.logo | startswith(\"data:image/svg+xml;base64,\")' '$T/api.json'"
check "overview: tidak membocorkan token/kunci" bash -c "! grep -qE 'AAH_|sk-or-v1|RahasiaWeb' '$T/api.json'"

section "10. Plugin dashboard (render JS dengan React tiruan)"
API_JSON="$T/api.json" node "$REPO/uji/render_plugin.js" "$REPO" >"$T/js.out" 2>&1
check "plugin Kantor ter-render tanpa error" grep -q "RENDER-OK" "$T/js.out"

# ---------------------------------------------------------------------------
printf '\n\e[1m%d lulus, %d gagal\e[0m\n' "$PASS" "$FAIL"
if ((FAIL)); then
  printf '\nGagal:\n'; printf '  - %s\n' "${FAILS[@]}"
  printf '\nFolder uji disimpan untuk diperiksa: %s\n' "$T"
  exit 1
fi
rm -rf "$T"
echo "SEMUA LULUS"
