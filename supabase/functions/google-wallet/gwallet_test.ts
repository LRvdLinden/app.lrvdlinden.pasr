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
