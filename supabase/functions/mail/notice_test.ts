import { buildNotice, NOTICE_MAX, parseNotices } from "./notice.ts";
import { renderMail } from "./layout.ts";
import { buildMessage } from "./outbound.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const eq = (a: unknown, b: unknown, m = "") => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m} ${JSON.stringify(a)} != ${JSON.stringify(b)}`); };
const EVIL = `Weg <img src=x onerror=alert(1)> *Zaak* [klik](https://evil.example) _x_ & "q"`;
const owner = (extra: Record<string, unknown> = {}) => ({ kind: "owner_deleted", to: "Eigenaar@Zaak.example", business: "Bakkerij Jansen", counts: { cards: 2, members: 14, events: 1, tickets: 20 }, ...extra });
const camp = (extra: Record<string, unknown> = {}) => ({ kind: "campaign_cancelled", to: "a@b.example", business: "Bakkerij Jansen", campaign: { title: "Binnenstadroute", reward: "Gratis taartje", ends_at: "2026-12-31T22:00:00Z" }, ...extra });

Deno.test("parseNotices: velden, adressen en grenzen", () => {
  const r = parseNotices({ mails: [owner(), camp(), camp(), camp({ to: "x@y.example" })] });
  ok(r.ok, "geldig");
  if (r.ok) { eq(r.value.length, 3, "dubbele mail eruit"); eq(r.value[0].to, "eigenaar@zaak.example", "kleine letters"); }
  eq(parseNotices({}), { ok: false, error: "bad_request" });
  eq(parseNotices({ mails: [] }), { ok: false, error: "bad_request" });
  eq(parseNotices({ mails: Array.from({ length: NOTICE_MAX + 1 }, (_, i) => owner({ to: `a${i}@x.example` })) }), { ok: false, error: "bad_request" });
  eq(parseNotices({ mails: [owner({ to: "kapot" })] }), { ok: false, error: "bad_address" });
  eq(parseNotices({ mails: [owner({ to: "a@x.example\r\nBcc: b@x.example" })] }), { ok: false, error: "bad_address" }, "geen kopregel-injectie");
  eq(parseNotices({ mails: [owner({ kind: "iets" })] }), { ok: false, error: "bad_request" });
  eq(parseNotices({ mails: [owner({ business: " " })] }), { ok: false, error: "bad_request" });
  eq(parseNotices({ mails: [camp({ campaign: undefined })] }), { ok: false, error: "bad_request" });
  eq(parseNotices({ mails: [owner({ counts: { cards: -1 } })] }), { ok: false, error: "bad_request" });
  eq(parseNotices({ mails: [owner({ counts: { cards: "2" } })] }), { ok: false, error: "bad_request" });
  const long = parseNotices({ mails: [owner({ business: "x".repeat(200) })] });
  ok(long.ok && long.value[0].business.length === 60, "naam begrensd");
});

Deno.test("mail aan de eigenaar: tekst en aantallen", () => {
  const r = parseNotices({ mails: [owner()] });
  if (!r.ok) throw new Error("parse");
  const m = buildNotice(r.value[0]);
  eq(m.subject, "Je zaak Bakkerij Jansen is verwijderd uit Pasr voor ondernemers");
  const t = renderMail({ brand: "zakelijk", kind: "mail", subject: m.subject, markdown: m.markdown }).text;
  ok(t.includes("Bakkerij Jansen") && t.includes("definitief") && t.includes("niet ongedaan"), "definitief");
  ok(t.includes("2 stempelkaarten met 14 leden") && t.includes("1 event met 20 tickets"), "aantallen: " + t);
  ok(t.includes("pasr.nl/zakelijk") && t.includes("zakelijk@pasr.nl") && t.includes("gratis"), "opnieuw beginnen en contact");
  ok(!t.includes("0 medewerkers"), "geen nullen");
});

Deno.test("mail aan deelnemers en organisator", () => {
  const r = parseNotices({ mails: [camp(), { kind: "participant_left", to: "o@x.example", business: "Zaak W", campaign: { title: "Actie van Y", reward: "", ends_at: null } }, camp({ campaign: { title: "Zonder datum", reward: "", ends_at: null } })] });
  if (!r.ok) throw new Error("parse");
  const a = buildNotice(r.value[0]);
  eq(a.subject, "De gezamenlijke actie Binnenstadroute is geannuleerd");
  const ta = renderMail({ brand: "zakelijk", kind: "mail", subject: a.subject, markdown: a.markdown }).text;
  ok(ta.includes("organisator") && ta.includes("Bakkerij Jansen") && ta.includes("niet meer bij Pasr voor ondernemers"), "uitleg organisator");
  ok(ta.includes("Beloningen die klanten al hebben gekregen, blijven van hen") && ta.includes("Gratis taartje"), "al uitgegeven beloningen");
  ok(ta.includes("31 december 2026") || ta.includes("1 januari 2027"), "einddatum: " + ta);
  const c = buildNotice(r.value[2]);
  ok(!/liep nog tot/.test(c.markdown) && /Er worden geen beloningen meer/.test(c.markdown), "zonder datum en beloning");
  const b = buildNotice(r.value[1]);
  eq(b.subject, "Zaak W doet niet meer mee aan Actie van Y");
  ok(/Zaak W/.test(b.markdown) && /loopt door/.test(b.markdown), "organisator: actie loopt door");
});

Deno.test("geen ongeschoonde zaaknaam of titel in de HTML (escaping, geen opmaak, geen links)", () => {
  for (const kind of ["owner_deleted", "campaign_cancelled", "participant_left"]) {
    const r = parseNotices({ mails: [{ kind, to: "a@b.example", business: EVIL, campaign: { title: EVIL, reward: EVIL, ends_at: null }, counts: { cards: 1 } }] });
    if (!r.ok) throw new Error("parse " + kind);
    const n = buildNotice(r.value[0]);
    const out = renderMail({ brand: "zakelijk", kind: "mail", subject: n.subject, markdown: n.markdown });
    ok(!/<img[^>]*onerror|<img src=x/i.test(out.html), kind + ": geen img uit de naam");
    ok(!/href="https:\/\/evil\.example/.test(out.html), kind + ": geen link uit de naam");
    ok(!/<(em|i)>(Zaak|x)<\/(em|i)>|<b>Zaak/.test(out.html.replace(/<b style[^>]*>/g, "<strong>")), kind + ": geen opmaak uit de naam");
    ok(out.html.includes("&lt;img src=x onerror=alert(1)&gt;"), kind + ": letterlijk en ge-escaped: " + out.html.slice(out.html.indexOf("Weg") - 20, out.html.indexOf("Weg") + 160));
    ok(!/[\r\n]/.test(out.subject), "onderwerp op één regel");
  }
});

Deno.test("merk Pasr Zakelijk: afzender, kop, kleur en geen afmeldlink", () => {
  const r = parseNotices({ mails: [owner()] });
  if (!r.ok) throw new Error("parse");
  const n = buildNotice(r.value[0]);
  const msg = buildMessage({
    brand: "zakelijk", kind: "mail", from: "Pasr Zakelijk <zakelijk@pasr.nl>", replyTo: "zakelijk@pasr.nl", to: [r.value[0].to], cc: [], bcc: [],
    subject: n.subject, markdown: n.markdown, messageId: "<x@pasr.nl>",
  });
  ok(msg.from.startsWith("Pasr Zakelijk"), "afzender");
  ok(msg.html.includes("Pasr voor ondernemers") && msg.html.includes("#2ED3A6") && msg.html.includes("mail-icon-zakelijk.png"), "huisstijl zakelijk");
  ok(!msg.html.includes("Meld je hier af") && !msg.headers["List-Unsubscribe"], "geen afmeldlink bij een zakelijke mededeling");
  ok(msg.envelope.to.length === 1 && !msg.cc && msg.to === "eigenaar@zaak.example", "één ontvanger, geen cc/bcc");
});
