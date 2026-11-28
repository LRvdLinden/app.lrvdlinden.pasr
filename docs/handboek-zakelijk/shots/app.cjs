// Schermen van de app Pasr Zakelijk (iPhone, iPad, Mac) voor het handboek.
// Bron: de App Store-scènes in zakelijk/appstore/source/scenes.html (nagebouwd uit de SwiftUI-code in zakelijk/apple/).
// Hier zonder marketingtekst: alleen het toestel met het scherm. Eén extra scherm (Instellingen, uit SettingsView.swift)
// staat hieronder in EXTRA en gebruikt dezelfde opmaak als de andere scènes.
//   node docs/handboek-zakelijk/shots/app.cjs [filter]      → PNG's in docs/handboek-zakelijk/build/raw/
const { chromium } = require("playwright");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const HERE = path.resolve(__dirname, "..");
const SRC = path.resolve(HERE, "..", "..", "zakelijk", "appstore", "source");
const OUT = path.join(HERE, "build", "raw");
const only = process.argv[2] || "";
fs.mkdirSync(OUT, { recursive: true });

// Instellingen (SettingsView.swift): Zaak, Scannen, Vindbaar in Pasr, Account, Privacy en beveiliging, Weergave, Hulp.
const EXTRA = String.raw`
SCREENS.settings = () => {
  const chev = I.chevr;
  const sw = (on) => '<span style="width:51px;height:31px;border-radius:16px;background:' + (on ? '#2ED3A6' : '#39393D') + ';position:relative;display:inline-block;flex:none"><i style="position:absolute;top:2px;' + (on ? 'right' : 'left') + ':2px;width:27px;height:27px;border-radius:50%;background:#fff"></i></span>';
  const ic = (svg, bg) => '<span style="width:30px;height:30px;border-radius:8px;background:' + bg + ';display:grid;place-items:center;flex:none">' + svg.replace('<svg', '<svg style="width:18px;height:18px;stroke:#fff;fill:none;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round"') + '</span>';
  return '<div class="app">' + status() + '<div class="navin"><div class="r"><div class="glw" style="gap:6px">De Hoek ' + I.chevd + '</div></div></div>' +
    '<div class="big">' + T("Instellingen") + '</div>' +
    '<div class="content" style="top:166px">' +
      '<div class="sec">' + T("Zaak") + '</div><div class="grp"><div class="r"><div class="sp"><b style="font-weight:600">' + BUS + '</b><small>Apeldoorn</small><small style="color:#8B80FF;font-weight:600">' + T("Je bent eigenaar") + '</small></div></div>' +
        '<div class="r acc">' + I.pencil + '<span class="sp">' + T("Gegevens van de zaak wijzigen") + '</span></div></div>' +
      '<div class="sec" style="margin-top:22px">' + T("Scannen") + '</div><div class="grp"><div class="r"><span class="sp">' + T("Afkoeltijd") + '</span><span class="v">5 min ' + I.updown + '</span></div>' +
        '<div class="r"><span class="sp">' + T("Max. stempels per scan") + '</span><span class="v" style="color:#fff">10</span><span class="v" style="background:#2C2C33;border-radius:9px;padding:4px 12px;color:#fff;gap:14px">' + I.minus.replace('<svg', '<svg style="width:16px;height:16px;stroke:#fff;stroke-width:2.4"') + I.plus.replace('<svg', '<svg style="width:16px;height:16px;stroke:#fff;stroke-width:2.4"') + '</span></div></div>' +
      '<div class="sec" style="margin-top:22px">' + T("Vindbaar in Pasr") + '</div><div class="grp"><div class="r"><span class="sp">' + T("Vindbaar in Pasr") + '</span>' + sw(true) + '</div>' +
        '<div class="r"><span class="sp" style="color:#fff">Dorpsstraat 1, Apeldoorn</span></div></div>' +
      '<div class="sec" style="margin-top:22px">' + T("Privacy en beveiliging") + '</div><div class="grp"><div class="r">' + ic(I.faceid, '#12A77E') + '<span class="sp">' + T("Vergrendelen met %@", "Face ID") + '</span>' + sw(true) + '</div></div>' +
      '<div class="foot">' + T("Bij openen en na terugkeer naar de app vraagt Pasr Zakelijk om Face ID, Touch ID of je toegangscode. Handig als de iPad of iPhone aan de kassa ligt.") + '</div>' +
      '<div class="sec" style="margin-top:22px">' + T("Hulp") + '</div><div class="grp"><div class="r">' + ic(I.search, '#6A5CFF') + '<span class="sp">' + T("Hulp en contact") + '</span>' + I.arrowup.replace('<svg', '<svg style="width:15px;height:15px;stroke:#5C5C66;stroke-width:2.4;fill:none"') + '</div>' +
        '<div class="r">' + ic(I.shield, '#6A5CFF') + '<span class="sp">' + T("Privacyverklaring") + '</span>' + I.arrowup.replace('<svg', '<svg style="width:15px;height:15px;stroke:#5C5C66;stroke-width:2.4;fill:none"') + '</div></div>' +
    '</div>' + tabbar("settings") + '</div>';
};`;

// [naam, soort, scherm]; soort: iphone | ipad | mac
const SHOTS = [
  ["app-scannen", "iphone", "scan"], ["app-scanresultaat", "iphone", "result"], ["app-acties", "iphone", "cards"], ["app-delen", "iphone", "share"],
  ["app-overzicht", "iphone", "overview"], ["app-medewerkers", "iphone", "staff"], ["app-vergrendeld", "iphone", "lock"], ["app-ticket-geldig", "iphone", "ticket"],
  ["app-klantenkaart", "iphone", "member"], ["app-gezamenlijk", "iphone", "community"], ["app-instellingen", "iphone", "settings"],
  ["ipad-overzicht", "ipad", "overview"],
  ["mac-vandaag", "mac", "today"], ["mac-scannen", "mac", "scanner"], ["mac-tickets", "mac", "tickets"], ["mac-klantenkaart", "mac", "member"],
  ["mac-gezamenlijk", "mac", "community"], ["mac-inzichten", "mac", "insights"], ["mac-widgets", "mac", "widgets"],
];

(async () => {
  const browser = await chromium.launch();
  const EN = JSON.parse(fs.readFileSync(path.join(SRC, "strings_en_all.json"), "utf8"));
  for (const [name, kind, screen] of SHOTS) {
    if (only && !name.includes(only)) continue;
    const W = kind === "mac" ? 1600 : kind === "ipad" ? 1100 : 700, H = kind === "mac" ? 1100 : kind === "ipad" ? 1400 : 1300;
    const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 2 });
    page.on("pageerror", (e) => console.log("  PAGEERROR", name, e.message));
    await page.addInitScript((en) => { window.EN = en; }, EN);
    await page.goto(pathToFileURL(path.join(SRC, "scenes.html")).href + `?s=${kind === "mac" ? "m1" : "z1"}&w=${W}&h=${H}&k=${kind}&l=nl`);
    await page.waitForSelector("body[data-ready]", { state: "attached", timeout: 20000 });
    const box = await page.evaluate(({ kind, screen, extra }) => {
      if (screen === "settings" && !SCREENS.settings) (0, eval)(extra);
      const html = kind === "mac" ? macScreen(screen).replace("__STYLE__", "top:40px;width:1440px")
        : device(kind, screen, `top:40px;width:${kind === "ipad" ? 900 : 520}px`);
      root.innerHTML = `<div class="canvas light" style="background:#fff">${html}</div>`;
      document.querySelectorAll(".screen").forEach((s) => { s.querySelector(".ui").style.setProperty("--k", s.clientWidth / (s.closest(".ipad") ? 1032 : 440)); });
      document.querySelectorAll(".mscreen").forEach((s) => { const k = s.clientWidth / 1280, m = s.querySelector(".mui"); m.style.setProperty("--k", k); m.style.height = (s.clientHeight / k) + "px"; });
      const el = document.querySelector(kind === "mac" ? ".macbook" : ".device").getBoundingClientRect();
      return { x: el.left, y: el.top, width: el.width, height: el.height };
    }, { kind, screen, extra: EXTRA });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    const m = kind === "mac" ? 30 : 34;
    await page.screenshot({ path: path.join(OUT, name + ".png"), clip: { x: Math.max(0, box.x - m), y: Math.max(0, box.y - m / 2), width: box.width + 2 * m, height: box.height + 1.6 * m } });
    console.log("  " + name);
    await page.close();
  }
  await browser.close();
})();
