// UI-test van "Zaak verwijderen" in Pasr Beheer (tab Ondernemers). Draait beheer/web/ lokaal met een mock van de functie
// admin (acties businesses, business_detail, business_delete_preview, business_delete) in Chromium (Playwright).
//   node tools/tests/beheer-zaak-verwijderen/delete-ui.test.js [--shots <map>]
// Vereist: `npm i playwright` (of een globale installatie) met Chromium. Geen netwerk, geen echte gegevens.
"use strict";
const http = require("http"), fs = require("fs"), path = require("path");
const { chromium } = require("playwright");

const WEB = path.resolve(__dirname, "../../../beheer/web");
const shotsDir = process.argv.includes("--shots") ? path.resolve(process.argv[process.argv.indexOf("--shots") + 1]) : null;
if (shotsDir) fs.mkdirSync(shotsDir, { recursive: true });
let failed = 0;
const ok = (c, m) => { if (c) console.log("PASS:", m); else { failed++; console.log("FAIL:", m); } };

const A = "aaaaaaaa-0000-4000-8000-000000000001", B = "bbbbbbbb-0000-4000-8000-000000000002";
const NAME = 'Bakkerij "De Gouden" & Zn';
let zaken = [
  { id: A, name: NAME, city: "Apeldoorn", status: "approved", email: "eigenaar@voorbeeld.example", has_owner: true, staff_count: 2, listed: true, created_at: new Date().toISOString(), cards: [] },
  { id: B, name: "Fietsenmaker Wiel", city: "Deventer", status: "blocked", email: "wiel@voorbeeld.example", has_owner: true, staff_count: 0, listed: true, created_at: new Date().toISOString(), cards: [] },
];
const counts = { cards: 2, members: 14, staff: 1, events: 3, upcoming_events: 1, tickets: 20, member_cards: 1, member_card_members: 5, campaigns: 1, participations: 2, offers: 4, log: 120 };
const calls = [];
let failDeleteOnce = false;
function handle(action, b) {
  calls.push({ action, b });
  switch (action) {
    case "businesses": return { businesses: zaken };
    case "business_detail": { const z = zaken.find((x) => x.id === b.id); return { business: z, staff: [], log: [], stats: { days: [], totals: {} } }; }
    case "business_delete_preview": { const z = zaken.find((x) => x.id === b.id); return z ? { id: z.id, name: z.name, status: z.status, counts: z.id === A ? counts : { cards: 0, members: 0, staff: 0, events: 0, upcoming_events: 0, tickets: 0, member_cards: 0, member_card_members: 0, campaigns: 0, participations: 0, offers: 0, log: 0 } } : { __status: 404, error: "not_found" }; }
    case "business_delete": {
      const z = zaken.find((x) => x.id === b.id);
      if (!z) return { __status: 404, error: "not_found" };
      if (failDeleteOnce) { failDeleteOnce = false; return { __status: 500, error: "server_error" }; }
      if (b.confirm !== z.name) return { __status: 400, error: "confirm_mismatch" };
      zaken = zaken.filter((x) => x.id !== b.id);
      return { deleted: true, id: z.id, name: z.name, counts, campaigns_cancelled: z.id === A ? 1 : 0 };
    }
    default: return {};
  }
}

(async () => {
  const server = http.createServer((req, res) => {
    const f = path.join(WEB, req.url.split("?")[0] === "/" ? "index.html" : decodeURIComponent(req.url.split("?")[0]));
    if (!f.startsWith(WEB) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".json": "application/json" };
    res.writeHead(200, { "content-type": types[path.extname(f)] || "application/octet-stream" }); fs.createReadStream(f).pipe(res);
  }).listen(0);
  const base = "http://127.0.0.1:" + server.address().port + "/";
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: "dark", locale: "nl-NL" });
  await ctx.addInitScript(() => { try { sessionStorage.setItem("pasr.beheer.token", "t"); sessionStorage.setItem("pasr.beheer.exp", String(Date.now() + 3600e3)); } catch { /* sandbox */ } });
  await ctx.route("**/config.js", (r) => r.fulfill({ contentType: "text/javascript", body: 'window.BEHEER={url:"https://mock.supabase.co",key:"k"};' }));
  await ctx.route("https://mock.supabase.co/functions/v1/admin", async (route) => {
    const { action, ...rest } = JSON.parse(route.request().postData() || "{}");
    const out = handle(action, rest);
    const status = out && out.__status ? out.__status : 200;
    if (out && out.__status) delete out.__status;
    route.fulfill({ status, contentType: "application/json", body: JSON.stringify(out) });
  });
  const page = await ctx.newPage();
  const logs = []; page.on("pageerror", (e) => logs.push("pageerror " + e.message));
  let dialogs = 0; page.on("dialog", (d) => { dialogs++; d.dismiss(); });
  const shot = async (n) => { if (shotsDir) { await page.waitForTimeout(150); await page.screenshot({ path: path.join(shotsDir, n + ".png") }); } };
  const last = (a) => [...calls].reverse().find((c) => c.action === a);
  const count = (a) => calls.filter((c) => c.action === a).length;

  await page.goto(base + "#business");
  await page.waitForSelector("#view-business:not(.hidden)");
  await page.click('#bizFilter button[data-status="all"]');
  await page.waitForFunction(() => document.querySelectorAll("#bizList .acc").length === 2);

  // details openen: gevaarlijke zone onderaan met rode knop
  await page.click('#bizList .acc:has-text("De Gouden") button:has-text("Details")');
  await page.waitForSelector(".biz-danger");
  const btn = page.locator('.biz-danger button:has-text("Verwijderen…")');
  ok(await btn.isVisible(), "gevaarlijke zone toont de knop 'Verwijderen…'");
  ok(await page.evaluate(() => { const b = [...document.querySelectorAll(".biz-danger button")][0]; return getComputedStyle(b).backgroundColor !== "rgba(0, 0, 0, 0)" && b.classList.contains("danger"); }), "de knop is rood (danger)");
  ok((await page.locator('#bizList .acc:has-text("De Gouden") button:has-text("Blokkeren")').count()) === 1, "Blokkeren blijft naast de andere acties staan");
  await shot("1-gevaarlijke-zone");

  // venster: aantallen, waarschuwingen, knop pas actief na vinkje en exacte naam
  await btn.click();
  await page.waitForSelector("#bizDel:not(.hidden) #bdList li");
  ok(last("business_delete_preview").b.id === A, "preview wordt opgehaald voor de zaak");
  const text = await page.locator("#bizDel").innerText();
  ok(/2 stempelkaarten met 14 leden/.test(text), "toont stempelkaarten en leden");
  ok(/3 events met 20 tickets, inclusief de gegevens van de aanmeldingen/.test(text), "toont events, tickets en dat aanmeldgegevens verdwijnen");
  ok(/1 medewerker/.test(text) && /1 klantenkaart met 5 leden/.test(text) && /4 kortingsbonnen en actiecodes/.test(text), "toont medewerkers, klantenkaarten, aanbiedingen");
  ok(/1 gezamenlijke actie van deze zaak \(wordt geannuleerd/.test(text) && /deelname aan 2 acties van andere zaken/.test(text), "toont gezamenlijke acties");
  ok(/1 aankomend event open/.test(text), "waarschuwt voor aankomende events");
  ok(/De eigenaar krijgt geen e-mail/.test(text), "zegt dat de eigenaar geen mail krijgt");
  ok(/nog goedgekeurd en wordt direct geblokkeerd/.test(text), "goedgekeurde zaak wordt eerst geblokkeerd, dat staat erbij");
  ok(await page.locator("#bdOk").isDisabled(), "knop uit zonder bevestiging");
  await page.check("#bdAck");
  ok(await page.locator("#bdOk").isDisabled(), "knop uit zonder naam");
  await page.fill("#bdInput", NAME.toLowerCase());
  ok(await page.locator("#bdOk").isDisabled(), "knop uit bij verkeerde hoofdletters");
  await page.fill("#bdInput", NAME + " ");
  ok(await page.locator("#bdOk").isDisabled(), "knop uit bij extra spatie");
  await shot("2-bevestigingsvenster-leeg");
  await page.fill("#bdInput", NAME);
  ok(await page.locator("#bdOk").isEnabled(), "knop aan bij vinkje en exacte naam");
  await page.uncheck("#bdAck");
  ok(await page.locator("#bdOk").isDisabled(), "vinkje weghalen zet de knop weer uit");
  await page.check("#bdAck");
  ok(count("business_delete") === 0, "tot nu toe is er niets verwijderd");
  await shot("3-bevestigingsvenster-klaar");

  // Annuleren en Escape verwijderen niets
  await page.click("#bdCancel");
  ok(await page.locator("#bizDel").isHidden() && count("business_delete") === 0, "Annuleren sluit zonder te verwijderen");
  await btn.click(); await page.waitForSelector("#bizDel:not(.hidden) #bdList li");
  ok((await page.inputValue("#bdInput")) === "" && !(await page.isChecked("#bdAck")), "venster start schoon bij opnieuw openen");
  await page.keyboard.press("Escape");
  ok(await page.locator("#bizDel").isHidden() && count("business_delete") === 0, "Escape sluit zonder te verwijderen");

  // serverfout: venster blijft open, melding, geen verdwenen zaak
  failDeleteOnce = true;
  await btn.click(); await page.waitForSelector("#bizDel:not(.hidden) #bdList li");
  await page.check("#bdAck"); await page.fill("#bdInput", NAME);
  await page.click("#bdOk");
  await page.waitForFunction(() => document.getElementById("bdErr").textContent.length > 0);
  ok(await page.locator("#bizDel").isVisible() && (await page.locator("#bdOk").isEnabled()), "bij een serverfout blijft het venster open en kan je opnieuw proberen");
  await shot("4-fout");

  // verwijderen
  await page.click("#bdOk");
  await page.waitForFunction(() => document.querySelectorAll("#bizList .acc").length === 1);
  const del = last("business_delete");
  ok(del.b.id === A && del.b.confirm === NAME, "business_delete krijgt id en de overgetypte naam");
  ok(await page.locator("#bizDel").isHidden(), "venster sluit na succes");
  ok((await page.locator("#bizList").innerText()).includes("Fietsenmaker Wiel") && !(await page.locator("#bizList").innerText()).includes("De Gouden"), "terug naar de lijst zonder de verwijderde zaak, andere zaak blijft");
  ok(/is verwijderd, 1 gezamenlijke actie geannuleerd/.test(await page.locator("#toast").innerText()), "toast meldt het resultaat en de geannuleerde actie");
  ok(!(await page.locator(".biz-danger").count()), "details van de verwijderde zaak zijn weg");

  // geblokkeerde zaak zonder inhoud: korte lijst, geen waarschuwing voor events
  await page.click('#bizList .acc:has-text("Fietsenmaker") button:has-text("Details")');
  await page.waitForSelector(".biz-danger");
  await page.click('.biz-danger button:has-text("Verwijderen…")');
  await page.waitForSelector("#bizDel:not(.hidden) #bdList li");
  const t2 = await page.locator("#bizDel").innerText();
  ok(/er hangt verder niets aan/.test(t2) && !/aankomend event/.test(t2) && !/nog goedgekeurd/.test(t2), "lege geblokkeerde zaak: geen overbodige waarschuwingen");
  await page.fill("#bdInput", "Fietsenmaker Wiel"); await page.check("#bdAck");
  await page.keyboard.press("Enter");
  await page.waitForFunction(() => document.querySelectorAll("#bizList .acc").length === 0);
  ok(count("business_delete") === 3, "Enter in het veld verstuurt ook (na de zelfde controles)");

  // mobiel: geen horizontale scroll in het venster
  zaken = [{ ...zaken[0] || { id: A, name: NAME, city: "Apeldoorn", status: "approved", has_owner: true, staff_count: 0, listed: true, created_at: new Date().toISOString(), cards: [] }, id: A, name: NAME, status: "approved" }];
  await page.setViewportSize({ width: 390, height: 844 });
  await page.reload(); await page.waitForSelector("#view-business:not(.hidden)");
  await page.click('#bizFilter button[data-status="all"]');
  await page.waitForSelector("#bizList .acc");
  await page.click('#bizList .acc button:has-text("Details")'); await page.waitForSelector(".biz-danger");
  await page.click('.biz-danger button:has-text("Verwijderen…")'); await page.waitForSelector("#bizDel:not(.hidden) #bdList li");
  ok(!(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1)), "geen horizontale scroll (mobiel)");
  await shot("5-mobiel");
  ok(dialogs === 0, "geen browserdialogen");
  ok(logs.length === 0, "geen scriptfouten: " + logs.join("; "));
  await browser.close(); server.close();
  console.log(failed ? `\n${failed} test(s) mislukt` : "\nAlle tests geslaagd");
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
