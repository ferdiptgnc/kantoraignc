/* GNC Kantor AI — portal. Membaca portal-config.json (dibuat kantorai) dan
 * status.json (ditulis Pengawas tiap 2 menit). Tidak ada data rahasia di keduanya. */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var STATE = { active: "Aktif", inactive: "Berhenti", failed: "Gagal", activating: "Memulai" };

  function linkFor(cfg) {
    if (!cfg || !cfg.enabled) return "";
    if (cfg.url) return cfg.url;
    return location.protocol + "//" + location.hostname + ":" + cfg.port;
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function setDoor(id, url) {
    var d = $(id);
    if (url) { d.href = url; d.removeAttribute("aria-disabled"); }
    else { d.removeAttribute("href"); d.setAttribute("aria-disabled", "true"); }
  }
  function meter(bar, label, v) {
    $(label).textContent = (v === null || v === undefined) ? "–" : v + "%";
    $(bar).style.width = Math.max(0, Math.min(100, v || 0)) + "%";
    $(bar).className = v >= 85 ? "hot" : "";
  }

  function tick() {
    var d = new Date();
    $("clock").textContent = d.toLocaleDateString("id-ID", { weekday: "long", day: "numeric", month: "long" }) +
      " · " + d.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" });
  }

  function loadConfig() {
    return fetch("portal-config.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (c) {
      $("office").textContent = c.office || "Kantor AI";
      document.title = (c.office || "Kantor AI") + " · GNC Kantor AI";
      $("version").textContent = c.version ? "v" + c.version : "";
      if (c.logo) { $("client-logo").src = c.logo; $("client-logo").alt = c.office; $("client-logo").hidden = false; }
      setDoor("door-ruang", linkFor(c.ruang));
      setDoor("door-panel", linkFor(c.dashboard));
    }).catch(function () {});
  }

  function render(s) {
    var crew = $("crew"), svc = $("svc");
    crew.textContent = ""; svc.textContent = "";
    var staff = (s.crew || []);
    staff.forEach(function (c) {
      var li = el("li");
      li.appendChild(el("span", "av", (c.name === "default" ? "AD" : c.name.slice(0, 2).toUpperCase())));
      var box = el("div");
      box.appendChild(el("div", "nm", c.name === "default" ? "admin" : c.name));
      box.appendChild(el("div", "ds", c.description || "Belum ada jabatan"));
      li.appendChild(box);
      li.appendChild(el("span", "tg" + (c.telegram ? " on" : ""), c.telegram ? "● Telegram" : "○ tanpa bot"));
      crew.appendChild(li);
    });
    if (!staff.length) crew.appendChild(el("li", "muted", "Belum ada data karyawan."));
    $("crew-count").textContent = Math.max(0, staff.length - 1) + " karyawan";

    var ok = 0;
    (s.services || []).forEach(function (x) {
      var li = el("li");
      var cls = x.state === "active" ? "ok" : (x.state === "failed" ? "bad" : "");
      if (x.state === "active") ok++;
      li.appendChild(el("span", "dot " + cls));
      li.appendChild(el("span", "", x.label));
      li.appendChild(el("span", "st", STATE[x.state] || x.state));
      svc.appendChild(li);
    });
    if (!(s.services || []).length) svc.appendChild(el("li", "muted", "Belum ada data layanan."));
    $("svc-summary").textContent = ok + "/" + (s.services || []).length + " aktif";
    meter("disk-bar", "disk", s.disk_pct);
    meter("mem-bar", "mem", s.mem_pct);
    if (s.generated_at) {
      var age = Math.round((Date.now() - new Date(s.generated_at).getTime()) / 60000);
      $("stamp").textContent = "Diperbarui Pengawas " + (age <= 0 ? "baru saja" : age + " menit lalu") + " · " + (s.hostname || "");
    }
  }

  function loadStatus() {
    fetch("status.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(render).catch(function () {
      $("stamp").textContent = "Data status belum tersedia (Pengawas belum berjalan).";
    });
  }

  tick(); setInterval(tick, 30000);
  loadConfig(); loadStatus(); setInterval(loadStatus, 30000);
})();
