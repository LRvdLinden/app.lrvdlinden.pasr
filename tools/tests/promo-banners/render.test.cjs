/* Rendert promo.js voor elke soort (kaart, coupon, actiecode, event) × formaat × thema in een echte browser
 * en controleert afmetingen en dat het resultaat niet leeg is. Draaien: node tools/tests/promo-banners/render.test.cjs */
const http = require("http"), fs = require("fs"), path = require("path");
let chromium; try { ({ chromium } = require("playwright")); } catch (e) { ({ chromium } = require("/opt/npm-tools/node_modules/playwright")); }
const site = path.join(__dirname, "..", "..", "..", "website");
const types = { ".js": "text/javascript", ".html": "text/html", ".png": "image/png", ".svg": "image/svg+xml", ".css": "text/css" };
const srv = http.createServer((q, r) => {
  let p = path.join(site, decodeURIComponent(q.url.split("?")[0])); if (p.endsWith("/")) p += "index.html";
  fs.readFile(p, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { "content-type": types[path.extname(p)] || "application/octet-stream" }); r.end(d); });
}).listen(0);
const cards = {
  card: { id: "demo", kind: "card", name: "Koffiekaart", business: "Bakkerij De Korenaar", city: "Apeldoorn", color: "#C2410C", stamps_total: 10, reward: "10e koffie gratis", published: true },
  concept: { id: "d2", kind: "card", name: "Lunchkaart met een erg lange naam voor de zekerheid", business: "Brasserie De Kleine Waterlelie Apeldoorn", color: "#FFE066", stamps_total: 30, reward: "Gratis lunch", published: false },
  coupon: { id: "c1", kind: "coupon", title: "Gratis gebak bij je koffie", discount_type: "percent", discount_value: 20, business: "Bakkerij De Korenaar", color: "#C2410C", ends_at: "2026-12-31" },
  code: { id: "a1", kind: "code", title: "Herfstactie: €5 korting vanaf €25", discount_type: "amount", discount_value: 5, business: "Kapsalon Studio Lux", color: "#0E7490", ends_at: "2026-12-15" },
  event: { id: "11111111-2222-3333-4444-555555555555", kind: "event", name: "Winterborrel met proeverij", business: "Brouwerij De Gouden Leeuw", address: "Marktplein 12, Apeldoorn", starts_at: "2026-12-12T19:30:00+01:00", color: "#6A5CFF", status: "published" },
  draft: { id: "e2", kind: "event", name: "Concept", business: "Zaak", address: "", starts_at: "2026-12-12T19:30:00+01:00", color: "#6A5CFF", status: "draft" },
};
(async () => {
  const b = await chromium.launch(), pg = await b.newPage(); let bad = 0, n = 0;
  pg.on("pageerror", e => { console.log("FOUT", e.message); bad++; });
  await pg.goto(`http://localhost:${srv.address().port}/zakelijk/flyer/`);
  await pg.waitForFunction("window.PasrPromo");
  const sizes = await pg.evaluate(() => PasrPromo.formats.map(f => [f.id, f.w, f.h]));
  for (const [k, c] of Object.entries(cards)) for (const [fid, w, h] of sizes) for (const t of ["light", "dark"]) {
    const r = await pg.evaluate(async ([c, f, t]) => { const cv = await PasrPromo.render(c, f, t); const d = cv.getContext("2d").getImageData(0, 0, cv.width, cv.height).data;
      const seen = new Set(); for (let i = 0; i < d.length; i += 4 * 997) seen.add(d[i] + "," + d[i + 1] + "," + d[i + 2]); return { w: cv.width, h: cv.height, colors: seen.size }; }, [c, fid, t]);
    n++; if (r.w !== w || r.h !== h || r.colors < 8) { bad++; console.log("FOUT", k, fid, t, JSON.stringify(r), "verwacht", w, h); }
  }
  await b.close(); srv.close();
  console.log(bad ? `${bad} fouten` : `OK: ${n} banners gerenderd`); process.exit(bad ? 1 : 0);
})();
