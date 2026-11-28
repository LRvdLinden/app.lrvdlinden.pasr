// Test: pasr.nl/zakelijk/dashboard/#beheer=<sleutel> opent het dashboard namens een ondernemer, in dit tabblad alleen (sessionStorage).
//   node tools/tests/beheer-namens-ondernemer/impersonate.test.js   (vereist playwright + Chromium; geen netwerk, mock-server)
"use strict";
const http = require("http"), fs = require("fs"), path = require("path");
const { chromium } = require("playwright");
const WEB = path.resolve(__dirname, "../../../website");
let failed = 0; const ok = (c, m) => { if (c) console.log("PASS:", m); else { failed++; console.log("FAIL:", m); } };
(async () => {
  const server = http.createServer((q, r) => {
    let u = decodeURIComponent(q.url.split("?")[0]); let f = path.join(WEB, u); if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, "index.html");
    if (!f.startsWith(WEB) || !fs.existsSync(f)) { r.writeHead(404); return r.end(); }
    const t = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".svg": "image/svg+xml" }[path.extname(f)] || "application/octet-stream";
    r.writeHead(200, { "content-type": t }); fs.createReadStream(f).pipe(r);
  }).listen(0);
  const base = "http://127.0.0.1:" + server.address().port;
  const b = await chromium.launch(); const ctx = await b.newContext({ viewport: { width: 1280, height: 900 } });
  await ctx.route("**/assets/account-config.js", (r) => r.fulfill({ contentType: "text/javascript", body: 'window.PASR_ACCOUNT={url:"https://mock.supabase.co",key:"k"};' }));
  const calls = [];
  await ctx.route("https://mock.supabase.co/**", async (r) => {
    const u = r.request().url(); calls.push(u);
    const j = (o, s = 200) => r.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(o) });
    if (u.includes("/auth/v1/verify")) { const body = JSON.parse(r.request().postData()); return body.token_hash === "GOEDEsleutelGOEDEsleutel1" ? j({ access_token: "a", refresh_token: "r", expires_in: 3600, user: { email: "eigenaar@example.test" } }) : j({ msg: "expired" }, 403); }
    if (u.includes("/auth/v1/logout")) return j({});
    if (u.includes("pasr_business_me")) return j({ businesses: [{ id: "11111111-1111-1111-1111-111111111111", name: "Bakkerij Bos", city: "Apeldoorn", role: "owner", status: "approved", cards: [] }] });
    return j([]);
  });
  const page = await ctx.newPage(); const errs = []; page.on("pageerror", (e) => errs.push(e.message));
  await page.addInitScript(() => { if (!sessionStorage.getItem("seeded")) { localStorage.setItem("pasr.zakelijk.session", JSON.stringify({ access_token: "EIGEN", refresh_token: "EIGEN", expires_at: Date.now() + 36e5, email: "ik@example.test" })); sessionStorage.setItem("seeded", "1"); } });
  await page.goto(base + "/zakelijk/dashboard/#beheer=GOEDEsleutelGOEDEsleutel1");
  await page.waitForSelector(".zd-imp", { timeout: 8000 }).catch(() => {});
  ok(await page.locator(".zd-imp").count() === 1, "balk 'namens' zichtbaar");
  ok((await page.locator(".zd-imp").innerText()).includes("Bakkerij Bos"), "balk noemt de zaak");
  ok(!page.url().includes("beheer="), "sleutel staat niet meer in de adresbalk");
  const own = await page.evaluate(() => ({ l: JSON.parse(localStorage.getItem("pasr.zakelijk.session")).access_token, s: !!sessionStorage.getItem("pasr.zakelijk.session") }));
  ok(own.l === "EIGEN" && own.s, "eigen sessie in localStorage onaangetast; sessie namens de ondernemer in sessionStorage");
  await page.click("#zdImpStop"); await page.waitForTimeout(500);
  ok(!calls.some((u) => u.includes("/auth/v1/logout")), "stoppen logt niet uit op de server");
  ok(await page.evaluate(() => !sessionStorage.getItem("pasr.zakelijk.session") && !!localStorage.getItem("pasr.zakelijk.session")), "na stoppen: sessie namens weg, eigen sessie blijft");
  // verlopen sleutel
  const p2 = await ctx.newPage(); await p2.goto(base + "/zakelijk/dashboard/#beheer=VERLOPENsleutelVERLOPEN12"); await p2.waitForSelector("text=Link verlopen", { timeout: 8000 }).catch(() => {});
  ok(await p2.locator("text=Link verlopen").count() === 1, "verlopen sleutel geeft een duidelijke melding");
  ok(!errs.length, "geen scriptfouten" + (errs.length ? " " + errs[0] : ""));
  await b.close(); server.close(); console.log(failed ? failed + " mislukt" : "Alle tests geslaagd"); process.exit(failed ? 1 : 0);
})();
