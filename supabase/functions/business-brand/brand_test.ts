import { cleanName, cleanUrl, dominant, hex, isPrivateIp, parseHead, parseManifest, pickColor, rankCandidates, textColor, usable } from "./brand.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("url: alleen http(s) en echte hostnamen", () => {
  ok(cleanUrl("bakkerij.nl")?.href === "https://bakkerij.nl/", "zonder schema");
  ok(cleanUrl("http://www.bakkerij.nl/over")?.hostname === "www.bakkerij.nl", "http mag");
  for (const bad of ["ftp://x.nl", "file:///etc/passwd", "http://localhost", "http://127.0.0.1", "http://[::1]/", "http://10.0.0.1",
                     "https://user:pw@x.nl", "https://x.nl:8080", "http://metadata.google.internal", "javascript:alert(1)", "", 5]) {
    ok(cleanUrl(bad) === null, "geweigerd: " + String(bad));
  }
});

Deno.test("ip: privé en gereserveerd", () => {
  for (const ip of ["10.1.2.3", "127.0.0.1", "169.254.169.254", "172.16.0.1", "192.168.1.1", "100.64.0.1", "0.0.0.0", "::1", "fd00::1", "fe80::1", "::ffff:10.0.0.1"]) {
    ok(isPrivateIp(ip), "privé: " + ip);
  }
  for (const ip of ["93.184.216.34", "172.32.0.1", "2a00:1450:4001:80b::200e", "8.8.8.8"]) ok(!isPrivateIp(ip), "publiek: " + ip);
});

Deno.test("html: naam, theme-color, iconen", () => {
  const h = parseHead(`<html><head><title>Bakkerij De Korf | Brood</title><meta name="theme-color" content="#c33">
    <meta property="og:site_name" content="Bakkerij De Korf"><link rel="manifest" href="/site.webmanifest">
    <link rel="icon" href="/fav.svg" type="image/svg+xml"><link rel="icon" href="/fav.ico">
    <link rel="apple-touch-icon" sizes="180x180" href="/apple.png"><link rel="icon" sizes="32x32" href="/f32.png">
    <meta property="og:image" content="https://cdn.x.nl/og.jpg"></head>`, "https://korf.nl/");
  ok(h.name === "Bakkerij De Korf" && h.colors[0] === "#CC3333" && h.manifest === "https://korf.nl/site.webmanifest", JSON.stringify(h));
  ok(h.icons.length === 2 && h.icons.every((i) => !/svg|ico/.test(i.href)), "geen svg/ico");
  const m = parseManifest({ name: "Korf", theme_color: "#123456", icons: [{ src: "/i512.png", sizes: "512x512" }, { src: "/m.png", sizes: "512x512", purpose: "maskable" }, { src: "/x.svg" }] }, "https://korf.nl/site.webmanifest");
  ok(m.color === "#123456" && m.icons.length === 2 && m.name === "Korf", "manifest");
  const r = rankCandidates(h, m.icons, "https://korf.nl/");
  ok(r[0].href === "https://korf.nl/i512.png" && r[r.length - 1].href === "https://cdn.x.nl/og.jpg", r.map((x) => x.href).join(","));
});

Deno.test("kleur: geen wit/zwart/grijs, leesbare tekst", () => {
  ok(!usable("#FFFFFF") && !usable("#000000") && !usable("#808080") && usable("#E30613"), "bruikbaar");
  ok(pickColor(["#FFFFFF", "#E30613"], "#00FF00") === "#E30613", "theme eerst");
  ok(pickColor(["#FFFFFF"], "#12A77E") === "#12A77E", "anders logo");
  ok(textColor("#F2B705") === "#000000" && textColor("#17162A") === "#FFFFFF", "contrast");
  const px = new Uint8Array(400 * 4);
  for (let i = 0; i < 400; i++) { const red = i < 300; px.set(red ? [220, 20, 30, 255] : [255, 255, 255, 255], i * 4); }
  const d = dominant(px);
  ok(d !== null && d.startsWith("#D"), String(d));
  ok(hex("rgb(255, 0, 0)") === "#FF0000" && hex("#abc") === "#AABBCC", "hex");
  ok(cleanName("  Bakkerij &amp; Co  ") === "Bakkerij & Co" && cleanName("x") === null && cleanName(5) === null, "naam");
});
