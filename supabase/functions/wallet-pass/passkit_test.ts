// deno test supabase/functions/wallet-pass/passkit_test.ts
const assert = (c: unknown, m = "assert") => { if (!c) throw new Error(m); };
const assertEquals = (a: unknown, b: unknown) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${JSON.stringify(a)} != ${JSON.stringify(b)}`);
};
import {
  amsterdamOffset, applePassToken, businessStand, dutchDates, open, route, seal, stampFields, stamps, stored, tagFor, ticketGroup, ticketPass, tokenHash,
} from "./passkit.ts";

const serial = "3F2504E0-4F89-11D3-9A0C-0305E82C3301";

Deno.test("route: de verzoeken van Wallet", () => {
  const base = "/wallet-pass/v1";
  assertEquals(route("POST", `${base}/devices/abc123/registrations/pass.nl.lrvdlinden.pasr/${serial}`),
    { kind: "register", device: "abc123", passType: "pass.nl.lrvdlinden.pasr", serial });
  assertEquals(route("DELETE", `/functions/v1/wallet-pass/v1/devices/abc123/registrations/pass.nl.lrvdlinden.pasr/${serial}`)?.kind, "unregister");
  assertEquals(route("GET", `${base}/devices/abc123/registrations/pass.nl.lrvdlinden.pasr`)?.kind, "serials");
  assertEquals(route("GET", `${base}/passes/pass.nl.lrvdlinden.pasr/${serial}`), { kind: "pass", passType: "pass.nl.lrvdlinden.pasr", serial });
  assertEquals(route("POST", `${base}/log`), { kind: "log" });
  assertEquals(route("POST", "/wallet-pass"), null);
  assertEquals(route("GET", `${base}/passes/x/../../etc`), null);
});

Deno.test("ApplePass-token uit de header", () => {
  const t = "a".repeat(64);
  assertEquals(applePassToken(`ApplePass ${t}`), t);
  assertEquals(applePassToken("Bearer x"), null);
  assertEquals(applePassToken(null), null);
});

Deno.test("versleutelen en weer openen met het token", async () => {
  const token = "0123456789abcdef".repeat(4);
  const card = { id: serial, name: "Bakker", number: "", format: "qr", colorHex: "#112233", kind: "stamps", stampsCount: 3 };
  const box = await seal(card, token);
  assertEquals(await open(box, token), card);
  let failed = false;
  try { await open(box, "f".repeat(64)); } catch { failed = true; }
  assert(failed, "verkeerd token mag niet openen");
  assertEquals((await tokenHash(token)).length, 64);
  assert(!box.includes("Bakker"));
});

Deno.test("stempels binnen de grenzen", () => {
  assertEquals(stamps({ id: serial, name: "x", number: "", format: "qr", colorHex: "#000000", stampsTotal: 50, stampsCount: 99 }).total, 30);
  const s = stamps({ id: serial, name: "x", number: "", format: "qr", colorHex: "#000000", stampsTotal: 10, stampsCount: 7, reward: "1 gratis koffie" });
  assertEquals([s.count, s.left, s.full], [7, 3, false]);
  assertEquals(s.dots, "●●●●●●●○○○");
  const f = stampFields({ id: serial, name: "x", number: "", format: "qr", colorHex: "#000000", stampsTotal: 10, stampsCount: 7, reward: "1 gratis koffie" });
  assertEquals(f.header.value, "7/10");
  assertEquals(f.auxiliary.at(-1)?.value, "3 tot 1 gratis koffie");
  assertEquals(f.primary.length, 1);
  const big = stampFields({ id: serial, name: "x", number: "", format: "qr", colorHex: "#000000", stampsTotal: 20, stampsCount: 20 });
  assertEquals(big.primary.length, 0);
  assertEquals(big.auxiliary.at(-1)?.value, "Vol: wissel je beloning in");
});

Deno.test("bewaard zonder token en actie", () => {
  const s = stored({ id: serial, name: "x", number: "1", format: "qr", colorHex: "#000000", token: "a".repeat(64), push: true, action: "update" });
  assertEquals(Object.keys(s).includes("token"), false);
  assertEquals(Object.keys(s).includes("action"), false);
});

Deno.test("stand van de zaak lezen", () => {
  assertEquals(businessStand({ stamps_count: 4, stamps_total: 8, reward: "Taart" }), { total: 8, count: 4, reward: "Taart" });
  assertEquals(businessStand([{ stampsCount: "2" }]), { total: undefined, count: 2, reward: undefined });
  assertEquals(businessStand(null), null);
  assertEquals(tagFor("2026-11-22T10:00:00Z"), String(Date.parse("2026-11-22T10:00:00Z")));
});

Deno.test("ticket: datums in het Nederlands en de Nederlandse tijdzone", () => {
  assertEquals(dutchDates("2027-06-18"), "18 juni 2027");
  assertEquals(dutchDates("2027-07-15", "2027-07-18"), "15 – 18 juli 2027");
  assertEquals(dutchDates("2027-06-30", "2027-07-02"), "30 juni – 2 juli 2027");
  assertEquals(dutchDates("geen datum"), null);
  assertEquals(amsterdamOffset(2027, 6, 18), "+02:00");
  assertEquals(amsterdamOffset(2027, 1, 10), "+01:00");
  assertEquals(amsterdamOffset(2027, 3, 28), "+02:00");   // laatste zondag van maart 2027
  assertEquals(amsterdamOffset(2027, 10, 31), "+01:00");  // laatste zondag van oktober 2027
});

Deno.test("ticket: eventTicket met merkkleur, evenementvelden en groep", () => {
  const base = { formatVersion: 1, backgroundColor: "rgb(0, 0, 0)", foregroundColor: "rgb(255, 255, 255)", labelColor: "x",
    barcodes: [{ format: "PKBarcodeFormatQR", message: "ABC123" }],
    storeCard: { headerFields: [], secondaryFields: [], backFields: [{ key: "pasr", label: "Pasr", value: "pasr.nl" }] } };
  const card = { id: serial, name: "Drakenboot – KIDS Early Bird", number: "ABC123", format: "qr", colorHex: "#1FB5B0", kind: "ticket",
    event: "Drakenboot 2027", brand: "Drakenboot", ticketType: "KIDS Early Bird", ticketNote: "t/m 14 jaar", date: "2027-06-18",
    doors: "17:00", ends: "01:00", venue: "Zwitsalpark", city: "Apeldoorn", infoURL: "https://www.drakenboot.nl/tickets", textHex: "#ffffff" };
  const p = ticketPass(base, card) as Record<string, any>;
  assert(!("storeCard" in p), "geen storeCard meer");
  assertEquals(p.eventTicket.primaryFields[0], { key: "event", label: "DRAKENBOOT", value: "Drakenboot 2027" });
  assertEquals(p.eventTicket.headerFields[0].value, "KIDS Early Bird");
  assertEquals(p.eventTicket.secondaryFields.map((f: any) => f.value), ["18 juni 2027", "17:00 – 01:00"]);
  assertEquals(p.eventTicket.auxiliaryFields.map((f: any) => f.label), ["LOCATIE", "LEEFTIJD"]);
  assertEquals(p.eventTicket.backFields.map((f: any) => f.key), ["info", "route", "pasr"]);
  assertEquals(p.backgroundColor, "rgb(31, 181, 176)");
  assertEquals(p.foregroundColor, "rgb(255, 255, 255)");
  assertEquals(p.relevantDate, "2027-06-18T17:00:00+02:00");
  assertEquals(p.expirationDate, "2027-06-19T06:00:00+02:00");
  assertEquals(p.logoText, "Drakenboot");
  assertEquals(p.barcodes, base.barcodes);
  // alle Drakenboot-tickets in één groep, een ander evenement apart
  const regular = ticketPass(base, { ...card, name: "Drakenboot – Regular", ticketType: "Regular", ticketNote: undefined }) as Record<string, any>;
  assertEquals(regular.groupingIdentifier, p.groupingIdentifier);
  assertEquals(p.groupingIdentifier, "pasr-event-drakenboot-2027");
  assert(ticketGroup({ ...card, event: "Zwarte Cross 2027" }) !== p.groupingIdentifier, "ander evenement, andere groep");
});

Deno.test("ticket: eigen ticket zonder catalogus blijft werken", () => {
  const p = ticketPass({ storeCard: {} }, { id: serial, name: "Concert", number: "1", format: "qr", colorHex: "#222222", kind: "ticket",
    eventDate: "2027-03-01T20:00:00Z", venue: "Ziggo Dome", seat: "Rij 4" }) as Record<string, any>;
  assertEquals(p.eventTicket.primaryFields[0].value, "Concert");
  assertEquals(p.eventTicket.secondaryFields[0].dateStyle, "PKDateStyleMedium");
  assertEquals(p.eventTicket.auxiliaryFields.map((f: any) => f.value), ["Ziggo Dome", "Rij 4"]);
  assertEquals(p.groupingIdentifier, "pasr-event-concert");
  assert(!("relevantDate" in p), "datum komt uit index.ts");
});

// ---- tickets en klantenkaart met barcode uit de database (27-11-2026) ----
import { amsterdam, eventTicketCard, memberCardCard, memberPass, serverCard, serverCode } from "./passkit.ts";

const EV = "11111111-2222-4333-8444-555555555555", TK = "66666666-7777-4888-8999-aaaaaaaaaaaa";
const ticketData = {
  kind: "event_ticket", ticket_id: TK, code: "K7Q2MXDATRZ5VWUY3ST2HJBN", status: "registered", event_id: EV,
  event_name: "Winterborrel", starts_at: "2026-12-19T15:00:00Z", ends_at: "2026-12-19T18:00:00Z", doors_at: "2026-12-19T14:45:00Z",
  address: "Hoofdstraat 12, Apeldoorn", color: "#1f3a5f", event_status: "published", business_name: "Bakkerij de Korenschoof",
  business_logo: null, holder_name: "Anna de Vries", ticket_type: "Toegang", index: 1, of: 2,
};

Deno.test("Nederlandse tijd (winter en zomer)", () => {
  assertEquals(amsterdam("2026-12-19T15:00:00Z"), { date: "2026-12-19", time: "16:00" });
  assertEquals(amsterdam("2027-07-06T15:30:00Z"), { date: "2027-07-06", time: "17:30" });
  assertEquals(amsterdam("x"), null);
});

Deno.test("eventTicket uit de database: QR = code, groep = event-id, naam van de houder", () => {
  const card = serverCard("event_ticket", ticketData)!;
  assertEquals([card.format, card.number, card.kind, card.date, card.doors, card.ends], ["qr", ticketData.code, "ticket", "2026-12-19", "15:45", "19:00"]);
  const pass = ticketPass({ storeCard: { backFields: [] } }, card) as Record<string, any>;
  assertEquals(pass.groupingIdentifier, EV);
  assert(pass.eventTicket.auxiliaryFields.some((f: any) => f.key === "holder" && f.value === "Anna de Vries"), "houder");
  assert(pass.eventTicket.backFields.some((f: any) => f.value === "1 van 2"), "1 van 2");
  assert(!JSON.stringify(pass).includes("birth"), "geen geboortedatum");
  assertEquals(pass.voided, undefined);
  assertEquals((ticketPass({}, eventTicketCard({ ...ticketData, status: "cancelled" })) as Record<string, unknown>).voided, true);
  assertEquals(serverCode(card), `ET:${TK}`);
  assertEquals(serverCard("member_card", ticketData), null);
});

Deno.test("klantenkaart: korting rechtsboven, lidnummer, spaarstand; EAN-13 wordt Code 128", () => {
  const data = { kind: "member_card", member_id: TK, card_id: EV, name: "Korenschoof Klantenkaart", color: "#8A4B1F", logo: null,
    business_name: "Bakkerij de Korenschoof", number: "2123456789018", barcode_type: "ean13", member_name: "Anna de Vries",
    member_since: "2026-03-01T10:00:00Z", discount_now: { percent: 15, label: "15% op alles", until: "2026-12-15T23:00:00Z" },
    next_discount: { percent: 20, label: "happy hour", starts_at: "2026-12-08T16:00:00Z" },
    saving: { count: 6, target: 10, reward: "Gratis gebakje", unit: "visits", can_redeem: false }, active: true };
  const card = memberCardCard(data);
  assertEquals([card.kind, card.format, serverCode(card)], ["member", "ean13", `MC:${TK}`]);
  const pass = memberPass({ storeCard: {} }, card) as Record<string, any>;
  assertEquals(pass.storeCard.headerFields[0].value, "15%");
  assertEquals(pass.storeCard.secondaryFields.map((f: any) => f.value), ["2123456789018", "Anna de Vries"]);
  assert(pass.storeCard.auxiliaryFields.some((f: any) => f.key === "saving" && f.value === "6/10"), "spaarstand");
  const none = memberPass({ storeCard: {} }, memberCardCard({ ...data, discount_now: null, saving: null, active: false })) as Record<string, any>;
  assertEquals(none.storeCard.headerFields[0].key, "brand");
  assert(none.storeCard.auxiliaryFields.some((f: any) => f.key === "next"), "volgende korting");
  assertEquals(none.voided, true);
});
