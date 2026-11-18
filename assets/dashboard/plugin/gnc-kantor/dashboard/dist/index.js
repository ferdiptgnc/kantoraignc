/* GNC Kantor AI — plugin Panel Hermes (tab "Kantor", lambang header, footer).
 * Galura Nexa Core — Technology Infrastructure.
 * IIFE tanpa build step: memakai React dari window.__HERMES_PLUGIN_SDK__.
 */
(function () {
  "use strict";

  var SDK = window.__HERMES_PLUGIN_SDK__;
  var REG = window.__HERMES_PLUGINS__;
  if (!SDK || !REG) return;

  var React = SDK.React;
  var h = React.createElement;
  var useState = SDK.hooks.useState;
  var useEffect = SDK.hooks.useEffect;
  var NAME = "gnc-kantor";
  var API = "/api/plugins/" + NAME + "/overview";

  var STATE_LABEL = {
    active: "Aktif", inactive: "Berhenti", failed: "Gagal", activating: "Memulai",
    deactivating: "Berhenti...", unknown: "Tidak diketahui"
  };

  function GncMark(props) {
    var size = props.size || 28;
    return h("svg", { viewBox: "0 0 64 64", width: size, height: size, "aria-hidden": "true", className: "gk-mark" },
      h("rect", { width: 64, height: 64, rx: 14, fill: "#0b1a30" }),
      h("path", { d: "M44 22a16 16 0 1 0 2 16H34", fill: "none", stroke: "#1e88ff", strokeWidth: 5, strokeLinecap: "round" }),
      h("circle", { cx: 34, cy: 38, r: 4, fill: "#c9a26b" }),
      h("circle", { cx: 44, cy: 22, r: 3.2, fill: "#4aa3ff" })
    );
  }

  function linkFor(url, port) {
    if (url) return url;
    if (!port) return "";
    return window.location.protocol + "//" + window.location.hostname + ":" + port;
  }

  function pct(v) { return v === null || v === undefined ? "–" : v + "%"; }

  function uptime(s) {
    if (!s && s !== 0) return "–";
    var d = Math.floor(s / 86400), hh = Math.floor((s % 86400) / 3600);
    return d > 0 ? d + " hari " + hh + " jam" : hh + " jam " + Math.floor((s % 3600) / 60) + " mnt";
  }

  function useOverview() {
    var st = useState({ data: null, error: null });
    var state = st[0], setState = st[1];
    useEffect(function () {
      var alive = true;
      function load() {
        SDK.fetchJSON(API)
          .then(function (d) { if (alive) setState({ data: d, error: null }); })
          .catch(function (e) { if (alive) setState(function (p) { return { data: p.data, error: String(e && e.message || e) }; }); });
      }
      load();
      var t = setInterval(load, 15000);
      return function () { alive = false; clearInterval(t); };
    }, []);
    return state;
  }

  function Stat(props) {
    return h("div", { className: "gk-stat" },
      h("div", { className: "gk-stat-value" }, props.value),
      h("div", { className: "gk-stat-label" }, props.label));
  }

  function StateDot(props) {
    var cls = props.state === "active" ? "ok" : (props.state === "failed" ? "bad" : "warn");
    return h("span", { className: "gk-dot gk-dot-" + cls, title: props.state });
  }

  function CrewCard(props) {
    var c = props.c;
    var label = c.name === "default" ? "admin" : c.name;
    return h("div", { className: "gk-crew" },
      h("div", { className: "gk-crew-head" },
        h("div", { className: "gk-avatar" }, (label || "?").slice(0, 2).toUpperCase()),
        h("div", { className: "gk-crew-id" },
          h("div", { className: "gk-crew-name" }, label),
          h("div", { className: "gk-crew-desc" }, c.description || "Belum ada jabatan"))),
      h("div", { className: "gk-crew-meta" },
        h("span", { className: "gk-chip" + (c.telegram ? " gk-chip-ok" : "") }, c.telegram ? "Telegram ✓" : "Tanpa bot"),
        c.topics && c.topics.length ? h("span", { className: "gk-chip" }, "Topik " + c.topics.join(", ")) : null,
        h("span", { className: "gk-chip gk-chip-model", title: c.model || "" }, c.model || "model admin")));
  }

  function KantorPage() {
    var ov = useOverview();
    var d = ov.data;
    if (!d) {
      return h("div", { className: "gk-page" },
        h("div", { className: "gk-card gk-loading" }, ov.error ? "Gagal memuat data kantor: " + ov.error : "Memuat data kantor..."));
    }
    var active = d.services.filter(function (s) { return s.state === "active"; }).length;
    var ruang = linkFor(d.links.ruang, d.links.ruang_port);
    var portal = linkFor(d.links.portal, d.links.portal_port);
    var staff = d.crew.filter(function (c) { return c.name !== "default"; }).length;

    return h("div", { className: "gk-page" },
      h("section", { className: "gk-hero" },
        h("div", { className: "gk-hero-left" },
          d.logo ? h("img", { src: d.logo, alt: d.office, className: "gk-client-logo" }) : h(GncMark, { size: 56 }),
          h("div", null,
            h("div", { className: "gk-eyebrow" }, "Kantor AI"),
            h("h1", { className: "gk-title" }, d.office),
            h("div", { className: "gk-sub" },
              "GNC Kantor AI" + (d.version ? " v" + d.version : "") + " · dikelola " + d.brand +
              " · akses " + (d.mode === "lan" ? "LAN" : "lokal")))),
        h("div", { className: "gk-actions" },
          ruang ? h("a", { className: "gk-btn gk-btn-primary", href: ruang, target: "_blank", rel: "noopener" }, "Buka Kantor 3D") : null,
          portal ? h("a", { className: "gk-btn", href: portal, target: "_blank", rel: "noopener" }, "Portal kantor") : null)),

      h("section", { className: "gk-stats" },
        h(Stat, { value: String(staff), label: "Karyawan AI" }),
        h(Stat, { value: active + "/" + d.services.length, label: "Layanan aktif" }),
        h(Stat, { value: pct(d.host.disk_pct), label: "Disk terpakai" }),
        h(Stat, { value: pct(d.host.mem_pct), label: "RAM terpakai" }),
        h(Stat, { value: uptime(d.host.uptime_s), label: "Uptime " + d.host.hostname })),

      h("section", { className: "gk-grid" },
        h("div", { className: "gk-card gk-span-2" },
          h("div", { className: "gk-card-title" }, "Karyawan AI"),
          staff === 0 ? h("div", { className: "gk-empty" },
            "Belum ada karyawan. Tambahkan dari terminal server: ",
            h("code", null, "kantorai"), " → Karyawan AI → Tambah karyawan.") : null,
          h("div", { className: "gk-crew-grid" }, d.crew.map(function (c) { return h(CrewCard, { key: c.name, c: c }); }))),
        h("div", { className: "gk-card" },
          h("div", { className: "gk-card-title" }, "Layanan"),
          h("ul", { className: "gk-svc" }, d.services.map(function (s) {
            return h("li", { key: s.unit },
              h(StateDot, { state: s.state }),
              h("span", { className: "gk-svc-label" }, s.label),
              h("span", { className: "gk-svc-state" }, STATE_LABEL[s.state] || s.state));
          })),
          h("div", { className: "gk-note" },
            d.pengawas_at ? "Pengawas terakhir memeriksa: " + new Date(d.pengawas_at).toLocaleString("id-ID") : "Pengawas belum berjalan.",
            h("br"), "Telegram grup kantor: " + (d.telegram_group ? "terhubung" : "belum diatur")))),

      h("footer", { className: "gk-foot" },
        h(GncMark, { size: 18 }),
        h("span", null, "GNC Kantor AI · Galura Nexa Core — Technology Infrastructure")));
  }

  function HeaderCrest() {
    return h("span", { className: "gk-crest", title: "GNC Kantor AI" }, h(GncMark, { size: 22 }), h("span", { className: "gk-crest-text" }, "GNC"));
  }

  function FooterBrand() {
    return h("span", { className: "gk-footer-brand" }, "GNC Kantor AI · Galura Nexa Core");
  }

  REG.register(NAME, KantorPage);
  REG.registerSlot(NAME, "header-left", HeaderCrest);
  REG.registerSlot(NAME, "footer-right", FooterBrand);
})();
