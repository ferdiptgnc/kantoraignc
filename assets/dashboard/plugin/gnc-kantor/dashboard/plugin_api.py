"""GNC Kantor AI — API plugin dashboard (hanya baca).

Dipasang di ~/.hermes/plugins/gnc-kantor/dashboard/plugin_api.py dan dimuat oleh
`hermes dashboard` di /api/plugins/gnc-kantor/. Semua rute ada di balik gerbang
login dashboard. Tidak ada rute yang mengubah sistem atau mengembalikan rahasia.
"""

from __future__ import annotations

import base64
import json
import os
import shlex
import socket
import subprocess
import time
from pathlib import Path
from typing import Any

from fastapi import APIRouter

router = APIRouter()

ETC = Path(os.environ.get("KANTORAI_ETC", "/etc/kantorai"))
WWW = Path(os.environ.get("KANTORAI_WWW", "/var/www/kantorai"))
HERMES_HOME = Path(os.environ.get("KANTORAI_HERMES_HOME", str(Path.home() / ".hermes")))

UNITS = [
    ("hermes-gateway", "Gateway Hermes", None),
    ("kantorai-dashboard", "Panel Hermes", "KA_WITH_DASHBOARD"),
    ("kantorai-ruang", "Kantor 3D", "KA_WITH_RUANG"),
    ("nginx", "Portal (nginx)", "KA_WITH_PORTAL"),
    ("kantorai-pengawas.timer", "Pengawas", "KA_WITH_PENGAWAS"),
    ("cloudflared", "Cloudflare Tunnel", "KA_WITH_CLOUDFLARED"),
]
LOGO_TYPES = {".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}


def _read_conf() -> dict[str, str]:
    """Baca /etc/kantorai/kantorai.conf (format KEY='nilai') tanpa mengeksekusinya."""
    conf: dict[str, str] = {}
    path = ETC / "kantorai.conf"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return conf
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        key = key.strip()
        if not key.startswith("KA_"):
            continue
        try:
            parts = shlex.split(raw)
            conf[key] = parts[0] if parts else ""
        except ValueError:
            conf[key] = raw.strip("'\"")
    return conf


def _unit_state(unit: str) -> str:
    try:
        out = subprocess.run(["systemctl", "is-active", unit], capture_output=True, text=True, timeout=5)
        return (out.stdout or out.stderr).strip() or "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


def _env_has(path: Path, key: str) -> bool:
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith(key + "=") and line[len(key) + 1:].strip().strip("'\""):
                return True
    except OSError:
        pass
    return False


def _env_get(path: Path, key: str) -> str:
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith(key + "="):
                return line[len(key) + 1:].strip().strip("'\"")
    except OSError:
        pass
    return ""


def _yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml  # dependensi inti Hermes

        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _model_of(cfg: dict[str, Any]) -> str:
    model = cfg.get("model")
    if isinstance(model, str):
        return model
    if isinstance(model, dict):
        name = model.get("default") or model.get("model") or ""
        prov = model.get("provider") or ""
        return f"{name} ({prov})" if name and prov else str(name or prov)
    return ""


def _crew() -> list[dict[str, Any]]:
    homes: list[tuple[str, Path]] = [("default", HERMES_HOME)]
    pdir = HERMES_HOME / "profiles"
    if pdir.is_dir():
        homes += [(p.name, p) for p in sorted(pdir.iterdir()) if p.is_dir() and not p.name.startswith(".")]
    crew = []
    for name, home in homes:
        meta = _yaml(home / "profile.yaml")
        env = home / ".env"
        desc = str(meta.get("description") or "")
        if name == "default" and not desc:
            desc = "Asisten utama & admin kantor"
        topics = _env_get(env, "TELEGRAM_ALLOWED_TOPICS")
        crew.append({
            "name": name,
            "description": desc,
            "model": _model_of(_yaml(home / "config.yaml")),
            "telegram": _env_has(env, "TELEGRAM_BOT_TOKEN"),
            "topics": [t for t in topics.split(",") if t.strip()],
            "has_soul": (home / "SOUL.md").is_file(),
        })
    return crew


def _logo_data_uri() -> str:
    for path in sorted((ETC / "brand").glob("logo.*")):
        mime = LOGO_TYPES.get(path.suffix.lower())
        try:
            if mime and path.stat().st_size <= 1_048_576:
                return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")
        except OSError:
            continue
    return ""


def _host() -> dict[str, Any]:
    info: dict[str, Any] = {"hostname": socket.gethostname()}
    try:
        st = os.statvfs("/")
        info["disk_pct"] = round(100 * (1 - st.f_bavail / st.f_blocks)) if st.f_blocks else None
    except OSError:
        info["disk_pct"] = None
    try:
        mem = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            k, _, v = line.partition(":")
            mem[k] = int(v.split()[0])
        info["mem_pct"] = round(100 * (mem["MemTotal"] - mem["MemAvailable"]) / mem["MemTotal"])
    except (OSError, KeyError, ValueError, ZeroDivisionError):
        info["mem_pct"] = None
    try:
        info["uptime_s"] = int(float(Path("/proc/uptime").read_text().split()[0]))
    except (OSError, ValueError, IndexError):
        info["uptime_s"] = None
    return info


@router.get("/overview")
def overview() -> dict[str, Any]:
    conf = _read_conf()
    services = []
    for unit, label, flag in UNITS:
        if flag and conf.get(flag, "yes" if flag != "KA_WITH_CLOUDFLARED" else "no") != "yes":
            continue
        services.append({"unit": unit, "label": label, "state": _unit_state(unit)})
    pengawas: dict[str, Any] = {}
    try:
        pengawas = json.loads((WWW / "status.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    mode = conf.get("KA_ACCESS_MODE", "local")
    return {
        "office": conf.get("KA_OFFICE_NAME", "Kantor AI"),
        "brand": conf.get("KA_BRAND_NAME", "Galura Nexa Core"),
        "version": conf.get("KA_INSTALLED_VERSION", ""),
        "mode": mode,
        "telegram_group": bool(conf.get("KA_TG_GROUP_ID")),
        "links": {
            "ruang": conf.get("KA_URL_RUANG", ""),
            "ruang_port": conf.get("KA_RUANG_PORT", "3001") if conf.get("KA_WITH_RUANG", "yes") in ("yes", "external") else "",
            "portal": conf.get("KA_URL_PORTAL", ""),
            "portal_port": conf.get("KA_PORTAL_PORT", "8080") if conf.get("KA_WITH_PORTAL", "yes") == "yes" else "",
        },
        "services": services,
        "crew": _crew(),
        "host": _host(),
        "pengawas_at": pengawas.get("generated_at"),
        "logo": _logo_data_uri(),
        "now": int(time.time()),
    }
