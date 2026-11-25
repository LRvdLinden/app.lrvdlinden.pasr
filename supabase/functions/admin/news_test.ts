import { chunks, cleanAudience, cleanLink, cleanNews, newsFingerprint, newsPayload, uniqueTokens, wantsAndroid, wantsIos } from "./news.ts";
import { fcmMessage } from "./fcm.ts";
import { cleanBusinessStatus } from "./business.ts";
import { message } from "./push.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("bericht controleren", () => {
  const r = cleanNews({ title: "  Nieuw  ", body: " Hallo\n\n\n\nwereld ", audience: "all" });
  ok(r.ok && r.value.title === "Nieuw" && r.value.body === "Hallo\n\nwereld" && r.value.store === null, JSON.stringify(r));
  ok(!cleanNews({ body: "", audience: "all" }).ok, "tekst verplicht");
  ok(!cleanNews({ body: "x", audience: "iedereen" }).ok, "doelgroep");
  ok(!cleanNews({ body: "x", audience: "store" }).ok, "winkel verplicht bij store");
  ok(!cleanNews({ body: "x", audience: "store", store: "AH; drop" }).ok, "winkel-id");
  const s = cleanNews({ body: "x".repeat(500), audience: "store", store: "AH" });
  ok(s.ok && s.value.body.length === 240 && s.value.store === "ah", "afkappen en kleine letters");
  const t = cleanNews({ body: "a", title: "", audience: "inactive" });
  ok(t.ok && t.value.title === null, "lege titel = null");
  ok(cleanAudience({ audience: "new" }).ok, "nieuw");
});

Deno.test("melding nieuws", () => {
  const p = newsPayload({ title: null, body: "Hoi", audience: "store", store: "ah", platform: "all", app: "pasr", url: null }, "id-1");
  ok(p.aps.alert.title === "Pasr" && p.kind === "news" && p.store === "ah" && p.id === "id-1", JSON.stringify(p));
  const q = newsPayload({ title: "T", body: "B", audience: "all", store: null, platform: "all", app: "pasr", url: null }, "id-2");
  ok(!("store" in q) && q.aps["thread-id"] === "news", "zonder winkel");
  ok(chunks([1, 2, 3, 4, 5], 2).length === 3 && chunks([], 2).length === 0, "stukken");
});

Deno.test("ondernemers", () => {
  ok(cleanBusinessStatus({ id: "8f1d3c3e-5a7b-4c2d-9e1f-0a1b2c3d4e5f", status: "approved" }).ok, "goedkeuren");
  ok(!cleanBusinessStatus({ id: "x", status: "approved" }).ok, "id");
  ok(!cleanBusinessStatus({ id: "8f1d3c3e-5a7b-4c2d-9e1f-0a1b2c3d4e5f", status: "deleted" }).ok, "status");
  const m = message("business", { accounts: 1, confirmed: 1, bots_hour: 0 }, "Bakkerij\nDe Korf");
  ok(m.aps.alert.title === "Nieuw zakelijk Pasr-account" && m.aps.alert.body.startsWith("Bakkerij De Korf ") && m.url === "pasrbeheer://businesses", m.aps.alert.body);
});

Deno.test("link onder de melding", () => {
  ok(cleanLink(undefined).ok && (cleanLink(undefined) as { url: null }).url === null, "weglaten");
  ok((cleanLink("  ") as { url: string | null }).url === null, "leeg = geen link");
  const a = cleanLink(" https://pasr.nl/zakelijk/?a=1#x ");
  ok(a.ok && a.url === "https://pasr.nl/zakelijk/?a=1#x", JSON.stringify(a));
  ok(cleanLink("https://PASR.nl").ok, "hoofdletters in host");
  for (const bad of ["http://pasr.nl", "javascript:alert(1)", "pasr://kaart", "https://", "https://localhost/x",
    "https://user:pw@pasr.nl", "https://pasr.nl:8443/", "https://pasr.nl/a b", "https://pasr.nl/a\nb", "ftp://pasr.nl",
    "https://192.168.1.1/", "https://pasr.nl/" + "a".repeat(490), 42]) {
    ok(!cleanLink(bad).ok, `geweigerd: ${String(bad).slice(0, 40)}`);
  }
  ok(cleanLink("https://pasr.nl/" + "a".repeat(400)).ok, "400 tekens mag");
});

Deno.test("platform en app", () => {
  const d = cleanAudience({ audience: "all" });
  ok(d.ok && d.platform === "all" && d.app === "pasr", "standaard alles en Pasr");
  const e = cleanAudience({ audience: "everyone", platform: "android", app: "both" });
  ok(e.ok && e.platform === "android" && e.app === "both" && !wantsIos(e) && wantsAndroid(e), JSON.stringify(e));
  ok(cleanAudience({ audience: "everyone", app: "zakelijk", platform: "ios" }).ok, "zakelijk iOS");
  ok(!cleanAudience({ audience: "everyone", platform: "windows" }).ok, "platform");
  ok(!cleanAudience({ audience: "everyone", app: "bingr" }).ok, "app");
  ok(!cleanAudience({ audience: "store", store: "ah", app: "zakelijk" }).ok, "opt-in alleen Pasr");
  const s = cleanAudience({ audience: "store", store: "ah", platform: "ios" });
  ok(s.ok && s.platform === "ios" && wantsIos(s) && !wantsAndroid(s), "bestaande doelgroep met platformfilter");
  const n = cleanNews({ body: "Storing opgelost", audience: "everyone", app: "both", url: "http://x.nl" });
  ok(!n.ok && n.error === "bad_url", "url wordt gecontroleerd");
});

Deno.test("melding met link (APNs en FCM)", () => {
  const n = { title: null, body: "Belangrijk", audience: "everyone" as const, store: null, platform: "all" as const, app: "both" as const,
    url: "https://pasr.nl/nieuws/" };
  const p = newsPayload(n, "id-3", "zakelijk");
  ok(p.url === "https://pasr.nl/nieuws/" && p.aps.alert.title === "Pasr Zakelijk", JSON.stringify(p));
  ok(newsPayload(n, "id-3").aps.alert.title === "Pasr", "standaardtitel Pasr");
  const f = fcmMessage("tok", p, "zakelijk");
  ok(f.message.data.url === "https://pasr.nl/nieuws/" && f.message.data.kind === "news" && f.message.data.channel === "zakelijk", JSON.stringify(f));
  ok(!("url" in newsPayload({ ...n, url: null }, "id-4")), "zonder link geen url");
});

Deno.test("dubbel en ontdubbelen", () => {
  const a = { title: null, body: "x", audience: "everyone" as const, store: null, platform: "all" as const, app: "pasr" as const, url: null };
  ok(newsFingerprint(a) === newsFingerprint({ ...a }), "zelfde bericht");
  ok(newsFingerprint(a) !== newsFingerprint({ ...a, platform: "ios" }), "ander platform is anders");
  ok(newsFingerprint(a) !== newsFingerprint({ ...a, url: "https://pasr.nl/" }), "andere link is anders");
  const u = uniqueTokens([{ token: "AB" }, { token: "ab" }, { token: "cd" }, { token: "" }]);
  ok(u.length === 2 && u[0].token === "AB", JSON.stringify(u));
});
