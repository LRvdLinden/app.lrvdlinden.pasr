import { assert, assertEquals } from "jsr:@std/assert@1";
import { cleanFcmToken, fcmMessage, fcmResult, fcmUrl, importRsaKey, memberPayload, oauthAssertion, parseServiceAccount } from "./fcm.ts";
import { newsPayload } from "./news.ts";

const SA = { project_id: "pasr-123", client_email: "fcm@pasr-123.iam.gserviceaccount.com", private_key: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n" };

Deno.test("service-account als JSON of base64, anders null", () => {
  assertEquals(parseServiceAccount(JSON.stringify(SA))?.project_id, "pasr-123");
  assertEquals(parseServiceAccount(btoa(JSON.stringify(SA)))?.client_email, SA.client_email);
  assertEquals(parseServiceAccount(""), null);
  assertEquals(parseServiceAccount("{\"project_id\":\"x\"}"), null);
  assertEquals(parseServiceAccount("geen json"), null);
});

Deno.test("FCM-tokens controleren", () => {
  assertEquals(cleanFcmToken("  dQw4w9WgXcQ:APA91bHun4MxP5egoKMwt2KZFBaFUH-1RYqx  "), "dQw4w9WgXcQ:APA91bHun4MxP5egoKMwt2KZFBaFUH-1RYqx");
  assertEquals(cleanFcmToken("kort"), null);
  assertEquals(cleanFcmToken("a b c d e f g h i j k l m n o p"), null);
  assertEquals(cleanFcmToken(42), null);
});

Deno.test("APNs-payload wordt een data-bericht voor FCM (alles tekst)", () => {
  const p = newsPayload({ title: "Albert Heijn", body: "Bonus deze week", audience: "store", store: "ah" }, "c1");
  const m = fcmMessage("tok_1234567890abcdefghij", p, "news");
  assertEquals(m.message.token, "tok_1234567890abcdefghij");
  assertEquals(m.message.data.title, "Albert Heijn");
  assertEquals(m.message.data.body, "Bonus deze week");
  assertEquals(m.message.data.kind, "news");
  assertEquals(m.message.data.store, "ah");
  assertEquals(m.message.data.id, "c1");
  assertEquals(m.message.data.channel, "news");
  assertEquals(m.message.android.priority, "HIGH");
  assert(Object.values(m.message.data).every((v) => typeof v === "string"));
  assert(!("aps" in m.message.data));
  assertEquals(fcmUrl("pasr-123"), "https://fcm.googleapis.com/v1/projects/pasr-123/messages:send");
});

Deno.test("ongeldige tokens herkennen", () => {
  assertEquals(fcmResult(200, {}), { ok: true });
  const gone = fcmResult(404, { error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } });
  assert(!gone.ok && gone.invalid && gone.error === "fcm_UNREGISTERED");
  const bad = fcmResult(400, { error: { status: "INVALID_ARGUMENT" } });
  assert(!bad.ok && bad.invalid);
  const busy = fcmResult(503, { error: { status: "UNAVAILABLE" } });
  assert(!busy.ok && !busy.invalid);
  const quota = fcmResult(429, { error: { details: [{ errorCode: "QUOTA_EXCEEDED" }] } });
  assert(!quota.ok && !quota.invalid && quota.error === "fcm_QUOTA_EXCEEDED");
});

Deno.test("melding bij een stempel en bij een volle kaart", () => {
  const card = { business: "Koffiebar De Boon", reward: "Gratis koffie", stamps_total: 10 };
  const one = memberPayload(card, "PZABCDEFGHJK2345", 3, 4);
  assertEquals(one.aps.alert.title, "Stempel erbij bij Koffiebar De Boon");
  assertEquals(one.aps.alert.body, "Je hebt er nu 4 van de 10.");
  assertEquals(one.kind, "stamps");
  assertEquals(memberPayload(card, "PZX", 3, 5).aps.alert.title, "2 stempels erbij bij Koffiebar De Boon");
  const full = memberPayload(card, "PZX", 9, 10);
  assertEquals(full.aps.alert.title, "Je stempelkaart van Koffiebar De Boon is vol");
  assertEquals(full.aps.alert.body, "Wissel je beloning in: Gratis koffie.");
  assertEquals(memberPayload(card, "PZX", 10, 0).aps.alert.body, "Je stand is bijgewerkt: 0 van de 10.");
  assertEquals(fcmMessage("t".repeat(30), full, "stamps").message.data.code, "PZX");
});

Deno.test("OAuth-assertion is een geldige RS256-JWT met de juiste scope", async () => {
  const pair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  const key = await importRsaKey(`-----BEGIN PRIVATE KEY-----\\n${btoa(bin)}\\n-----END PRIVATE KEY-----`);
  const jwt = await oauthAssertion(SA, key, 1_800_000_000);
  const [h, p, s] = jwt.split(".");
  const dec = (x: string) => Uint8Array.from(atob(x.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - x.length % 4) % 4)), (c) => c.charCodeAt(0));
  assert(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", pair.publicKey, dec(s), new TextEncoder().encode(`${h}.${p}`)));
  const claims = JSON.parse(new TextDecoder().decode(dec(p)));
  assertEquals(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(claims.iss, SA.client_email);
  assertEquals(claims.exp - claims.iat, 3600);
});
