import { cleanCover, cleanGuide, cleanStore, domainOf, imageType, parseHead, slug } from "./stores.ts";
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

Deno.test("saldo-pagina", async () => {
  const { cleanBalancePage } = await import("./stores.ts");
  const r = cleanBalancePage({ store_id: "VVV", url: "https://www.vvvcadeaukaarten.nl/saldo" });
  ok(r.ok && r.value.store_id === "vvv" && r.value.url === "https://www.vvvcadeaukaarten.nl/saldo", JSON.stringify(r));
  ok(!cleanBalancePage({ store_id: "vvv", url: "http://vvv.nl" }).ok, "alleen https");
  ok(!cleanBalancePage({ store_id: "vvv", url: "https://127.0.0.1/x" }).ok, "geen interne adressen");
  ok(!cleanBalancePage({ store_id: "v v", url: "https://vvv.nl" }).ok, "id");
  ok(!cleanBalancePage({ store_id: "vvv", url: "https://a:b@vvv.nl" }).ok, "geen inlog in adres");
});

Deno.test("aanvraag hoort bij winkel", async () => {
  const { requestMatches } = await import("./stores.ts");
  const store = { name: "Bakkers Cadeau", domain: "bakkerscadeaukaart.nl", aliases: ["bakkerscadeaukaart"] };
  ok(requestMatches(store, { name: "iets", website: "https://www.bakkerscadeaukaart.nl/saldo" }), "domein");
  ok(requestMatches(store, { name: "bakkers cadeau" }), "naam");
  ok(requestMatches(store, { name: "Bakkerscadeaukaart" }), "alias");
  ok(!requestMatches(store, { name: "Bakker Bart" }), "andere winkel");
  ok(!requestMatches({ name: "AH" }, { name: "a" }), "te kort");
});

Deno.test("cadeaubon-gids", () => {
  const r = cleanGuide({ validity: " 3 jaar ", online: true, store: false, how: "Bij de kassa.", terms_url: "https://www.bol.com/x", checked: "2026-11-21", foo: 1 });
  ok(r.ok && r.value?.validity === "3 jaar" && r.value.online === true && r.value.store === false && !("foo" in (r.value ?? {})), JSON.stringify(r));
  ok(!cleanGuide({ terms_url: "http://bol.com" }).ok, "alleen https");
  ok(!cleanGuide({ program_url: "http://ah.nl" }).ok, "programma alleen https");
  const loy = cleanGuide({ earn: "Scan je kaart.", perks: "Korting.", program_url: "https://www.ah.nl/bonuskaart" });
  ok(loy.ok && loy.value?.earn === "Scan je kaart." && loy.value.program_url === "https://www.ah.nl/bonuskaart", JSON.stringify(loy));
  const bd = cleanGuide({ birthday: "  Gratis   taartje in je verjaardagsmaand " });
  ok(bd.ok && bd.value?.birthday === "Gratis taartje in je verjaardagsmaand", JSON.stringify(bd));
  const longBd = cleanGuide({ birthday: "x".repeat(400) });
  ok(longBd.ok && longBd.value?.birthday?.length === 160, "verjaardag hoogstens 160 tekens");
  ok(!cleanGuide({ checked: "21-11-2026" }).ok, "datum");
  ok(!cleanGuide({ online: "ja" }).ok, "true/false");
  ok(!cleanGuide([1]).ok, "geen lijst");
  const empty = cleanGuide({ validity: "  " });
  ok(empty.ok && empty.value === null, "leeg wordt null");
  const s1 = cleanStore({ name: "Bol", card_hex: "#0000A4" });
  ok(s1.ok && !("guide" in s1.value), "zonder gids blijft de gids staan");
  const s2 = cleanStore({ name: "Bol", card_hex: "#0000A4", guide: { validity: "3 jaar" } });
  ok(s2.ok && s2.value.guide?.validity === "3 jaar", "met gids");
  ok(!cleanStore({ name: "Bol", card_hex: "#0000A4", guide: { terms_url: "javascript:alert(1)" } }).ok, "foute gids");
});

Deno.test("kaartontwerp (cover)", () => {
  const s1 = cleanStore({ name: "VVV", card_hex: "#0066B3" });
  ok(s1.ok && !("cover" in s1.value), "zonder cover blijft de cover staan");
  const s2 = cleanStore({ name: "VVV", card_hex: "#0066B3", cover: "data:image/jpeg;base64,/9j/4AAQSkZJRg==" });
  ok(s2.ok && s2.value.cover === "/9j/4AAQSkZJRg==", "jpeg");
  const s3 = cleanStore({ name: "VVV", card_hex: "#0066B3", cover: null });
  ok(s3.ok && s3.value.cover === null, "verwijderen");
  ok(!cleanCover("R0lGODlh").ok, "geen gif");
  ok(!cleanCover("/9j/" + "A".repeat(220_000)).ok, "te groot");
});


Deno.test("evenementticket blijft een ticket in de catalogus", () => {
  const r = cleanStore({ name: "Voorbeeld evenement", domain: "example.com", card_hex: "#123456", category: "Evenementen", kind: "ticket", format: "qr" });
  ok(r.ok && r.value.kind === "ticket" && r.value.format === "qr" && r.value.category === "Evenementen", JSON.stringify(r));
});

Deno.test("ticket: evenementgegevens in de gids", () => {
  const r = cleanGuide({
    event: "  Drakenboot   2027 ", brand: "Drakenboot", date: "2027-06-18", doors: "17:00", ends: "01:00",
    venue: "Zwitsalpark", city: "Apeldoorn", ticket_type: "KIDS Early Bird", ticket_note: "t/m 14 jaar",
    info_url: "https://www.drakenboot.nl/tickets", text_hex: "#ffffff", onbekend: "weg",
  });
  ok(r.ok && r.value?.event === "Drakenboot 2027" && r.value.text_hex === "#FFFFFF" && r.value.doors === "17:00", JSON.stringify(r));
  ok(r.ok && !("onbekend" in (r.value ?? {})), "onbekende sleutel weg");
  ok(!cleanGuide({ doors: "25:00" }).ok, "geen tijd");
  ok(!cleanGuide({ date: "2027-06-18", end_date: "2027-06-17" }).ok, "einde voor begin");
  ok(!cleanGuide({ info_url: "http://example.com" }).ok, "alleen https");
  ok(!cleanGuide({ text_hex: "wit" }).ok, "geen kleur");
});
