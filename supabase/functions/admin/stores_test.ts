import { cleanStore, domainOf, imageType, parseHead, slug } from "./stores.ts";
import { message } from "./push.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("domein en slug", () => {
  ok(domainOf("https://www.Kwantum.nl/acties?x=1") === "kwantum.nl", "domein");
  ok(domainOf("http://127.0.0.1") === null && domainOf("localhost") === null && domainOf("geen domein") === null, "geen interne adressen");
  ok(slug("Kwantum Wonen & Co") === "kwantum-wonen-co", slug("Kwantum Wonen & Co"));
  ok(slug("Café Ünique") === "cafe-unique", "accenten");
});

Deno.test("winkel controleren", () => {
  const r = cleanStore({ name: "Kwantum", domain: "kwantum.nl", card_hex: "#e30613", format: "ean13", category: "Warenhuis en wonen" });
  ok(r.ok && r.value.id === "kwantum" && r.value.card_hex === "#E30613", JSON.stringify(r));
  ok(!cleanStore({ name: "", card_hex: "#000000" }).ok, "naam verplicht");
  ok(!cleanStore({ name: "X y", card_hex: "rood" }).ok, "kleur");
  const bad = cleanStore({ name: "Kwantum", card_hex: "#000000", logo: "<svg>" });
  ok(!bad.ok, "logo moet base64 zijn");
  const odd = cleanStore({ name: "Kwantum", card_hex: "#000000", category: "Onzin", format: "foo" });
  ok(odd.ok && odd.value.category === "Overig" && odd.value.format === "code128", "standaarden");
});

Deno.test("website lezen", () => {
  const html = `<html><head><title>Kwantum | Wonen</title><meta name="theme-color" content="#e30613">
    <link rel="apple-touch-icon" sizes="180x180" href="/a.png"><link rel="icon" href="/f.svg" type="image/svg+xml">
    <link rel="icon" sizes="32x32" href="https://cdn.kwantum.nl/32.png"><link rel="manifest" href="/site.webmanifest"></head></html>`;
  const h = parseHead(html, "https://www.kwantum.nl/");
  ok(h.name === "Kwantum", String(h.name));
  ok(h.colors[0] === "#E30613", "kleur");
  ok(h.icons.length === 2 && h.icons.some((i) => i.href === "https://www.kwantum.nl/a.png" && i.size === 180), JSON.stringify(h.icons));
  ok(h.manifest === "https://www.kwantum.nl/site.webmanifest", "manifest");
  ok(imageType(new Uint8Array([0x89, 0x50, 0x4e, 0x47])) === "image/png", "png");
});

Deno.test("melding winkel aangevraagd", () => {
  const m = message("store_request", { accounts: 1, confirmed: 1, bots_hour: 0 }, "Kwantum\nX");
  ok(m.aps.alert.body === "Iemand mist Kwantum X in Pasr." && m.url === "pasrbeheer://stores", m.aps.alert.body);
});
