/* GNC Kantor AI — branding Kantor 3D (Ruang, MIT, github.com/yugienugraha/ruang).
 * Disisipkan nginx (sub_filter) tanpa mengubah kode Ruang, jadi aman saat Ruang diperbarui. */
(function () {
  "use strict";
  if (window.__gncBrand) return;
  window.__gncBrand = true;
  var KEY = "gnc-badge-min";
  var office = "Kantor AI";

  function store(get, val) {
    try { if (get) return localStorage.getItem(KEY); localStorage.setItem(KEY, val); } catch (e) { return null; }
    return null;
  }

  function fixTitle() {
    var t = document.title || "";
    if (/ · Ruang$/.test(t)) document.title = t.replace(/ · Ruang$/, " · Kantor 3D " + office);
  }

  function build(cfg) {
    office = (cfg && cfg.office) || office;
    var logo = (cfg && cfg.logo) ? "/__gnc/" + cfg.logo : "/__gnc/logo-gnc.svg";
    var b = document.createElement("div");
    b.id = "gnc-badge";
    b.setAttribute("role", "note");
    var img = document.createElement("img");
    img.src = logo; img.alt = "";
    var txt = document.createElement("div");
    txt.className = "gnc-txt";
    var t = document.createElement("div"); t.className = "gnc-t"; t.textContent = "Kantor 3D · " + office;
    var s = document.createElement("div"); s.className = "gnc-s";
    s.appendChild(document.createTextNode("GNC Kantor AI · Galura Nexa Core · "));
    var a = document.createElement("a");
    a.href = "https://github.com/yugienugraha/ruang"; a.target = "_blank"; a.rel = "noopener"; a.textContent = "Ruang (MIT)";
    s.appendChild(a);
    txt.appendChild(t); txt.appendChild(s);
    var btn = document.createElement("button");
    btn.type = "button"; btn.title = "Kecilkan"; btn.textContent = "–";
    btn.onclick = function () { b.classList.add("gnc-min"); store(false, "1"); };
    img.onclick = function () { if (b.classList.contains("gnc-min")) { b.classList.remove("gnc-min"); store(false, "0"); } };
    b.appendChild(img); b.appendChild(txt); b.appendChild(btn);
    if (store(true) === "1") b.classList.add("gnc-min");
    document.body.appendChild(b);
    fixTitle();
    var titleEl = document.querySelector("title");
    if (titleEl && window.MutationObserver) new MutationObserver(fixTitle).observe(titleEl, { childList: true, characterData: true, subtree: true });
  }

  function start() {
    fetch("/__gnc/config.json", { cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(build).catch(function () { build(null); });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();
})();
