// Render plugin Panel Hermes GNC dengan React tiruan dan data dari overview() (uji/uji_kantorai.sh).
const fs = require("fs");
const repo = process.argv[2];
const data = JSON.parse(fs.readFileSync(process.env.API_JSON, "utf8"));
function render(node) {
  if (node == null || node === false) return "";
  if (typeof node !== "object") return String(node);
  if (Array.isArray(node)) return node.map(render).join("");
  if (typeof node.type === "function") return render(node.type(node.props || {}));
  const attrs = node.props && node.props.href ? ' href="' + node.props.href + '"' : "";
  return "<" + node.type + attrs + ">" + node.children.map(render).join("") + "</" + node.type + ">";
}
const registered = {}, slots = {};
global.window = {
  location: { protocol: "http:", hostname: "10.0.0.5" },
  __HERMES_PLUGINS__: { register: (n, c) => (registered[n] = c), registerSlot: (p, s, c) => (slots[s] = c) },
  __HERMES_PLUGIN_SDK__: {
    React: { createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat() }) },
    hooks: { useState: () => [{ data, error: null }, () => {}], useEffect: () => {} },
    fetchJSON: () => Promise.resolve(data),
  },
};
eval(fs.readFileSync(repo + "/assets/dashboard/plugin/gnc-kantor/dashboard/dist/index.js", "utf8"));
if (!registered["gnc-kantor"]) throw new Error("tab tidak terdaftar");
const html = render({ type: registered["gnc-kantor"], props: {}, children: [] });
for (const s of [data.office, "sekretaris", "Buka Kantor 3D", 'href="http://10.0.0.5:3001"', "Topik 77", "Telegram ✓"]) {
  if (!html.includes(s)) throw new Error("tidak ditemukan di render: " + s);
}
if (!slots["header-left"] || !slots["footer-right"]) throw new Error("slot belum terdaftar");
render({ type: slots["header-left"], props: {}, children: [] });
render({ type: slots["footer-right"], props: {}, children: [] });
console.log("RENDER-OK");
