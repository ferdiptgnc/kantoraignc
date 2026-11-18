#!/usr/bin/env bash
# shellcheck shell=bash
# ============================================================================
#  setup.sh — langkah pemasangan & penerapan konfigurasi
#  Dipakai oleh install-kantorai.sh dan menu kantorai (perubahan pengaturan).
#  Butuh common.sh sudah di-source.
# ============================================================================

# ---------------------------------------------------------------------------
# Nilai bawaan pengaturan
# ---------------------------------------------------------------------------
ka_defaults() {
  : "${KA_OFFICE_NAME:=Kantor AI}"
  : "${KA_BRAND_NAME:=Galura Nexa Core}"
  : "${KA_TZ:=Asia/Jakarta}"
  : "${KA_ACCESS_MODE:=local}"          # local (127.0.0.1, lewat SSH tunnel) | lan
  : "${KA_PORTAL_PORT:=8080}"
  : "${KA_RUANG_PORT:=3001}"            # port publik Kantor 3D (lewat nginx)
  : "${KA_RUANG_INTERNAL_PORT:=3101}"   # port Ruang di 127.0.0.1
  : "${KA_DASH_PORT:=9119}"
  : "${KA_WEB_USER:=admin}"
  : "${KA_WEB_PASS:=}"
  : "${KA_WITH_DASHBOARD:=yes}"
  : "${KA_WITH_RUANG:=yes}"
  : "${KA_WITH_PORTAL:=yes}"
  : "${KA_WITH_PENGAWAS:=yes}"
  : "${KA_WITH_BROWSER:=no}"            # Chromium untuk tool browser agen (besar)
  : "${KA_WITH_CLOUDFLARED:=no}"
  : "${KA_CF_TOKEN:=}"
  : "${KA_URL_DASHBOARD:=}"             # URL publik (Cloudflare) bila ada
  : "${KA_URL_RUANG:=}"
  : "${KA_URL_PORTAL:=}"
  : "${KA_TG_ADMIN_TOKEN:=}"
  : "${KA_TG_USERS:=}"
  : "${KA_TG_GROUP_ID:=}"
  : "${KA_PENGAWAS_THREAD:=}"
  : "${KA_AUTO_BACKUP:=yes}"
  : "${KA_BACKUP_KEEP:=7}"
  : "${KA_MODEL_MODE:=interactive}"     # interactive | config | skip
  : "${KA_MODEL_PROVIDER:=}"
  : "${KA_MODEL_NAME:=}"
  : "${KA_MODEL_KEY_VAR:=}"
  : "${KA_MODEL_KEY:=}"
}

# Simpan pengaturan non-rahasia ke /etc/kantorai/kantorai.conf
ka_save_conf() {
  local k
  for k in KA_OFFICE_NAME KA_BRAND_NAME KA_TZ KA_ACCESS_MODE KA_PORTAL_PORT KA_RUANG_PORT \
           KA_RUANG_INTERNAL_PORT KA_DASH_PORT KA_WEB_USER KA_WITH_DASHBOARD KA_WITH_RUANG \
           KA_WITH_PORTAL KA_WITH_PENGAWAS KA_WITH_CLOUDFLARED KA_URL_DASHBOARD KA_URL_RUANG \
           KA_URL_PORTAL KA_TG_GROUP_ID KA_PENGAWAS_THREAD KA_AUTO_BACKUP KA_BACKUP_KEEP; do
    conf_set "$k" "${!k-}"
  done
  conf_set KA_INSTALLED_VERSION "$KA_VERSION"
}

# Muat pengaturan tersimpan ke variabel KA_* (untuk menu / perbaikan).
ka_load_conf() {
  if [[ -r $KA_CONF ]]; then
    # shellcheck disable=SC1090
    . "$KA_CONF"
  fi
  ka_defaults
}

ka_bind_addr() { if [[ $KA_ACCESS_MODE == lan ]]; then printf '0.0.0.0'; else printf '127.0.0.1'; fi; }

# ---------------------------------------------------------------------------
# Salin file program
# ---------------------------------------------------------------------------
ka_install_files() { # ka_install_files SRC_DIR
  local src=$1
  mkdir -p "$KA_HOME" "$KA_ETC" "$KA_VAR" "$KA_WWW" "$KA_BACKUP_DIR" "$KA_LIBDIR" "$KA_ETC/brand" "$KA_BINDIR" "$KA_SYSTEMD_DIR" || return 1
  chmod 700 "$KA_ETC" "$KA_BACKUP_DIR"
  if [[ $(readlink -f "$src") != $(readlink -f "$KA_HOME") ]]; then
    rm -rf "$KA_HOME.new"
    mkdir -p "$KA_HOME.new"
    cp -a "$src"/. "$KA_HOME.new"/
    rm -rf "$KA_HOME.new/.git" "$KA_HOME.old"
    [[ -d $KA_HOME ]] && mv "$KA_HOME" "$KA_HOME.old"
    mv "$KA_HOME.new" "$KA_HOME" && rm -rf "$KA_HOME.old"
  fi
  install -m 644 "$KA_HOME/lib/common.sh" "$KA_LIBDIR/common.sh" &&
  install -m 644 "$KA_HOME/lib/setup.sh" "$KA_LIBDIR/setup.sh" &&
  install -m 755 "$KA_HOME/lib/pengawas.sh" "$KA_LIBDIR/pengawas.sh" &&
  install -m 755 "$KA_HOME/kantorai" "$KA_BINDIR/kantorai" || return 1
  # PATH untuk alias karyawan (/root/.local/bin/<nama>) di semua shell login
  if [[ -d $KA_PROFILE_D ]]; then
    cat >"$KA_PROFILE_D/kantorai.sh" <<'EOF'
# GNC Kantor AI: perintah hermes & alias karyawan ada di ~/.local/bin
case ":$PATH:" in *":/root/.local/bin:"*) ;; *) [ "$(id -u)" = 0 ] && PATH="/root/.local/bin:$PATH" ;; esac
EOF
  fi
  touch "$KA_LOG"; chmod 600 "$KA_LOG"
}

# ---------------------------------------------------------------------------
# Hermes Agent
# ---------------------------------------------------------------------------
ka_install_hermes() {
  if hermes_ok; then
    okp "Hermes Agent sudah terpasang ($(hm --version 2>/dev/null | head -1))"
    return 0
  fi
  local args=(--non-interactive --skip-computer-use)
  [[ $KA_WITH_BROWSER == yes ]] || args+=(--skip-browser)
  say "Memasang Hermes Agent (beberapa menit, log: $KA_LOG)..."
  if ! curl -fsSL --retry 3 "$KA_HERMES_INSTALL_URL" -o "$KA_VAR/hermes-install.sh"; then
    errp "Gagal mengunduh installer Hermes dari $KA_HERMES_INSTALL_URL"; return 1
  fi
  if ! HOME=$KA_ROOT_HOME bash "$KA_VAR/hermes-install.sh" "${args[@]}" >>"$KA_LOG" 2>&1; then
    errp "Installer Hermes gagal. Lihat: tail -50 $KA_LOG"; return 1
  fi
  hermes_ok || { errp "Perintah hermes tidak ditemukan di $HERMES_BIN setelah instalasi."; return 1; }
  okp "Hermes Agent terpasang ($(hm --version 2>/dev/null | head -1))"
}

# Bot admin (profil default) + user yang diizinkan
ka_apply_telegram_admin() {
  local envf; envf=$(profile_env default)
  if [[ -n $KA_TG_ADMIN_TOKEN ]]; then
    envset "$envf" TELEGRAM_BOT_TOKEN "$KA_TG_ADMIN_TOKEN"
  fi
  if [[ -n $KA_TG_USERS ]]; then
    envset "$envf" TELEGRAM_ALLOWED_USERS "$KA_TG_USERS"
    [[ -n $(envget "$envf" TELEGRAM_HOME_CHANNEL) ]] || envset "$envf" TELEGRAM_HOME_CHANNEL "${KA_TG_USERS%%,*}"
  fi
  if [[ -n $KA_TG_GROUP_ID ]]; then
    envset "$envf" TELEGRAM_GROUP_ALLOWED_USERS "$(envget "$envf" TELEGRAM_ALLOWED_USERS)"
  fi
  return 0
}

ka_apply_model_config() { # mode tanpa dialog: tulis provider/model/key
  [[ -n $KA_MODEL_PROVIDER ]] && hm config set model.provider "$KA_MODEL_PROVIDER" >>"$KA_LOG" 2>&1
  [[ -n $KA_MODEL_NAME ]] && hm config set model.default "$KA_MODEL_NAME" >>"$KA_LOG" 2>&1
  if [[ -n $KA_MODEL_KEY_VAR && -n $KA_MODEL_KEY ]]; then
    [[ $KA_MODEL_KEY_VAR =~ ^[A-Z][A-Z0-9_]{2,60}$ ]] || { warnp "KA_MODEL_KEY_VAR tidak valid: $KA_MODEL_KEY_VAR"; return 1; }
    envset "$(profile_env default)" "$KA_MODEL_KEY_VAR" "$KA_MODEL_KEY"
  fi
  return 0
}

ka_install_gateway() {
  if [[ -f $KA_SYSTEMD_DIR/$KA_GATEWAY_UNIT.service ]]; then
    gateway_restart || warnp "Gateway gagal di-restart; cek: kantorai logs gateway"
    return 0
  fi
  say "Memasang gateway Hermes sebagai system service (root)..."
  if hm gateway install --system --run-as-user root --start-now --start-on-login </dev/null >>"$KA_LOG" 2>&1; then
    okp "Gateway terpasang ($KA_GATEWAY_UNIT.service)"
  else
    warnp "Pemasangan gateway gagal. Ulangi lewat: kantorai layanan → pasang ulang gateway"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Panel Hermes (dashboard) + branding GNC
# ---------------------------------------------------------------------------
ka_install_branding() {
  local tdir="$HERMES_HOME/dashboard-themes" pdir="$HERMES_HOME/plugins/$KA_PLUGIN_NAME"
  mkdir -p "$tdir" "$HERMES_HOME/plugins"
  install -m 644 "$KA_HOME/assets/dashboard/theme-gnc.yaml" "$tdir/gnc.yaml"
  rm -rf "$pdir"
  cp -a "$KA_HOME/assets/dashboard/plugin/$KA_PLUGIN_NAME" "$pdir"
  if hermes_ok; then
    hm config set dashboard.theme "$KA_THEME_NAME" >>"$KA_LOG" 2>&1 || true
    hm plugins enable "$KA_PLUGIN_NAME" >>"$KA_LOG" 2>&1 || true
  fi
}

ka_write_dashboard_unit() {
  local host; host=$(ka_bind_addr)
  cat >"$KA_SYSTEMD_DIR/$KA_DASH_UNIT.service" <<EOF
# GNC Kantor AI — dibuat otomatis oleh kantorai. Ubah lewat menu kantorai.
[Unit]
Description=GNC Kantor AI - Panel Hermes (dashboard web)
After=network-online.target $KA_GATEWAY_UNIT.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$KA_ROOT_HOME
Environment=HOME=$KA_ROOT_HOME
Environment=HERMES_HOME=$HERMES_HOME
Environment=PATH=$KA_ROOT_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=-$HERMES_HOME/.env
ExecStart=$HERMES_BIN dashboard --no-open --host $host --port $KA_DASH_PORT
Restart=always
RestartSec=10
RestartPreventExitStatus=78

[Install]
WantedBy=multi-user.target
EOF
}

# Login username/password panel Hermes (fitur bawaan Hermes): wajib saat mode LAN
# atau saat panel dibuka lewat domain publik (dashboard.public_url).
ka_apply_dashboard_auth() {
  local envf; envf=$(profile_env default)
  if hermes_ok; then
    hm config set dashboard.public_url "${KA_URL_DASHBOARD:-}" >>"$KA_LOG" 2>&1 || true
  fi
  if [[ ($KA_ACCESS_MODE == lan || -n $KA_URL_DASHBOARD) && -n $KA_WEB_PASS ]]; then
    envset "$envf" HERMES_DASHBOARD_BASIC_AUTH_USERNAME "$KA_WEB_USER"
    envset "$envf" HERMES_DASHBOARD_BASIC_AUTH_PASSWORD "$KA_WEB_PASS"
    [[ -n $(envget "$envf" HERMES_DASHBOARD_BASIC_AUTH_SECRET) ]] || envset "$envf" HERMES_DASHBOARD_BASIC_AUTH_SECRET "$(gen_secret 36)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Kantor 3D (Ruang, MIT — github.com/yugienugraha/ruang)
# ---------------------------------------------------------------------------
ka_install_ruang() {
  if [[ -x $KA_RUANG_CMD ]]; then
    okp "Kantor 3D (Ruang) sudah terpasang"
    return 0
  fi
  say "Memasang Kantor 3D (Ruang)..."
  if ! curl -fsSL --retry 3 "$KA_RUANG_INSTALL_URL" -o "$KA_VAR/ruang-install.sh"; then
    errp "Gagal mengunduh installer Ruang"; return 1
  fi
  if env -u RUANG_BIN -u RUANG_HOME HOME=$KA_ROOT_HOME bash "$KA_VAR/ruang-install.sh" >>"$KA_LOG" 2>&1 && [[ -x $KA_RUANG_CMD ]]; then
    okp "Kantor 3D terpasang"
  else
    errp "Installer Ruang gagal. Lihat: tail -50 $KA_LOG"; return 1
  fi
}

ka_write_ruang_unit() {
  cat >"$KA_SYSTEMD_DIR/$KA_RUANG_UNIT.service" <<EOF
# GNC Kantor AI — dibuat otomatis oleh kantorai. Ubah lewat menu kantorai.
[Unit]
Description=GNC Kantor AI - Kantor 3D (Ruang)
After=network-online.target $KA_GATEWAY_UNIT.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$KA_ROOT_HOME
Environment=HOME=$KA_ROOT_HOME
Environment=HERMES_HOME=$HERMES_HOME
Environment=RUANG_PORT=$KA_RUANG_INTERNAL_PORT
Environment=PATH=$KA_ROOT_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$KA_RUANG_CMD --port $KA_RUANG_INTERNAL_PORT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

# ---------------------------------------------------------------------------
# Portal web + nginx
# ---------------------------------------------------------------------------
ka_set_web_password() { # tulis htpasswd nginx (apr1)
  local hash
  hash=$(openssl passwd -apr1 "$KA_WEB_PASS") || return 1
  (umask 027; printf '%s:%s\n' "$KA_WEB_USER" "$hash" >"$KA_HTPASSWD")
  if getent group www-data >/dev/null; then chgrp www-data "$KA_HTPASSWD"; chmod 640 "$KA_HTPASSWD"; fi
  chmod 711 "$KA_ETC"
}

ka_json_str() { jq -Rn --arg v "$1" '$v'; }

ka_render_portal() {
  local p="$KA_WWW/portal" b="$KA_WWW/ruang-brand" logo=""
  mkdir -p "$p" "$b"
  cp -a "$KA_HOME/assets/portal/." "$p/"
  cp -a "$KA_HOME/assets/ruang-brand/." "$b/"
  for logo in "$KA_ETC"/brand/logo.*; do
    [[ -f $logo ]] || { logo=""; continue; }
    cp -f "$logo" "$p/logo-kantor.${logo##*.}"; cp -f "$logo" "$b/logo-kantor.${logo##*.}"
    logo="logo-kantor.${logo##*.}"; break
  done
  jq -n \
    --arg office "$KA_OFFICE_NAME" --arg brand "$KA_BRAND_NAME" --arg mode "$KA_ACCESS_MODE" \
    --arg version "$KA_VERSION" --arg logo "$logo" \
    --arg url_dash "$KA_URL_DASHBOARD" --arg url_ruang "$KA_URL_RUANG" \
    --argjson dash_port "$KA_DASH_PORT" --argjson ruang_port "$KA_RUANG_PORT" \
    --argjson dash_on "$([[ $KA_WITH_DASHBOARD == yes ]] && echo true || echo false)" \
    --argjson ruang_on "$([[ $KA_WITH_RUANG == yes ]] && echo true || echo false)" \
    '{office:$office, brand:$brand, mode:$mode, version:$version, logo:$logo,
      dashboard:{enabled:$dash_on, port:$dash_port, url:$url_dash},
      ruang:{enabled:$ruang_on, port:$ruang_port, url:$url_ruang}}' >"$p/portal-config.json"
  cp -f "$p/portal-config.json" "$b/config.json"
  [[ -f $KA_WWW/status.json ]] || printf '{"generated_at":null}\n' >"$KA_WWW/status.json"
  chmod -R a+rX "$KA_WWW"
}

ka_render_nginx() {
  local bind auth="" conf
  bind=$(ka_bind_addr)
  if [[ $KA_ACCESS_MODE == lan ]]; then
    auth="    auth_basic \"$KA_OFFICE_NAME\";
    auth_basic_user_file $KA_HTPASSWD;"
  fi
  conf="# GNC Kantor AI — dibuat otomatis oleh kantorai. Ubah lewat menu kantorai, bukan manual.
map \$http_upgrade \$kantorai_conn_upgrade { default upgrade; '' close; }
"
  if [[ $KA_WITH_PORTAL == yes ]]; then
    conf+="
server {
    listen $bind:$KA_PORTAL_PORT;
    server_name _;
    root $KA_WWW/portal;
    index index.html;
    server_tokens off;
$auth
    location = /status.json { alias $KA_WWW/status.json; add_header Cache-Control \"no-store\"; }
    location / { try_files \$uri \$uri/ =404; }
}
"
  fi
  if [[ $KA_WITH_RUANG == yes ]]; then
    conf+="
server {
    listen $bind:$KA_RUANG_PORT;
    server_name _;
    server_tokens off;
$auth
    location /__gnc/ { alias $KA_WWW/ruang-brand/; }
    location / {
        proxy_pass http://127.0.0.1:$KA_RUANG_INTERNAL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host 127.0.0.1:$KA_RUANG_INTERNAL_PORT;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$kantorai_conn_upgrade;
        proxy_set_header Accept-Encoding \"\";
        proxy_read_timeout 300s;
        sub_filter_once on;
        sub_filter '</head>' '<link rel=\"stylesheet\" href=\"/__gnc/brand.css\"><script defer src=\"/__gnc/brand.js\"></script></head>';
    }
}
"
  fi
  mkdir -p "$(dirname "$KA_NGINX_CONF")"
  printf '%s' "$conf" >"$KA_NGINX_CONF"
}

ka_nginx_reload() {
  command -v nginx >/dev/null 2>&1 || return 0
  if ! nginx -t >>"$KA_LOG" 2>&1; then
    errp "Konfigurasi nginx tidak valid (cek: nginx -t)"; return 1
  fi
  systemctl enable nginx >>"$KA_LOG" 2>&1 || true
  systemctl reload nginx >>"$KA_LOG" 2>&1 || systemctl restart nginx >>"$KA_LOG" 2>&1
}

# Situs default nginx memakai port 80; matikan bila portal memakai port 80.
ka_nginx_disable_default_if_needed() {
  [[ $KA_PORTAL_PORT == 80 && -L /etc/nginx/sites-enabled/default ]] || return 0
  rm -f /etc/nginx/sites-enabled/default
  warnp "Situs default nginx dinonaktifkan karena port 80 dipakai portal."
}

# ---------------------------------------------------------------------------
# Pengawas (watchdog)
# ---------------------------------------------------------------------------
ka_write_pengawas_units() {
  cat >"$KA_SYSTEMD_DIR/$KA_PENGAWAS_UNIT.service" <<EOF
# GNC Kantor AI — dibuat otomatis oleh kantorai.
[Unit]
Description=GNC Kantor AI - Pengawas (cek layanan, pulihkan otomatis, kirim notifikasi)
After=network-online.target

[Service]
Type=oneshot
ExecStart=$KA_LIBDIR/pengawas.sh periksa
Nice=10
EOF
  cat >"$KA_SYSTEMD_DIR/$KA_PENGAWAS_UNIT.timer" <<EOF
[Unit]
Description=GNC Kantor AI - Pengawas setiap 2 menit

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=15s

[Install]
WantedBy=timers.target
EOF
  cat >"$KA_SYSTEMD_DIR/$KA_PENGAWAS_UNIT-harian.service" <<EOF
[Unit]
Description=GNC Kantor AI - Laporan harian & backup otomatis

[Service]
Type=oneshot
ExecStart=$KA_LIBDIR/pengawas.sh harian
Nice=15
EOF
  cat >"$KA_SYSTEMD_DIR/$KA_PENGAWAS_UNIT-harian.timer" <<EOF
[Unit]
Description=GNC Kantor AI - Laporan harian pukul 07:05

[Timer]
OnCalendar=*-*-* 07:05:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

# ---------------------------------------------------------------------------
# Cloudflare Tunnel (opsional, akun Cloudflare milik klien)
# ---------------------------------------------------------------------------
ka_install_cloudflared() {
  [[ -n $KA_CF_TOKEN ]] || { warnp "Token Cloudflare Tunnel kosong, dilewati."; return 0; }
  if ! command -v cloudflared >/dev/null 2>&1; then
    say "Memasang cloudflared..."
    mkdir -p /usr/share/keyrings && chmod 755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg >>"$KA_LOG" 2>&1 || return 1
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
      >/etc/apt/sources.list.d/cloudflared.list
    apt-get update >>"$KA_LOG" 2>&1 && apt-get install -y cloudflared >>"$KA_LOG" 2>&1 || return 1
  fi
  cloudflared service uninstall >>"$KA_LOG" 2>&1 || true
  if cloudflared service install "$KA_CF_TOKEN" >>"$KA_LOG" 2>&1; then
    okp "Cloudflare Tunnel terpasang (atur hostname di dashboard Cloudflare Zero Trust)"
  else
    errp "cloudflared service install gagal (cek token)"; return 1
  fi
}

# ---------------------------------------------------------------------------
# Terapkan semua layanan web sesuai pengaturan (dipakai installer & menu)
# ---------------------------------------------------------------------------
ka_apply_web() {
  systemctl daemon-reload
  if [[ $KA_WITH_DASHBOARD == yes ]]; then
    ka_apply_dashboard_auth
    ka_write_dashboard_unit
    systemctl daemon-reload
    systemctl enable "$KA_DASH_UNIT" >>"$KA_LOG" 2>&1
    systemctl restart "$KA_DASH_UNIT" >>"$KA_LOG" 2>&1 || warnp "Panel Hermes gagal start (kantorai logs dashboard)"
  else
    systemctl disable --now "$KA_DASH_UNIT" >>"$KA_LOG" 2>&1 || true
  fi
  if [[ $KA_WITH_RUANG == yes && -x $KA_RUANG_CMD ]]; then
    ka_write_ruang_unit
    systemctl daemon-reload
    systemctl enable "$KA_RUANG_UNIT" >>"$KA_LOG" 2>&1
    systemctl restart "$KA_RUANG_UNIT" >>"$KA_LOG" 2>&1 || warnp "Kantor 3D gagal start (kantorai logs ruang)"
  else
    systemctl disable --now "$KA_RUANG_UNIT" >>"$KA_LOG" 2>&1 || true
  fi
  if [[ $KA_WITH_PORTAL == yes || $KA_WITH_RUANG == yes ]]; then
    [[ $KA_ACCESS_MODE == lan && -n $KA_WEB_PASS ]] && ka_set_web_password
    ka_render_portal
    ka_nginx_disable_default_if_needed
    ka_render_nginx
    ka_nginx_reload
  else
    rm -f "$KA_NGINX_CONF"; ka_nginx_reload
  fi
}

ka_urls_text() { # ringkasan alamat untuk ditampilkan
  local host; if [[ $KA_ACCESS_MODE == lan ]]; then host=$(local_ip); else host=127.0.0.1; fi
  [[ $KA_WITH_PORTAL == yes ]]    && printf 'Portal kantor : %s\n' "${KA_URL_PORTAL:-http://$host:$KA_PORTAL_PORT}"
  [[ $KA_WITH_DASHBOARD == yes ]] && printf 'Panel Hermes  : %s\n' "${KA_URL_DASHBOARD:-http://$host:$KA_DASH_PORT}"
  [[ $KA_WITH_RUANG == yes ]]     && printf 'Kantor 3D     : %s\n' "${KA_URL_RUANG:-http://$host:$KA_RUANG_PORT}"
  if [[ $KA_ACCESS_MODE != lan ]]; then
    printf '\nMode lokal: buka lewat SSH tunnel dari laptop, contoh:\n'
    printf '  ssh -L %s:127.0.0.1:%s -L %s:127.0.0.1:%s -L %s:127.0.0.1:%s root@%s\n' \
      "$KA_PORTAL_PORT" "$KA_PORTAL_PORT" "$KA_DASH_PORT" "$KA_DASH_PORT" "$KA_RUANG_PORT" "$KA_RUANG_PORT" "$(local_ip)"
  fi
  return 0
}
