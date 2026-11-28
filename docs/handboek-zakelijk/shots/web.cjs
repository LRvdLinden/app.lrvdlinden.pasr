// Schermafbeeldingen van het webdashboard en de publieke pagina's voor het handboek.
// Rendert de echte code uit website/ (zakelijk.js, loyalty2.js, tickets-klantenkaart.js, …) in Chromium; alleen de server is
// nagebootst (shots/mock.cjs). Alle namen en cijfers zijn verzonnen.
//   node docs/handboek-zakelijk/shots/web.cjs [filter]      → PNG's in docs/handboek-zakelijk/build/raw/
const { chromium } = require("playwright");
const fs = require("node:fs");
const path = require("node:path");
const mock = require("./mock.cjs");

const HERE = path.resolve(__dirname, "..");
const SITE = path.resolve(HERE, "..", "..", "website");
const OUT = path.join(HERE, "build", "raw");
const ORIGIN = "https://pasr.test";
const only = process.argv[2] || "";
fs.mkdirSync(OUT, { recursive: true });

const TYPES = { ".html": "text/html; charset=utf-8", ".js": "application/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png",
  ".jpg": "image/jpeg", ".json": "application/json", ".woff2": "font/woff2", ".webmanifest": "application/manifest+json", ".gif": "image/gif" };
const FONTS = `
@font-face{font-family:"Bricolage Grotesque";font-weight:600;src:url(/__fonts/bricolage-grotesque-latin-600-normal.woff2) format("woff2")}
@font-face{font-family:"Bricolage Grotesque";font-weight:700;src:url(/__fonts/bricolage-grotesque-latin-700-normal.woff2) format("woff2")}
@font-face{font-family:"Bricolage Grotesque";font-weight:800;src:url(/__fonts/bricolage-grotesque-latin-800-normal.woff2) format("woff2")}
${[400, 500, 600, 700, 800].map((w) => `@font-face{font-family:"Figtree";font-weight:${w};src:url(/__fonts/figtree-latin-${w}-normal.woff2) format("woff2")}`).join("\n")}
*{caret-color:transparent!important} .zk-toast{display:none!important} #pasr-cookie-btn{display:none!important} img[src*="marketingtools"]{visibility:hidden}`;

function fileFor(p) {
  if (p.startsWith("/__fonts/")) return path.join(HERE, "fonts", path.basename(p));
  let f = path.join(SITE, decodeURIComponent(p));
  if (/\/add\/e\//.test(p)) f = path.join(SITE, "aanmelden", "index.html");
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, "index.html");
  return f;
}

async function open(browser, url, o = {}) {
  const ctx = await browser.newContext({ viewport: { width: o.w || 1440, height: o.h || 900 }, deviceScaleFactor: 2, locale: "nl-NL", timezoneId: "Europe/Amsterdam",
    colorScheme: "light", reducedMotion: "reduce" });
  const page = await ctx.newPage();
  await page.clock.setFixedTime(new Date(mock.NOW));
  page.on("pageerror", (e) => console.log("  PAGEERROR", o.name, e.message));
  await page.route("**/*", async (route) => {
    const u = new URL(route.request().url());
    if (u.hostname === "demo.supabase.test") {
      let body = null; try { body = JSON.parse(route.request().postData() || "null"); } catch (e) { /* */ }
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mock.respond(u.pathname, body, o.variant, o.opts)) });
    }
    if (u.origin !== ORIGIN) return route.fulfill({ status: 204, body: "" });   // geen echte netwerkverzoeken (Google Fonts, PDOK, App Store-badge)
    if (u.pathname === "/assets/account-config.js") return route.fulfill({ status: 200, contentType: TYPES[".js"], body: 'window.PASR_ACCOUNT={url:"https://demo.supabase.test",key:"demo"};' });
    const f = fileFor(u.pathname);
    if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: "" });
    return route.fulfill({ status: 200, contentType: TYPES[path.extname(f)] || "application/octet-stream", body: fs.readFileSync(f) });
  });
  await page.addInitScript(({ css, session, first }) => {
    try {
      localStorage.setItem("pasr_consent", JSON.stringify({ choice: "necessary", at: new Date().toISOString(), v: 1 }));
      if (session) localStorage.setItem("pasr.zakelijk.session", JSON.stringify({ access_token: "demo", refresh_token: "demo", expires_at: Date.now() + 9e6, email: session, first_name: first }));
      else localStorage.removeItem("pasr.zakelijk.session");
    } catch (e) { /* */ }
    document.addEventListener("DOMContentLoaded", () => { const s = document.createElement("style"); s.textContent = css; document.head.appendChild(s); });
  }, { css: FONTS, session: o.session === false ? null : (o.variant === "staff" ? "daan@jouwzaak.nl" : "marieke@jouwzaak.nl"), first: o.variant === "staff" ? "Daan" : "Marieke" });
  await page.goto(ORIGIN + url);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(o.wait || 900);
  return { ctx, page };
}

async function snap(page, name, o) {
  const file = path.join(OUT, name + ".png");
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(250);
  if (o.el) {
    // element met een rand eromheen; de werkbalk en zijbalk staan stil zodat ze niet over een lang element heen vallen
    await page.addStyleTag({ content: ".zd3-top,.zd3-sidein{position:static!important}" });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(150);
    const bb = await page.locator(o.el).first().boundingBox();
    const pad = o.pad == null ? 16 : o.pad;
    await page.screenshot({ path: file, fullPage: true, clip: { x: Math.max(0, bb.x - pad), y: Math.max(0, bb.y - pad), width: bb.width + 2 * pad, height: Math.min(bb.height + 2 * pad, o.maxH || 1e5) } });
  } else if (o.clip) {
    await page.screenshot({ path: file, clip: o.clip, fullPage: true });
  } else await page.screenshot({ path: file, fullPage: !!o.full });
  console.log("  " + name);
}

const D = "/zakelijk/dashboard/";
const click = (sel) => async (p) => { await p.locator(sel).first().click(); await p.waitForTimeout(700); };
const fill = (pairs) => async (p) => { for (const [s, v] of pairs) await p.locator(s).first().fill(v); };
const typeScan = (code) => async (p) => { await p.fill("#sCode", code); await p.click("#sManual button[type=submit]"); await p.waitForTimeout(900); };

// [naam, url, opties]; opties: variant, w/h, session:false, setup(page), el/clip/full, opts (mock)
const SHOTS = [
  ["web-zakelijk-home", "/zakelijk/", { session: false, h: 900, clip: { x: 0, y: 0, width: 1440, height: 745 } }],
  ["web-zakelijk-faq", "/zakelijk/#faq", { session: false, h: 900, setup: async (p) => { await p.locator("#faq").scrollIntoViewIfNeeded(); await p.waitForTimeout(300); }, el: "#faq" }],
  ["web-inloggen", D, { session: false, h: 760 }],
  ["web-aanmelden-account", D + "#account", { session: false, h: 820 }],
  ["web-zaak-aanmelden", D, { variant: "new", h: 900 }],
  ["web-wacht-op-goedkeuring", D + "#stempelkaarten", { variant: "pending", h: 640 }],
  ["web-vandaag", D + "#vandaag", { h: 1060 }],
  ["web-vandaag-acties", D + "#vandaag", { h: 1400, wait: 1400, el: ".zd3-grid" }],
  ["web-zaakkiezer", D + "#vandaag", { h: 560, setup: click("#zdBizBtn"), clip: { x: 0, y: 0, width: 900, height: 420 } }],
  ["web-meldingen", D + "#vandaag", { h: 700, setup: async (p) => { await p.waitForTimeout(600); await click("#zdBell")(p); }, clip: { x: 640, y: 0, width: 800, height: 640 } }],
  ["web-accountmenu", D + "#vandaag", { h: 600, setup: async (p) => { await p.waitForTimeout(400); await click("#zdMe")(p); }, clip: { x: 1040, y: 0, width: 400, height: 420 } }],
  ["web-nieuw-maken", D + "#vandaag", { h: 820, setup: click("#tdNew"), el: ".zk-modal [role=dialog]", pad: 0 }],
  ["web-stempelkaarten", D + "#stempelkaarten", { el: "#zd-panel" }],
  ["web-stempelkaart-bewerken", D + "#stempelkaarten", { setup: async (p) => { await click('.zk-card[data-id] button[data-act="edit"]')(p); await click('#cDemo [data-n="half"]')(p); }, el: "#zd-panel" }],
  ["web-qr-link", D + "#stempelkaarten", { setup: click('.zk-card button[data-act="share"]'), el: ".zk-modal [role=dialog]", pad: 0 }],
  ["web-leden", D + "#stempelkaarten", { setup: click('.zk-card button[data-act="members"]'), el: "#zd-panel" }],
  ["web-knop-website", D + "#stempelkaarten", { h: 1000, setup: async (p) => { await p.waitForTimeout(600); await click(".pz-badge-btn")(p); }, el: "dialog.pz-badge-dlg[open]", pad: 0 }],
  ["web-beloningen", D + "#beloningen", { el: "#zd-panel", wait: 1300, maxH: 1150 }],
  ["web-klantenkaarten", D + "#klantenkaarten", { el: "#zd-panel" }],
  ["web-klantenkaart-bewerken", D + "#klantenkaarten", { h: 1000, setup: click(".mc-item [data-e]"), el: "#zd-panel" }],
  ["web-tickets", D + "#tickets", { el: "#zd-panel" }],
  ["web-event-maken", D + "#tickets", { h: 1000, setup: async (p) => { await click("#tkNew")(p); await fill([["#tkForm [name=name]", "Winterborrel"], ["#tkForm [name=address]", "Hoofdstraat 12, 7311 AB Apeldoorn"], ["#tkForm [name=capacity]", "120"], ["#tkForm [name=description]", "Glühwein, warme chocolademelk en ons nieuwe winterbrood."]])(p); await p.locator("#tkForm [name=name]").dispatchEvent("input"); await p.waitForTimeout(400); }, el: "#zd-panel" }],
  ["web-event-detail", D + "#tickets", { h: 1000, setup: click(".tk-evbtn"), el: "#zd-panel" }],
  ["web-kortingsbonnen", D + "#kortingsbonnen", { el: "#zd-panel", wait: 1300 }],
  ["web-actiecodes", D + "#actiecodes", { el: "#zd-panel", wait: 1200 }],
  ["web-gezamenlijke-acties", D + "#gezamenlijke-acties", { el: "#zd-panel", wait: 1300 }],
  ["web-gezamenlijke-beheer", D + "#gezamenlijke-acties", { wait: 1300, setup: async (p) => { await click("[data-manage]")(p); await p.fill("[data-search] input", "Apeldoorn"); await p.click("[data-search] button"); await p.waitForTimeout(800); }, el: "article.pz2-planned[data-id]", maxH: 1500 }],
  ["web-uitnodiging-actie", "/zakelijk/uitnodiging/?t=" + "a".repeat(64), { session: false, h: 900 }],
  ["web-scannen", D + "#scannen", { el: "#zd-panel" }],
  ["web-scan-stempelkaart", D + "#scannen", { h: 1100, setup: typeScan("PZ7HKD2M9XQ37Q4K"), el: "#zd-panel" }],
  ["web-scan-beloning", D + "#scannen", { h: 1100, opts: { full: true }, setup: typeScan("PZ7HKD2M9XQ37R5V"), el: "#sResult" }],
  ["web-scan-ticket-geldig", D + "#scannen", { opts: { ticket: "valid" }, setup: typeScan("K7Q2MXDATRZ5VWUY3ST2HJBN"), el: "#sResult" }],
  ["web-scan-ticket-gebruikt", D + "#scannen", { opts: { ticket: "used" }, setup: typeScan("B7Q2MXDATRZ5VWUY3ST2HJBN"), el: "#sResult" }],
  ["web-scan-klantenkaart", D + "#scannen", { setup: typeScan("KS-000124"), el: "#sResult" }],
  ["web-scan-kortingsbon", D + "#scannen", { setup: typeScan("PC7HKD2M9XQ37Q4KA2B3C4D5"), el: "#sResult" }],
  ["web-inzichten", D + "#inzichten", { el: "#zd-panel", wait: 1400 }],
  ["web-marketing", D + "#marketing", { el: "#zd-panel", wait: 1200 }],
  ["web-promotiemateriaal", D + "#promotiemateriaal", { h: 1100, wait: 1200, setup: async (p) => { await p.selectOption("#zkPromoProduct", "0"); await p.waitForTimeout(1800); }, el: "#zd-panel" }],
  ["web-vestigingen", D + "#vestigingen", { el: "#zd-panel", wait: 1200 }],
  ["web-medewerkers", D + "#medewerkers", { setup: async (p) => { await p.fill("#stName", "Joris"); await p.click("#stInv button[type=submit]"); await p.waitForTimeout(900); }, el: "#zd-panel" }],
  ["web-medewerker-scanner", D, { variant: "staff", h: 900 }],
  ["web-instellingen", D + "#instellingen", { el: "#zd-panel" }],
  ["web-account", D + "#mijn-account", { el: "#zd-panel" }],
  ["web-logboek", D + "#vandaag", { setup: async (p) => { await p.waitForTimeout(500); await click("#lgAll")(p); }, el: "#zd-panel" }],
  ["web-prullenbak", D + "#prullenbak", { el: "#zd-panel", wait: 1100 }],
  ["mob-vandaag", D + "#vandaag", { w: 390, h: 844 }],
  ["mob-acties", D + "#alle-acties", { w: 390, h: 844, wait: 1200 }],
  ["mob-meer", D + "#meer", { w: 390, h: 844 }],
  ["mob-scan-ticket", D + "#scannen", { w: 390, h: 844, opts: { ticket: "valid" }, setup: async (p) => { await typeScan("K7Q2MXDATRZ5VWUY3ST2HJBN")(p); await p.evaluate(() => window.scrollTo(0, 0)); } , full: true }],
  ["web-aanmeldpagina", "/add/e/" + mock.EV1, { session: false, w: 1280, h: 900, full: true }],
  ["mob-aanmeldpagina", "/add/e/" + mock.EV1, { session: false, w: 390, h: 844 }],
];

(async () => {
  const browser = await chromium.launch({ args: ["--lang=nl-NL"] });
  for (const [name, url, o] of SHOTS) {
    if (only && !name.includes(only)) continue;
    o.name = name;
    const { ctx, page } = await open(browser, url, o);
    try {
      if (o.setup) await o.setup(page);
      await snap(page, name, o);
    } catch (e) { console.log("  FOUT", name, e.message.split("\n")[0]); }
    await ctx.close();
  }
  await browser.close();
})();
