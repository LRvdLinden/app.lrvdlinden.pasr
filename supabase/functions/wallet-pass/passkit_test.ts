// deno test supabase/functions/wallet-pass/passkit_test.ts
const assert = (c: unknown, m = "assert") => { if (!c) throw new Error(m); };
const assertEquals = (a: unknown, b: unknown) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${JSON.stringify(a)} != ${JSON.stringify(b)}`);
};
import { applePassToken, businessStand, open, route, seal, stampFields, stamps, stored, tagFor, tokenHash } from "./passkit.ts";

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
