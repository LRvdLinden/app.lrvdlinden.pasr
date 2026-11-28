// UI-test van het tabblad Mail in Pasr Beheer. Draait beheer/web/ lokaal met een mock van de functie admin (acties mail_*),
// loopt de flows door in Chromium (Playwright) en maakt schermafbeeldingen.
//   node tools/tests/beheer-mail/mail-ui.test.js [--shots <map>]
// Vereist: `npm i playwright` (of een globale installatie) met Chromium. Geen netwerk, geen echte adressen.
"use strict";
const http = require("http"), fs = require("fs"), path = require("path");
const { chromium } = require("playwright");

const WEB = path.resolve(__dirname, "../../../beheer/web");
const shotsDir = process.argv.includes("--shots") ? path.resolve(process.argv[process.argv.indexOf("--shots") + 1]) : null;
if (shotsDir) fs.mkdirSync(shotsDir, { recursive: true });

let failed = 0;
const ok = (c, m) => { if (c) console.log("PASS:", m); else { failed++; console.log("FAIL:", m); } };

// ---- mock ----
const EVIL = '<div style="color:#c00"><p>Hallo, een <b>vraag</b> over mijn pas.</p><script>window.__pwned=1</script><img src="https://evil.example/pixel.gif" onerror="window.__pwned=2"><a href="javascript:alert(1)">bad</a><a href="https://pasr.nl">pasr.nl</a></div>';
const png = Buffer.alloc(2048, 7).toString("base64");
const db = {
  threads: [
    { number: 1003, subject: "Mijn pas werkt niet", status: "new", brand: "pasr", contact_name: "Sanne de Vries", contact_email: "sanne@example.test", last_message_at: new Date(Date.now() - 600e3).toISOString(), unread: true, preview: "Hallo, een vraag over mijn pas." },
    { number: 1002, subject: "Aanmelding Pasr Zakelijk", status: "open", brand: "zakelijk", contact_name: "Bakkerij Bos", contact_email: "bos@example.test", last_message_at: new Date(Date.now() - 7200e3).toISOString(), unread: false, preview: "Wij willen graag stempelkaarten." },
    { number: 1001, subject: "Bedankt", status: "closed", brand: "pasr", contact_name: "", contact_email: "pieter@example.test", last_message_at: new Date(Date.now() - 86400e3 * 3).toISOString(), unread: false, preview: "Top!" },
  ],
  campaigns: [
    { id: 2, brand: "zakelijk", audience: "owners", subject: "Kennismaken met Pasr Zakelijk", status: "sent", recipients: 48, sent: 47, failed: 1, created_at: new Date(Date.now() - 86400e3 * 5).toISOString() },
    { id: 3, brand: "pasr", audience: "users", subject: "Nieuw in Pasr", status: "sending", recipients: 1200, sent: 400, failed: 0, created_at: new Date(Date.now() - 3600e3).toISOString() },
  ],
};
const sentItems = [
  { number: 1004, subject: "Kennismaken met Pasr Zakelijk", status: "pending", brand: "pasr", contact_name: "", contact_email: "", last_message_at: new Date(Date.now() - 3600e3).toISOString(), sent_at: new Date(Date.now() - 3600e3).toISOString(), last_direction: "out", to_preview: "ontvanger@example.test", to_count: 1, cc_count: 1, bcc_count: 4, attachments: 1, error: null },
  { number: 1003, subject: "Re: Mijn pas werkt niet", status: "new", brand: "pasr", contact_name: "Sanne de Vries", contact_email: "sanne@example.test", last_message_at: new Date(Date.now() - 7200e3).toISOString(), sent_at: new Date(Date.now() - 7200e3).toISOString(), last_direction: "out", to_preview: "sanne@example.test", to_count: 1, cc_count: 0, bcc_count: 0, attachments: 0, error: "SMTP weigerde de mail" },
];
const calls = [];
function handle(action, b) {
  calls.push({ action, b });
  switch (action) {
    case "mail_status": return { smtp: true, imap: true, brands: { pasr: { from: "Pasr <support@pasr.nl>" }, zakelijk: { from: "Pasr Zakelijk <support@pasr.nl>" } }, sync: { last_run: new Date(Date.now() - 120e3).toISOString(), last_error: null, fetched: 3, imported: 1 }, counts: { new: 1, open: 1, pending: 0, closed: 1, unread: db.threads.filter((t) => t.unread).length } };
    case "mail_poll": return { ok: true, fetched: 2, imported: 1, new_threads: 1, replies: 0, ignored: 1, rejected: 0 };
    case "mail_thread_list": {
      if (b.box === "sent") { let it = sentItems; if (b.brand) it = it.filter((t) => t.brand === b.brand); if (b.q) it = it.filter((t) => (t.subject + t.to_preview).toLowerCase().includes(String(b.q).toLowerCase())); return { total: it.length, page: 0, items: it, counts: {} }; }
      let items = db.threads.filter((t) => (b.status === "active" ? t.status !== "closed" : b.status === "all" || !b.status ? true : t.status === b.status));
      if (b.brand) items = items.filter((t) => t.brand === b.brand);
      if (b.q) items = items.filter((t) => (t.subject + t.preview).toLowerCase().includes(String(b.q).toLowerCase()));
      return { total: items.length, page: b.page || 0, items, counts: { new: 1, open: 1, pending: 0, closed: 1, unread: db.threads.filter((t) => t.unread).length } };
    }
    case "mail_thread_get": {
      const t = db.threads.find((x) => x.number === b.number) || sentItems.find((x) => x.number === b.number); t.unread = false;
      if (b.number === 1004) return { thread: { ...t, priority: "normal", created_at: t.sent_at }, messages: [{ id: "s1", direction: "out", from: "Pasr Zakelijk <support@pasr.nl>", to: ["ontvanger@example.test"], cc: ["kopie@example.test"], bcc_count: 4, subject: t.subject, body_html: "<h2>Welkom</h2><p>Hoi daar, leuk dat je er bent.</p>", body_text: "Welkom", attachments: [{ id: "a2", name: "folder.pdf", type: "application/pdf", size: 307200 }], created_at: t.sent_at }] };
      return { thread: { ...t, priority: "normal", created_at: t.last_message_at }, messages: [
        { id: "m1", direction: "in", from: t.contact_email, to: ["support@pasr.nl"], cc: [], bcc_count: 0, subject: t.subject, body_html: EVIL, body_text: "Hallo, een vraag over mijn pas.", attachments: [{ id: "a1", name: "scherm.png", type: "image/png", size: 2048 }], created_at: t.last_message_at },
        { id: "m2", direction: "out", from: "Pasr <support@pasr.nl>", to: [t.contact_email], cc: [], bcc_count: 2, subject: "Re: " + t.subject, body_html: "<p>Dank voor je bericht.</p>", body_text: "Dank voor je bericht.", attachments: [], created_at: t.last_message_at },
        { id: "m3", direction: "note", from: "beheer", to: [], cc: [], bcc_count: 0, subject: "", body_html: "", body_text: "Intern: klant belt morgen.", attachments: [], created_at: t.last_message_at },
      ] };
    }
    case "mail_attachment": return { name: "scherm.png", type: "image/png", data_b64: png };
    case "mail_thread_reply": return { ok: true, status: b.status, email_sent: true, message_id: "<x@pasr.nl>" };
    case "mail_thread_status": case "mail_thread_note": return { ok: true };
    case "mail_preview": return { html: `<!doctype html><html><head><meta name="color-scheme" content="light dark"><style>body{margin:0;background:#F4F4F8}.card{background:#fff;color:#17162A;padding:24px;border-radius:16px;max-width:520px;margin:16px auto}.btn{display:inline-block;background:#6A5CFF;color:#fff;padding:10px 18px;border-radius:12px;text-decoration:none}@media (prefers-color-scheme: dark){body{background:#0F1016}.card{background:#1B1D27;color:#F2F1FA}}</style></head><body><div class="card"><p style="font-weight:700;color:#6A5CFF">${b.brand === "zakelijk" ? "Pasr voor ondernemers" : "Pasr"}</p><h1 style="font-size:22px">${String(b.subject || "Onderwerp").replace(/[<>&]/g, "")}</h1><p>${String(b.body_md || "").replace(/[<>&]/g, "").slice(0, 200)}</p><p><a class="btn" href="https://pasr.nl">Open Pasr</a></p></div>${b.signature === false ? "" : `<div class="card sig" style="padding:0;background:#15171F;color:#fff;text-align:center;font-weight:800;border-radius:12px"><p style="padding:34px 0;margin:0">${b.brand === "zakelijk" ? "Team Pasr Zakelijk" : "Team Pasr"}</p></div>`}</body></html>`, text: "Voorbeeldtekst\n" + (b.body_md || "") };
    case "mail_test": return { ok: true };
    case "mail_compose": if (b.subject === "TOOLARGE") return { __status: 413, error: "too_large", max_bytes: 20971520 }; return { ok: true, sent: 1, failed: 0, number: 1004 };
    case "mail_campaign_audience": return { count: b.audience === "owners" ? 48 : 1200 };
    case "mail_campaign_send": return { ok: true, campaign_id: 4, recipients: b.audience === "owners" ? 48 : 1200 };
    case "mail_campaign_list": return db.campaigns;
    case "mail_campaign_cancel": db.campaigns.find((c) => c.id === b.id).status = "cancelled"; return { ok: true };
    default: return null;
  }
}

(async () => {
  const server = http.createServer((req, res) => {
    const f = path.join(WEB, req.url.split("?")[0] === "/" ? "index.html" : decodeURIComponent(req.url.split("?")[0]));
    if (!f.startsWith(WEB) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    const ext = path.extname(f), types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".json": "application/json" };
    res.writeHead(200, { "content-type": types[ext] || "application/octet-stream" }); fs.createReadStream(f).pipe(res);
  }).listen(0);
  const base = "http://127.0.0.1:" + server.address().port + "/";
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, acceptDownloads: true, colorScheme: "dark", locale: "nl-NL" });
  await ctx.addInitScript(() => {
    try { sessionStorage.setItem("pasr.beheer.token", "t"); sessionStorage.setItem("pasr.beheer.exp", String(Date.now() + 3600e3)); } catch { /* sandboxed iframe */ }
    window.BEHEER = { url: "https://mock.supabase.co", key: "k" };
  });
  await ctx.route("**/config.js", (r) => r.fulfill({ contentType: "text/javascript", body: 'window.BEHEER={url:"https://mock.supabase.co",key:"k"};' }));
  await ctx.route("https://mock.supabase.co/functions/v1/admin", async (route) => {
    const body = JSON.parse(route.request().postData() || "{}"); const { action, ...rest } = body;
    const out = handle(action, rest);
    if (out && out.__status) return route.fulfill({ status: out.__status, contentType: "application/json", body: JSON.stringify({ error: out.error, max_bytes: out.max_bytes }) });
    if (out === null) return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(out) });
  });
  const page = await ctx.newPage();
  const logs = [];
  page.on("console", (m) => logs.push(m.text())); page.on("pageerror", (e) => logs.push("pageerror " + e.message));
  let dialogs = 0; page.on("dialog", (d) => { dialogs++; d.dismiss(); });
  const shot = async (n, full) => { if (shotsDir) { await page.evaluate(() => scrollTo(0, 0)); await page.waitForTimeout(150); await page.screenshot({ path: path.join(shotsDir, n + ".png"), fullPage: !!full }); } };
  const last = (a) => [...calls].reverse().find((c) => c.action === a);

  await page.goto(base + "#mail-pasr");
  await page.waitForSelector("#view-mail:not(.hidden)");
  await page.waitForSelector(".mx-item");
  ok(await page.locator("#mailBadge").innerText() === "1", "menu-badge toont 1 ongelezen");
  ok((await page.locator(".mx-item").count()) === 1, "Support-postvak toont alleen de actieve tickets van Support");
  ok(calls.some((c) => c.action === "mail_thread_list" && c.b.brand === "pasr" && c.b.box === "inbox"), "Support-postvak vraagt brand=pasr");
  ok((await page.locator("#mail-inbox .mx-status-t").innerText()).includes("IMAP"), "IMAP/SMTP-status zichtbaar");
  await shot("1-inbox-lijst");

  // filter, zoeken, ongelezen
  await page.click('.mx-filters button[data-f="all"]');
  await page.waitForFunction(() => document.querySelectorAll(".mx-item").length === 2);
  ok(last("mail_thread_list").b.status === "all", "filter Alle vraagt status=all");
  await page.fill('#mail-inbox input[type=search]', "bedankt");
  await page.waitForFunction(() => document.querySelectorAll(".mx-item").length === 1);
  ok([...calls].reverse().find((c) => c.action === "mail_thread_list" && c.b.q).b.q === "bedankt", "zoeken stuurt q");
  await page.fill('#mail-inbox input[type=search]', "");
  await page.waitForFunction(() => document.querySelectorAll(".mx-item").length === 2);
  await page.check("#mail-inbox .mx-unread input");
  ok((await page.locator(".mx-item").count()) === 1, "alleen ongelezen filtert");
  await page.uncheck("#mail-inbox .mx-unread input");
  ok(await page.locator("#mail-inbox select").isHidden(), "merkfilter is verborgen: het postvak bepaalt het merk");

  // thread openen: veilige weergave
  await page.click('.mx-item:has-text("#1003")');
  await page.waitForSelector(".mx-msg");
  ok((await page.locator(".mx-msg").count()) === 3, "thread toont ontvangen, verstuurd en notitie");
  const sb = await page.locator("iframe.mx-frame").first().getAttribute("sandbox");
  ok(sb !== null && !/allow-scripts|allow-same-origin/.test(sb), "mail-HTML staat in sandboxed iframe zonder scripts");
  const srcdoc = await page.locator("iframe.mx-frame").first().getAttribute("srcdoc");
  ok(!/<script|onerror|javascript:|evil\.example/i.test(srcdoc), "srcdoc bevat geen script, handlers, javascript:-links of externe afbeeldingen");
  await page.waitForTimeout(300);
  ok((await page.evaluate(() => window.__pwned)) === undefined, "script uit de mail is niet uitgevoerd");
  ok((await page.locator(".mx-msg.out .mx-addrs").innerText()).includes("2 ontvangers"), "BCC toont alleen het aantal");
  await page.click('.mx-view-seg button:has-text("Tekst")');
  ok((await page.locator(".mx-msg.in .mx-text").innerText()).includes("een vraag over mijn pas"), "tekstvariant te kiezen");
  ok(!(await page.locator(".mx-item.unread").count()), "ticket is als gelezen gemarkeerd");
  const [dl] = await Promise.all([page.waitForEvent("download"), page.click('.mx-atts button')]);
  ok(dl.suggestedFilename() === "scherm.png", "bijlage downloaden");
  await shot("2-inbox-ticket");

  // antwoord
  await page.fill(".mx-reply .mx-editor textarea", "Hoi **Sanne**, dit is opgelost.");
  await page.waitForFunction(() => document.querySelector(".mx-reply .mx-pv-host") && document.querySelector(".mx-reply .mx-pv-host").shadowRoot && document.querySelector(".mx-reply .mx-pv-host").shadowRoot.textContent.includes("opgelost"));
  ok(last("mail_preview").b.body_md.includes("**Sanne**"), "antwoord toont live voorbeeld (mail_preview)");
  ok((await page.locator(".mx-reply .mx-sig").innerText()).includes("Handtekening Team Pasr toevoegen") && await page.locator(".mx-reply .mx-sig input").isChecked(), "antwoord: schakelaar Handtekening Team Pasr, standaard aan");
  ok(last("mail_preview").b.signature === true && (await page.locator(".mx-reply .mx-pv-host").evaluate((h) => h.shadowRoot.textContent)).includes("Team Pasr"), "voorbeeld toont de handtekening");
  const rcc = page.locator(".mx-reply .mx-addr").nth(0).locator("input");
  await rcc.fill("een@example.test, twee@example.test"); await rcc.press("Enter");
  await page.click('.mx-reply button[type=submit]');
  await page.waitForSelector("#mailModal:not(.hidden)");
  const dtxt = await page.locator("#mailModal").innerText();
  ok(dtxt.includes("Pasr") && dtxt.includes("3 adressen"), "bevestiging toont merk en aantal ontvangers");
  ok(dtxt.includes("Team Pasr") && !dtxt.includes("Zakelijk"), "bevestiging toont de handtekening van Support");
  ok((await page.locator(".mx-reply .mx-sig").innerText()).includes("Team Pasr") && !(await page.locator(".mx-reply .mx-sig").innerText()).includes("Zakelijk"), "naam van de handtekening volgt het postvak");
  await shot("3-bevestiging-antwoord");
  await page.click("#mmCancel");
  ok(!calls.some((c) => c.action === "mail_thread_reply"), "annuleren verstuurt niets");
  await page.click('.mx-reply button[type=submit]'); await page.click("#mmOk");
  await page.waitForFunction(() => document.querySelector("#toast") && /verstuurd/i.test(document.querySelector("#toast").textContent));
  const rep = last("mail_thread_reply").b;
  ok(rep.number === 1003 && rep.brand === "pasr" && rep.cc.length === 2 && rep.status === "pending" && rep.signature === true, "thread_reply met merk, CC, status en handtekening");
  await page.waitForSelector('#mail-inbox .mx-notice', { timeout: 5000 }).catch(() => {});
  ok(await page.locator('#mail-inbox .mx-notice button:text-is("Bekijk in Verzonden")').isVisible(), "na antwoord: melding Bekijk in Verzonden");
  // notitie en status
  await page.waitForSelector(".mx-msg");
  await page.click('.mx-reply .seg button:has-text("Interne notitie")');
  await page.fill(".mx-reply .mx-field textarea", "Terugbellen");
  await page.click('.mx-reply button[type=submit]');
  await page.waitForTimeout(400);
  ok(!!last("mail_thread_note") && last("mail_thread_note").b.text === "Terugbellen", "interne notitie opgeslagen");
  await page.selectOption(".mx-statusform select >> nth=0", "closed");
  await page.click('.mx-statusform button:has-text("Opslaan")');
  await page.waitForTimeout(300);
  ok(last("mail_thread_status").b.status === "closed", "status wijzigen");
  await page.click('#mail-inbox .mx-status button:has-text("Nu ophalen")');
  await page.waitForTimeout(300);
  ok(!!last("mail_poll"), "Nu ophalen roept mail_poll aan");

  // ---- Nieuwe mail ----
  await page.click("#mtab-compose");
  await page.waitForSelector("#mail-compose form");
  for (const l of ["Aan", "CC", "BCC"]) ok(await page.locator(`#mail-compose .mx-addr .mx-lab:text-is("${l}")`).isVisible(), `veld ${l} altijd zichtbaar`);
  ok((await page.locator("#mail-compose button", { hasText: /CC\/BCC tonen/i }).count()) === 0, "geen verborgen knop voor CC/BCC");
  const bcc = page.locator("#mail-compose .mx-addr").nth(2).locator("input");
  await bcc.focus();
  await page.evaluate(() => { const i = document.querySelectorAll("#mail-compose .mx-addr input")[2]; const dt = new DataTransfer(); dt.setData("text", "a@example.test, B@example.test\nc@example.test b@example.test, kapot, Naam <d@example.test>"); i.dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true })); });
  const cnt = await page.locator("#mail-compose .mx-addr").nth(2).locator(".mx-count").innerText();
  ok(/4 adressen|5 adressen/.test(cnt) && cnt.includes("1 ongeldig") && cnt.includes("1 dubbel"), "teller: aantal, ongeldig en dubbel (" + cnt.replace(/[a-z0-9]+@\S+/gi, "") + ")");
  ok((await page.locator("#mail-compose .mx-addr").nth(2).locator(".mx-chip.bad").count()) === 1, "ongeldig adres rood gemarkeerd");
  await page.locator("#mail-compose .mx-addr").nth(0).locator("input").fill("ontvanger@example.test ");
  await page.locator("#mail-compose input[type=text]").nth(3).fill("Kennismaken met Pasr Zakelijk");
  // opmaak
  await page.fill("#mail-compose .mx-editor textarea", "Hoi {{voornaam}}");
  await page.fill("#mail-compose .mx-editor textarea", "");
  await page.click('#mail-compose .mx-tool:text-is("Kop")');
  await page.keyboard.type("Welkom"); await page.keyboard.press("Enter");
  await page.click('#mail-compose .mx-tool:text-is("B")'); await page.keyboard.type("dik"); await page.keyboard.press("End"); await page.keyboard.press("Enter");
  await page.click('#mail-compose .mx-tool:text-is("Knop")');
  await page.keyboard.type("https://pasr.nl/zakelijk/");
  const md = await page.inputValue("#mail-compose .mx-editor textarea");
  if (process.env.DEBUG_MD) console.log(JSON.stringify(md));
  ok(md.includes("## Welkom") && md.includes("**dik**") && md.includes("[[Knoptekst|https://pasr.nl/zakelijk/]]"), "werkbalk: kop, vet en knop");
  await page.fill("#mail-compose .mx-editor textarea", ""); await page.click('#mail-compose .mx-tool:text-is("Link")');
  const mdLink = await page.inputValue("#mail-compose .mx-editor textarea");
  await page.fill("#mail-compose .mx-editor textarea", ""); await page.click('#mail-compose .mx-tool:text-is("Afbeelding")');
  const mdImg = await page.inputValue("#mail-compose .mx-editor textarea");
  await page.fill("#mail-compose .mx-editor textarea", ""); await page.click('#mail-compose .mx-tool:text-is("Lijst")');
  ok(mdLink === "[tekst](https://)" && mdImg === "![omschrijving](https://)", "werkbalk: link en afbeelding");
  await page.fill("#mail-compose .mx-editor textarea", "## Welkom\n\nHoi {{voornaam}}, **leuk** dat je er bent.\n\n[[Open Pasr Zakelijk|https://pasr.nl/zakelijk/]]");
  await page.click('#mail-compose .mx-pv-head button:text-is("Donker")');
  await page.waitForFunction(() => { const h = document.querySelector("#mail-compose .mx-pv-host"); return h.shadowRoot && h.shadowRoot.textContent.includes("Welkom"); });
  const bgDark = await page.evaluate(() => { const h = document.querySelector("#mail-compose .mx-pv-host"); return getComputedStyle(h.shadowRoot.querySelector(".card")).backgroundColor; });
  await page.click('#mail-compose .mx-pv-head button:text-is("Licht")');
  await page.waitForTimeout(200);
  const bgLight = await page.evaluate(() => { const h = document.querySelector("#mail-compose .mx-pv-host"); return getComputedStyle(h.shadowRoot.querySelector(".card")).backgroundColor; });
  ok(bgDark !== bgLight && bgLight === "rgb(255, 255, 255)", "voorbeeld wisselt tussen licht en donker (" + bgLight + " / " + bgDark + ")");
  await page.click('#mail-compose .mx-pv-head button:text-is("Donker")');
  // bijlagen
  await page.setInputFiles("#mail-compose input[type=file]", [{ name: "folder.pdf", mimeType: "application/pdf", buffer: Buffer.alloc(300 * 1024, 1) }]);
  await page.waitForSelector("#mail-compose .mx-file");
  ok((await page.locator("#mail-compose .mx-files").innerText()).includes("folder.pdf"), "bijlage getoond met grootte");
  await page.setInputFiles("#mail-compose input[type=file]", [{ name: "groot.bin", mimeType: "application/octet-stream", buffer: Buffer.alloc(20 * 1024 * 1024, 1) }]);
  await page.waitForTimeout(500);
  ok((await page.locator("#mail-compose .mx-att .err").innerText()).includes("20 MB") && (await page.locator("#mail-compose .mx-file:not(.total)").count()) === 1, "bijlagen boven 20 MB totaal geweigerd");
  ok((await page.locator("#mail-compose .mx-sig").innerText()).includes("Handtekening Team Pasr toevoegen"), "nieuwe mail: schakelaar Handtekening Team Pasr");
  await page.click("#mail-compose .mx-sig input");
  await page.waitForTimeout(700);
  await shot("4-nieuwe-mail", true);
  // testmail
  await page.fill("#mail-compose .mx-testrow input", "ik@example.test");
  await page.click('#mail-compose button:text-is("Testmail sturen")');
  await page.waitForTimeout(300);
  ok(last("mail_test").b.to === "ik@example.test" && last("mail_test").b.brand === "pasr" && last("mail_test").b.signature === false, "testmail naar één adres; handtekening uit wordt meegestuurd");
  ok(last("mail_preview").b.signature === false, "voorbeeld zonder handtekening als de schakelaar uit staat");
  // ongeldige adressen blokkeren versturen
  await page.click('#mail-compose button[type=submit]');
  ok((await page.locator("#mail-compose .mx-form > .err").innerText()).includes("rood"), "versturen geblokkeerd met ongeldig adres");
  await page.locator("#mail-compose .mx-addr").nth(2).locator(".mx-chip.bad button").click();
  await page.click("#mail-compose .mx-sig input");
  ok((await page.locator("#mail-compose .mx-sig").innerText()).includes("Team Pasr") && await page.locator("#mail-compose .mx-sig input").isChecked(), "nieuwe mail: naam volgt merk, weer aan");
  await page.click('#mail-compose button[type=submit]');
  await page.waitForSelector("#mailModal:not(.hidden)");
  const ct = await page.locator("#mailModal").innerText();
  ok(ct.includes("Pasr") && /5 adressen/.test(ct) && ct.includes("BCC 4") && ct.includes("1 bestand"), "bevestiging: merk, ontvangers, bijlagen");
  await shot("5-bevestiging-nieuwe-mail");
  await page.click("#mmOk");
  await page.waitForTimeout(400);
  const cb = last("mail_compose").b;
  ok(cb.bcc.length === 4 && cb.to.length === 1 && cb.brand === "pasr" && cb.attachments.length === 1 && !!cb.attachments[0].data_b64 && cb.thread === true && cb.signature === true, "mail_compose met aan, BCC, merk, bijlage en handtekening");
  ok(!(await page.evaluate(() => JSON.stringify(Object.assign({}, localStorage)))).includes("@"), "geen adressen in localStorage");

  // te groot: getal uit de server
  await page.locator("#mail-compose input[type=text]").nth(3).fill("TOOLARGE");
  await page.locator("#mail-compose .mx-addr").nth(0).locator("input").fill("x@example.test ");
  await page.fill("#mail-compose .mx-editor textarea", "tekst");
  await page.click('#mail-compose button[type=submit]'); await page.click("#mmOk");
  await page.waitForTimeout(400);
  ok((await page.locator("#mail-compose .mx-form > .err").innerText()).includes("hoogstens 20 MB"), "too_large toont de limiet uit de server");

  // ---- Verzonden ----
  await page.locator("#mail-compose .mx-addr").nth(0).locator(".mx-chip button").click();
  await page.locator("#mail-compose input[type=text]").nth(3).fill("Nog een mail");
  await page.locator("#mail-compose .mx-addr").nth(0).locator("input").fill("y@example.test ");
  await page.click('#mail-compose button[type=submit]'); await page.click("#mmOk");
  await page.waitForSelector('#mail-compose .err button:text-is("Bekijk in Verzonden")');
  await shot("10-na-versturen-link", true);
  await page.click('#mail-compose .err button:text-is("Bekijk in Verzonden")');
  await page.waitForSelector("#mail-sent .mx-msg");
  ok((await page.locator("#mtab-sent").getAttribute("aria-selected")) === "true", "knop opent het tabblad Verzonden met de thread");
  ok(last("mail_thread_list").b.box === "sent", "thread_list met box=sent");
  await page.waitForSelector("#mail-sent .mx-item");
  const sl = await page.locator("#mail-sent .mx-list").innerText();
  ok((await page.locator("#mail-sent .mx-item").count()) === 2 && sl.includes("BCC 4") && sl.includes("CC 1") && sl.includes("1 bijlage") && sl.includes("Niet verstuurd"), "verzonden-lijst: aantallen, bijlage, merk en fout");
  ok(!(await page.locator("#mail-sent .mx-filters").isVisible()), "geen statusfilter in Verzonden");
  await page.click('#mail-sent .mx-item:has-text("#1004")');
  await page.waitForSelector("#mail-sent .mx-msg");
  const sm = await page.locator("#mail-sent .mx-msg").first().innerText();
  ok(sm.includes("kopie@example.test") && sm.includes("4 ontvangers") && !sm.includes("BCC kopie"), "thread: To en CC zichtbaar, BCC alleen aantal");
  await shot("11-verzonden");

  // ---- Nieuwsbrief ----
  await page.click("#mtab-news");
  await page.waitForSelector("#mail-news .mx-audcount b");
  await page.waitForFunction(() => document.querySelector("#mail-news .mx-audcount b").textContent !== "–");
  ok((await page.locator("#mail-news .mx-audcount b").innerText()) === "1.200", "Support: doelgroep Gebruikers toont aantal");
  ok((await page.locator("#mail-news .mx-from").innerText()).includes("support@pasr.nl"), "nieuwsbrief Support gaat vanaf support@pasr.nl");
  ok((await page.locator("#mail-news .hist").count()) === 2, "campagne-overzicht");
  ok(await page.locator("#mail-news progress").count() === 1, "voortgang van lopende verzending");
  await page.locator("#mail-news input[type=text]").nth(0).fill("Kennismaken met Pasr Zakelijk");
  await page.fill("#mail-news .mx-editor textarea", "Hoi {{voornaam}},\n\nPasr Zakelijk voor jouw zaak.");
  ok((await page.locator("#mail-news .mx-sig").innerText()).includes("Handtekening Team Pasr toevoegen") && await page.locator("#mail-news .mx-sig input").isChecked(), "nieuwsbrief: schakelaar met Team Pasr, standaard aan");
  await page.waitForTimeout(700);
  await shot("6-nieuwsbrief", true);
  await page.click('#mail-news button[type=submit]');
  await page.waitForSelector("#mailModal:not(.hidden)");
  ok((await page.locator("#mailModal").innerText()).includes("1.200 personen"), "bevestiging toont aantal ontvangers");
  await page.click("#mmOk"); await page.waitForTimeout(400);
  const cs = last("mail_campaign_send").b;
  ok(cs.audience === "users" && cs.brand === "pasr" && /^[0-9a-f-]{36}$/.test(cs.request_id), "campaign_send met doelgroep, merk en request_id");
  ok(cs.signature === true, "campaign_send stuurt signature mee");
  page.once("dialog", () => {});
  await page.click('#mail-news button:text-is("Annuleren")');
  await page.waitForSelector("#mailModal:not(.hidden)"); await page.click("#mmOk"); await page.waitForTimeout(300);
  ok(!!last("mail_campaign_cancel"), "lopende verzending annuleren");

  // ---- Postvak Ondernemers: eigen adres, eigen tickets, eigen doelgroep ----
  await page.click("#tab-mail-zakelijk");
  await page.waitForFunction(() => document.getElementById("mailTitle").textContent === "Postvak Ondernemers");
  await page.waitForSelector("#mail-inbox .mx-item");
  ok((await page.locator("#mail-inbox .mx-item").count()) === 1 && (await page.locator("#mail-inbox .mx-list").innerText()).includes("#1002"), "Ondernemers-postvak toont alleen zakelijke tickets");
  ok(calls.some((c) => c.action === "mail_thread_list" && c.b.brand === "zakelijk"), "Ondernemers-postvak vraagt brand=zakelijk");
  await page.click("#tab-mailnews-zakelijk");
  await page.waitForFunction(() => document.querySelector("#mail-news .mx-audcount b") && document.querySelector("#mail-news .mx-audcount b").textContent === "48");
  ok((await page.locator("#mail-news .mx-from").innerText()).includes("zakelijk@pasr.nl"), "nieuwsbrief Ondernemers gaat vanaf zakelijk@pasr.nl");
  await page.locator("#mail-news input[type=text]").nth(0).fill("Voor ondernemers");
  await page.fill("#mail-news .mx-editor textarea", "Hoi {{voornaam}},\n\nNieuws.");
  await page.click('#mail-news button[type=submit]');
  await page.waitForSelector("#mailModal:not(.hidden)"); await page.click("#mmOk"); await page.waitForTimeout(400);
  const cz = last("mail_campaign_send").b;
  ok(cz.audience === "owners" && cz.brand === "zakelijk", "Ondernemers-nieuwsbrief: doelgroep owners, merk zakelijk");

  // ---- algemeen ----
  ok(dialogs === 0, "geen browserdialogen (eigen vensters)");
  ok(!logs.some((l) => /@/.test(l)), "geen e-mailadressen in de console");
  ok(!logs.some((l) => /pageerror|Content Security Policy|Refused/i.test(l)), "geen scriptfouten of CSP-overtredingen" + (logs.length ? " " + JSON.stringify(logs.filter((l) => /pageerror|Content Security|Refused/i.test(l)).slice(0, 3)) : ""));
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
  ok(!overflow, "geen horizontale scroll (desktop)");

  // ---- mobiel ----
  await page.click("#tab-mail-pasr"); await page.click("#mtab-sent"); await page.waitForSelector("#mail-sent .mx-item"); await page.click("#mail-sent .mx-item >> nth=0"); await page.waitForSelector("#mail-sent .mx-msg");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.click("#mtab-sent"); await page.waitForSelector("#mail-sent .mx-layout .mx-detail"); if (await page.locator("#mail-sent .mx-back").isVisible()) await page.click("#mail-sent .mx-back"); await page.waitForSelector("#mail-sent .mx-item"); await shot("12-mobiel-verzonden"); await page.click("#mtab-inbox"); if (await page.locator("#mail-inbox .mx-back").isVisible()) await page.click("#mail-inbox .mx-back"); await page.waitForSelector(".mx-item");
  ok(!(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1)), "geen horizontale scroll (mobiel, inbox)");
  await shot("7-mobiel-inbox");
  await page.click("#mail-inbox .mx-item >> nth=0"); await page.waitForSelector("#mail-inbox .mx-msg");
  ok(await page.locator("#mail-inbox .mx-back").isVisible() && !(await page.locator("#mail-inbox .mx-list").isVisible()), "mobiel: detail vervangt de lijst met terugknop");
  await shot("8-mobiel-ticket", true);
  await page.click("#mail-inbox .mx-back");
  await page.click("#mtab-compose");
  ok(!(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1)), "geen horizontale scroll (mobiel, nieuwe mail)");
  await shot("9-mobiel-nieuwe-mail", true);
  await browser.close(); server.close();
  console.log(failed ? `\n${failed} test(s) mislukt` : "\nAlle tests geslaagd");
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
