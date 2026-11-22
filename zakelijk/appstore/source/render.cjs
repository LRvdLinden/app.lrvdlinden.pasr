// Maakt alle App Store-afbeeldingen van Pasr Zakelijk (nl-NL en en-US):
//   node zakelijk/appstore/source/render.cjs <uitvoermap>
// Daarna: python3 zakelijk/appstore/source/flatten.py <uitvoermap>   (RGB zonder alfakanaal)
// Zelfde opzet als appstore/source/render.cjs van Pasr. Engelse app-teksten komen uit zakelijk/apple/tools/strings_en.json.
const { chromium } = require("playwright");
const { pathToFileURL } = require("node:url");
const path = require("node:path");
const fs = require("node:fs");

const here = __dirname;
const out = process.argv[2] || path.join(here, "..", "out");
const page = pathToFileURL(path.join(here, "scenes.html")).href;
const EN = JSON.parse(fs.readFileSync(path.join(here, "..", "..", "apple", "tools", "strings_en.json"), "utf8"));
const only = process.env.ONLY;

const scenes = [["z1", "scannen"], ["z2", "stempels"], ["z3", "kaarten"], ["z4", "qr-flyer"], ["z5", "overzicht"], ["z6", "medewerkers"], ["z7", "veilig"]];
const devices = [
  ["iphone-6.9", 1320, 2868, "iphone"],
  ["iphone-6.5", 1284, 2778, "iphone"],
  ["iphone-6.3", 1206, 2622, "iphone"],
  ["iphone-6.1", 1179, 2556, "iphone"],
  ["ipad-13", 2064, 2752, "ipad"],
];
const promos = [["header", 5244, 2950], ["header", 3840, 1646], ["search", 5244, 2950], ["search", 3840, 2560], ["search", 1920, 1280]];
const jobs = [];
for (const [loc, l] of [["nl-NL", "nl"], ["en-US", "en"]]) {
  for (const [dev, w, h, k] of devices) {
    scenes.forEach(([s, name], i) => jobs.push({ file: path.join("screenshots", loc, dev, `${String(i + 1).padStart(2, "0")}_${name}_${w}x${h}.png`), w, h, s, k, l }));
  }
  for (const [name, w, h] of promos) jobs.push({ file: path.join("marketing", loc, `${name}_${w}x${h}.png`), w, h, s: "", k: "promo", l });
}

(async () => {
  const browser = await chromium.launch();
  let errors = 0;
  for (const j of jobs.filter((x) => !only || x.file.includes(only))) {
    const p = await browser.newPage({ viewport: { width: j.w, height: j.h }, deviceScaleFactor: 1 });
    await p.addInitScript((en) => { window.EN = en; }, EN);
    p.on("pageerror", (e) => { errors++; console.error("ERR", j.file, e.message); });
    p.on("console", (m) => { if (m.type() === "error") { errors++; console.error("CONSOLE", j.file, m.text()); } });
    await p.goto(`${page}?s=${j.s}&w=${j.w}&h=${j.h}&k=${j.k}&l=${j.l}`);
    await p.waitForSelector("body[data-ready]", { state: "attached", timeout: 20000 });
    await p.waitForTimeout(150);
    const file = path.join(out, j.file);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    await p.screenshot({ path: file, omitBackground: false });
    await p.close();
    console.log(j.file);
  }
  await browser.close();
  if (errors) process.exit(1);
})();
