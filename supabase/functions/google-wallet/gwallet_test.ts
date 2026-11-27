import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  b64url, barcodeType, cleanHex, cleanLogo, genericObject, importPrivateKey, isKey, isUuid, modules, objectId, saveClaims,
  signJwt, stand,
} from "./gwallet.ts";

const ID = "6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f";

Deno.test("object-id en invoercontrole", () => {
  assertEquals(objectId("3388000000012345678", ID), "3388000000012345678.pasr_6f1c2d3e4a5b4c6d8e9f0a1b2c3d4e5f");
  assert(isUuid(ID));
  assert(!isUuid("x"));
  assert(isKey("a".repeat(48)));
  assert(!isKey("zz"));
});

Deno.test("barcodetypes vallen terug op Code 128 als de waarde niet past", () => {
  assertEquals(barcodeType("ean13", "2620000000000"), "EAN_13");
  assertEquals(barcodeType("ean13", "12345"), "CODE_128");
  assertEquals(barcodeType("itf", "12345678901234"), "ITF_14");
  assertEquals(barcodeType("itf", "1234"), "CODE_128");
  assertEquals(barcodeType("qr", "PZABCDEFGHJK23"), "QR_CODE");
  assertEquals(barcodeType(undefined, "x"), "CODE_128");
});

Deno.test("kleur en logo", () => {
  assertEquals(cleanHex("00a0e2"), "#00A0E2");
  assertEquals(cleanHex("rood"), "#6A5CFF");
  assertEquals(cleanLogo("data:image/png;base64,iVBORw0KGgo="), "iVBORw0KGgo=");
  assertEquals(cleanLogo("<script>"), null);
});

Deno.test("stempelkaart: stand, header en regels", () => {
  const card = { id: ID, name: "Koffiebar", number: "PZABCDEFGHJK2345", format: "qr", kind: "stamps",
    details: { stampsTotal: 10, stampsCount: 3, reward: "Gratis koffie", issuer: "business", memberCode: "PZABCDEFGHJK2345" } };
  const s = stand(card, { count: 4 });
  assertEquals(s, { total: 10, count: 4, reward: "Gratis koffie" });
  const obj = genericObject("123456", card, "https://pasr.nl/assets/icon-512.png", { count: 4 });
  assertEquals((obj.header as { defaultValue: { value: string } }).defaultValue.value, "4 van 10 stempels");
  assertEquals((obj.barcode as { type: string }).type, "QR_CODE");
  const m = modules(card, s);
  assertEquals(m[0].id, "stamps");
  assert(m[0].body.startsWith("●●●●○"));
});

Deno.test("kortingscode als tekst en voucher met einddatum", () => {
  const code = genericObject("123456", { id: ID, name: "Bol", number: "KORTING10", kind: "code", expiresAt: "2026-12-31T10:00:00Z" }, "x");
  assertEquals((code.barcode as { type: string }).type, "TEXT_ONLY");
  assert(code.validTimeInterval);
  const v = genericObject("123456", { id: ID, name: "Bol", number: "6064", kind: "voucher", balance: 12.5, currency: "EUR" }, "x");
  assert((v.textModulesData as { id: string }[]).some((t) => t.id === "balance"));
  assertEquals((v.subheader as { defaultValue: { value: string } }).defaultValue.value, "Cadeaukaart");
});

Deno.test("JWT met RS256 is te controleren", async () => {
  const pair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----\n`;
  const key = await importPrivateKey(pem);
  const jwt = await signJwt(saveClaims("pasr@example.iam.gserviceaccount.com", "123.pasr_x"), key);
  const [h, p, s] = jwt.split(".");
  const sig = Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - s.length % 4) % 4)), (c) => c.charCodeAt(0));
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", pair.publicKey, sig, new TextEncoder().encode(`${h}.${p}`));
  assert(ok);
  const payload = JSON.parse(atob(p.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - p.length % 4) % 4)));
  assertEquals(payload.typ, "savetowallet");
  assertEquals(payload.payload.genericObjects[0].id, "123.pasr_x");
  assertEquals(b64url("ab?"), "YWI_");
});

// ---- tickets en klantenkaart met barcode ----
import { eventClassId, eventTicketClass, eventTicketObject, loyaltyClass, loyaltyObject, saveClaimsFor, serverCode } from "./gwallet.ts";

const EV = "11111111-2222-4333-8444-555555555555", TK = "66666666-7777-4888-8999-aaaaaaaaaaaa";

Deno.test("eventTicket: klasse per event, object per ticket met QR en houder", () => {
  const d = { kind: "event_ticket", ticket_id: TK, code: "K7Q2MXDATRZ5VWUY3ST2HJBN", status: "registered", event_id: EV, event_name: "Winterborrel",
    starts_at: "2026-12-19T15:00:00Z", ends_at: "2026-12-19T18:00:00Z", doors_at: null, address: "Hoofdstraat 12", color: "#1f3a5f",
    business_name: "Korenschoof", holder_name: "Anna de Vries", ticket_type: "Toegang", index: 2, of: 2 };
  const c = eventTicketClass("338800", d, "https://x/logo.png");
  assertEquals(c.id, "338800.pasr_event_11111111222243338444555555555555");
  assertEquals(c.hexBackgroundColor, "#1F3A5F");
  const o = eventTicketObject("338800", d);
  assertEquals(o.classId, eventClassId("338800", EV));
  assertEquals(o.barcode, { type: "QR_CODE", value: d.code, alternateText: d.code });
  assertEquals(o.ticketHolderName, "Anna de Vries");
  assertEquals(o.groupingInfo.groupingId, EV);
  assertEquals(eventTicketObject("338800", { ...d, event_status: "cancelled" }).state, "INACTIVE");
  assert(!JSON.stringify(o).includes("birth"));
  assertEquals(saveClaimsFor("sa@x", "eventTicketObjects", o.id).payload, { eventTicketObjects: [{ id: o.id }] });
  assertEquals(serverCode("event_ticket", TK.toUpperCase()), `ET:${TK}`);
});

Deno.test("loyalty: lidnummer als EAN-13, spaarstand en korting", () => {
  const d = { kind: "member_card", member_id: TK, card_id: EV, name: "Korenschoof Klantenkaart", color: "#8a4b1f", business_name: "Korenschoof",
    number: "2123456789018", barcode_type: "ean13", member_name: null, discount_now: { percent: 15, label: "15% op alles" },
    next_discount: null, saving: { count: 6, target: 10, reward: "Gratis gebakje", unit: "visits" }, active: true };
  assertEquals(loyaltyClass("338800", d, "https://x").programName, "Korenschoof Klantenkaart");
  const o = loyaltyObject("338800", d);
  assertEquals(o.barcode.type, "EAN_13");
  assertEquals(o.loyaltyPoints?.balance.string, "6/10");
  assertEquals(o.secondaryLoyaltyPoints?.balance.string, "15%");
  assertEquals("accountName" in o, false);
  assertEquals(loyaltyObject("338800", { ...d, barcode_type: "code128", number: "KS-000124" }).barcode.type, "CODE_128");
  assertEquals(loyaltyObject("338800", { ...d, active: false }).state, "INACTIVE");
});
