// Maakt alle App Store-afbeeldingen: node appstore/source/render.cjs <uitvoermap>
const { chromium } = require("playwright");
const { pathToFileURL } = require("node:url");
const path = require("node:path");
const fs = require("node:fs");

const here = __dirname;
const out = process.argv[2] || path.join(here, "..", "out");
const page = pathToFileURL(path.join(here, "scenes.html")).href;
const jobs = [];
const add = (dir, name, w, h, s, k) => jobs.push({ dir, name, w, h, s, k });
const iphone = ["s1", "s2", "s3", "s4", "s5", "s6", "s7"];
iphone.forEach((s, i) => add("screenshots/iPhone 6.9 inch (1320x2868)", `0${i + 1}`, 1320, 2868, s, "iphone"));
iphone.forEach((s, i) => add("screenshots/iPhone 6.5 inch (1284x2778)", `0${i + 1}`, 1284, 2778, s, "iphone"));
["s1", "s2", "s3", "s4", "s5", "s7"].forEach((s, i) => add("screenshots/iPad 13 inch (2064x2752)", `0${i + 1}`, 2064, 2752, s, "ipad"));
iphone.forEach((s, i) => add("screenshots/iPhone 6.3 inch (1206x2622)", `0${i + 1}`, 1206, 2622, s, "iphone"));
iphone.forEach((s, i) => add("screenshots/iPhone 6.1 inch (1179x2556)", `0${i + 1}`, 1179, 2556, s, "iphone"));
["watchlist", "watchcode", "watchqr"].forEach((s, i) => {
  add("screenshots/Apple Watch Ultra 3 (422x514)", `0${i + 1}`, 422, 514, s, "watchmock");
  add("screenshots/Apple Watch Ultra 3 zonder mockup (422x514)", `0${i + 1}`, 422, 514, s, "watch");
  add("screenshots/Apple Watch Series 46mm (416x496)", `0${i + 1}`, 416, 496, s, "watchmock");
});
add("promo/App Store artwork 1 (5244x2950, 3840x1646)", "5244x2950", 5244, 2950, "", "promo");
add("promo/App Store artwork 1 (5244x2950, 3840x1646)", "3840x1646", 3840, 1646, "", "promo");
add("promo/App Store artwork 2 (5244x2950, 3840x2560, 1920x1280)", "5244x2950", 5244, 2950, "", "promo");
add("promo/App Store artwork 2 (5244x2950, 3840x2560, 1920x1280)", "3840x2560", 3840, 2560, "", "promo");
add("promo/App Store artwork 2 (5244x2950, 3840x2560, 1920x1280)", "1920x1280", 1920, 1280, "", "promo");
add("promo/In-App Event", "event-card-1920x1080", 1920, 1080, "", "promo");
add("promo/In-App Event", "event-details-1080x1920", 1080, 1920, "", "promo");
add("promo/Overig", "social-1200x630", 1200, 630, "", "promo");

(async () => {
const browser = await chromium.launch();
for (const j of jobs) {
  const p = await browser.newPage({ viewport: { width: j.w, height: j.h }, deviceScaleFactor: 1 });
  p.on("pageerror", (e) => console.error("ERR", j.s, e.message));
  p.on("console", (m) => { if (m.type() === "error") console.error("CONSOLE", j.s, m.text()); });
  await p.goto(`${page}?s=${j.s}&w=${j.w}&h=${j.h}&k=${j.k}`);
  await p.waitForSelector("body[data-ready]", { state: "attached", timeout: 15000 });
  await p.waitForTimeout(150);
  const dir = path.join(out, j.dir);
  fs.mkdirSync(dir, { recursive: true });
  await p.screenshot({ path: path.join(dir, `${j.name}.png`), omitBackground: false });
  await p.close();
  console.log(j.dir, j.name);
}
await browser.close();
})();
