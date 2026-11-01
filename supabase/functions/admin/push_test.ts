// deno test supabase/functions/admin/push_test.ts
import { apnsJwt, apnsResult, cleanPrefs, cleanRegister, DEFAULT_PREFS, message, pemToDer, wants } from "./push.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const TOKEN = "ab".repeat(32);

Deno.test("registreren: geldige invoer en standaard-schakelaars", () => {
  const r = cleanRegister({ device_id: "dev-12345678", apns_token: TOKEN.toUpperCase(), platform: "macos", sandbox: true, app_build: 3 });
  ok(r.ok, "ok");
  if (r.ok) {
    ok(r.value.apns_token === TOKEN, "kleine letters");
    ok(JSON.stringify(r.value.prefs) === JSON.stringify(DEFAULT_PREFS), "standaard prefs");
  }
});

Deno.test("registreren: foute invoer", () => {
  ok(!cleanRegister({ device_id: "x", apns_token: TOKEN, platform: "ios" }).ok, "korte id");
  ok(!cleanRegister({ device_id: "dev-12345678", apns_token: "zz", platform: "ios" }).ok, "token");
  ok(!cleanRegister({ device_id: "dev-12345678", apns_token: TOKEN, platform: "android" }).ok, "platform");
  ok(!cleanRegister({ device_id: "dev-12345678", apns_token: TOKEN, platform: "ios", prefs: { foo: true } }).ok, "prefs");
  ok(!cleanRegister({ device_id: "dev-12345678", apns_token: TOKEN, platform: "ios", app_build: -1 }).ok, "build");
});

Deno.test("schakelaars", () => {
  ok(cleanPrefs({ bots: false })?.bots === false && cleanPrefs({ bots: false })?.signups === true, "aanvullen");
  ok(cleanPrefs({ bots: "nee" }) === null, "geen boolean");
  ok(wants({ signups: false }, "signup") === false, "uit");
  ok(wants(null, "deleted") === true, "standaard");
  ok(wants({}, "confirmed") === false, "bevestigd staat standaard uit");
});

Deno.test("meldingen: nooit persoonsgegevens, wel aantallen", () => {
  const m = message("signup", { accounts: 1234, confirmed: 1000, bots_hour: 0 });
  ok(m.aps.alert.body.includes("1.234 accounts"), m.aps.alert.body);
  ok(m.url === "pasrbeheer://accounts", "url");
  ok(message("signup", { accounts: 1, confirmed: 0, bots_hour: 0 }).aps.alert.body.includes("1 account."), "enkelvoud");
  const b = message("bot", { accounts: 1, confirmed: 1, bots_hour: 4 }, "honeypot");
  ok(b.aps.alert.body.startsWith("4 aanmeldingen") && b.aps.alert.body.includes("honeypot"), b.aps.alert.body);
  ok(message("bot", { accounts: 1, confirmed: 1, bots_hour: 1 }, "<script>").aps.alert.body.includes("verdacht"), "onbekende reden");
});

Deno.test("APNs: uitkomst", () => {
  ok(apnsResult(200, "").ok, "200");
  const r = apnsResult(410, "Unregistered");
  ok(!r.ok && r.invalid, "410");
  const t = apnsResult(429, "TooManyRequests");
  ok(!t.ok && !t.invalid && t.error === "apns_TooManyRequests", "429");
});

Deno.test("APNs: JWT met een P-256-sleutel", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\\n${btoa(String.fromCharCode(...der))}\\n-----END PRIVATE KEY-----`;
  ok(pemToDer(pem).length === der.length, "pem met letterlijke \\n");
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const jwt = await apnsJwt(key, "ABC123DEFG", "EU3UY476T6", 1_800_000_000);
  const [h, c, s] = jwt.split(".");
  const dec = (x: string) => JSON.parse(atob(x.replace(/-/g, "+").replace(/_/g, "/")));
  ok(dec(h).kid === "ABC123DEFG" && dec(c).iss === "EU3UY476T6", "kop en claims");
  const sig = Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=="), (x) => x.charCodeAt(0));
  ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, sig, new TextEncoder().encode(`${h}.${c}`)), "handtekening");
});
