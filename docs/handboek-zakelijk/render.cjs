// Bouwt Handboek-Pasr-Zakelijk.pdf uit handboek.html (Chromium, A4).
//   1. PDF maken; finish.py leest op welke pagina elk hoofdstuk en elke paragraaf staat (via de links in de inhoudsopgave)
//   2. paginanummers in de inhoudsopgave zetten en opnieuw maken (tot ze niet meer veranderen)
//   3. kop- en voettekst per pagina (hoofdstuknaam, paginanummer) als tweede laag erover, bladwijzers en metadata (finish.py)
// Gebruik: node docs/handboek-zakelijk/render.cjs [uitvoer.pdf]   (eerst: shots/web.cjs, shots/app.cjs, python3 images.py)
const { chromium } = require("playwright");
const { execFileSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");
const fs = require("node:fs");
const path = require("node:path");

const HERE = __dirname;
const BUILD = path.join(HERE, "build");
const OUT = path.resolve(process.argv[2] || path.join(HERE, "Handboek-Pasr-Zakelijk.pdf"));
fs.mkdirSync(BUILD, { recursive: true });
const PDF = { format: "A4", printBackground: true, preferCSSPageSize: true, outline: true, tagged: true };

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(pathToFileURL(path.join(HERE, "handboek.html")).href);
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => Promise.all([...document.images].map((i) => i.complete ? 0 : new Promise((r) => { i.onload = i.onerror = r; }))));
  for (const f of fs.readdirSync(BUILD)) if (/^pass\d\.pdf$/.test(f)) fs.unlinkSync(path.join(BUILD, f));
  let pages = null;
  for (let pass = 1; pass <= 4; pass++) {
    const file = path.join(BUILD, `pass${pass}.pdf`);
    await page.pdf(Object.assign({ path: file }, PDF));
    const found = JSON.parse(execFileSync("python3", [path.join(HERE, "finish.py"), "pages", file], { encoding: "utf8" }));
    const same = pages && JSON.stringify(found) === JSON.stringify(pages);
    pages = found;
    console.log(`pass ${pass}: ${Object.keys(found).length} doelen`);
    if (same) break;
    await page.evaluate((p) => { document.querySelectorAll(".toc [data-for]").forEach((el) => { el.textContent = p[el.dataset.for] || "?"; }); }, pages);
  }
  // kop- en voettekst: per pagina het hoofdstuk (van het laatste hoofdstukbegin op of voor die pagina)
  const chapters = await page.evaluate(() => [...document.querySelectorAll("section.chapter")].map((s) => ({ id: s.id, title: s.dataset.title, num: s.dataset.num })));
  const total = JSON.parse(execFileSync("python3", [path.join(HERE, "finish.py"), "count", fs.readdirSync(BUILD).filter((f) => /^pass\d\.pdf$/.test(f)).sort().map((f) => path.join(BUILD, f)).pop()], { encoding: "utf8" }));
  const per = [];
  for (let n = 1; n <= total; n++) {
    let cur = null;
    for (const c of chapters) if (pages[c.id] && pages[c.id] <= n) cur = c;
    per.push(n === 1 ? null : n < (pages[chapters[0].id] || 3) ? { head: "Inhoud", n } : { head: `${cur.num}  ${cur.title}`, n });
  }
  const overlay = await browser.newPage();
  const ovFile = path.join(BUILD, "overlay.html");
  fs.writeFileSync(ovFile, `<!doctype html><html><head><style>
    @font-face{font-family:F;font-weight:600;src:url(${pathToFileURL(path.join(HERE, "fonts/figtree-latin-600-normal.woff2")).href})}
    @font-face{font-family:F;font-weight:800;src:url(${pathToFileURL(path.join(HERE, "fonts/figtree-latin-800-normal.woff2")).href})}
    @page{size:A4;margin:0} html,body{margin:0}
    .p{position:relative;width:210mm;height:297mm;break-after:page;font-family:F;color:#6B6E82}
    .h{position:absolute;left:18mm;right:18mm;top:10.5mm;display:flex;justify-content:space-between;font:600 7.8pt F;border-bottom:.25mm solid #DCD9F2;padding-bottom:1.8mm}
    .h b{font-weight:800;color:#4A3CE0;letter-spacing:.02em} .f{position:absolute;left:18mm;right:18mm;bottom:9mm;display:flex;justify-content:space-between;font:600 7.8pt F}
    .f b{font-weight:800;color:#17162A;font-size:8.6pt}
  </style></head><body>${per.map((p) => `<div class="p">${p ? `<div class="h"><b>${p.head}</b><span>Handboek Pasr Zakelijk</span></div><div class="f"><span>pasr.nl/zakelijk · versie 1.0.4 · november 2026</span><b>${p.n}</b></div>` : ""}</div>`).join("")}</body></html>`);
  await overlay.goto(pathToFileURL(ovFile).href);
  await overlay.evaluate(() => document.fonts.ready);
  await overlay.pdf({ path: path.join(BUILD, "overlay.pdf"), format: "A4", printBackground: false, preferCSSPageSize: true });
  const final = fs.readdirSync(BUILD).filter((f) => /^pass\d\.pdf$/.test(f)).sort().pop();
  execFileSync("python3", [path.join(HERE, "finish.py"), "merge", path.join(BUILD, final), path.join(BUILD, "overlay.pdf"), OUT], { stdio: "inherit" });
  await browser.close();
})();
