import { buildNotices, cleanBusinessDelete, cleanBusinessDetail, cleanBusinessSettings, confirmMatches, deleteAuditLine, mailsReport } from "./business.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const ID = "8f1d3c3e-5a7b-4c2d-9e1f-0a1b2c3d4e5f";

Deno.test("zaak-detail", () => {
  const d = cleanBusinessDetail({ id: ID });
  ok(d.ok && d.limit === 200 && d.days === 30, "standaard");
  ok(!cleanBusinessDetail({ id: "x" }).ok, "id");
  ok(!cleanBusinessDetail({ id: ID, limit: 0 }).ok && !cleanBusinessDetail({ id: ID, limit: 5000 }).ok, "limit");
  ok(!cleanBusinessDetail({ id: ID, days: 400 }).ok && !cleanBusinessDetail({ id: ID, days: 1.5 }).ok, "days");
  const e = cleanBusinessDetail({ id: ID, limit: "50", days: 7 });
  ok(e.ok && e.limit === 50 && e.days === 7, "tekst als getal");
});

Deno.test("instellingen: afkoeltijd en max per scan", () => {
  const s = cleanBusinessSettings({ id: ID, cooldown_minutes: 0, max_per_scan: 30 });
  ok(s.ok && s.settings.cooldown_minutes === 0 && s.settings.max_per_scan === 30, "grenzen mogen");
  ok(!cleanBusinessSettings({ id: ID, cooldown_minutes: 1441 }).ok, "afkoeltijd te hoog");
  ok(!cleanBusinessSettings({ id: ID, cooldown_minutes: -1 }).ok, "afkoeltijd negatief");
  ok(!cleanBusinessSettings({ id: ID, max_per_scan: 0 }).ok && !cleanBusinessSettings({ id: ID, max_per_scan: 31 }).ok, "max per scan");
  ok(!cleanBusinessSettings({ id: ID, max_per_scan: "drie" }).ok, "geen getal");
  ok(!cleanBusinessSettings({ id: ID }).ok, "niets om op te slaan");
  const one = cleanBusinessSettings({ id: ID, cooldown_minutes: 15 });
  ok(one.ok && !("max_per_scan" in one.settings), "alleen wat meegegeven is");
});

Deno.test("instellingen: vindbaar in Pasr, adres en locatie", () => {
  const s = cleanBusinessSettings({ id: ID, listed: false });
  ok(s.ok && s.settings.listed === false, "uit de lijst halen");
  ok(!cleanBusinessSettings({ id: ID, listed: "nee" }).ok, "listed is boolean");
  const a = cleanBusinessSettings({ id: ID, address: "  Hoofdstraat   1,  Apeldoorn ", lat: 52.21, lng: 5.97 });
  ok(a.ok && a.settings.address === "Hoofdstraat 1, Apeldoorn" && a.settings.lat === 52.21, "adres en locatie");
  ok(!cleanBusinessSettings({ id: ID, lat: 52.2 }).ok, "lat zonder lng");
  ok(!cleanBusinessSettings({ id: ID, lat: 100, lng: 5 }).ok, "lat buiten bereik");
  const n = cleanBusinessSettings({ id: ID, address: null, lat: null, lng: null });
  ok(n.ok && n.settings.address === null && n.settings.lat === null, "wissen");
});

import { cleanBusinessInput, cleanCardInput, dbError } from "./business.ts";

Deno.test("zaak aanmaken door het beheer", () => {
  const r = cleanBusinessInput({ business: { name: "  Koffie   A ", city: "Deventer", email: " A@X.nl ", website: "koffie-a.nl/", listed: false,
    cooldown_minutes: "15", max_per_scan: 5, address: "Brink 1" } }, true);
  ok(r.ok && r.value.name === "Koffie A" && r.value.email === "a@x.nl" && r.value.website === "https://koffie-a.nl", JSON.stringify(r));
  ok(r.ok && r.value.cooldown_minutes === 15 && r.value.listed === false && !("id" in r.value), "instellingen");
  ok(!cleanBusinessInput({ business: { name: "X" } }, true).ok, "naam te kort");
  ok(!cleanBusinessInput({ business: {} }, true).ok, "naam verplicht");
  ok(!cleanBusinessInput({ business: { name: "Goed", email: "geen-mail" } }, true).ok, "e-mail");
  ok(!cleanBusinessInput({ business: { name: "Goed", website: "javascript:alert(1)" } }, true).ok, "website");
  ok(!cleanBusinessInput({ business: { name: "Goed", website: "http://localhost" } }, true).ok, "geen hostnaam");
  ok(!cleanBusinessInput({ business: { name: "Goed", max_per_scan: 31 } }, true).ok, "max per scan");
  ok(!cleanBusinessInput({ business: { name: "Goed", cooldown_minutes: 2000 } }, true).ok, "afkoeltijd");
  ok(!cleanBusinessInput({ business: "Goed" }, true).ok, "geen object");
  const e = cleanBusinessInput({ business: { name: "Goed", email: "" } }, true);
  ok(e.ok && e.value.email === "", "zonder eigenaar");
});

Deno.test("zaak bewerken door het beheer", () => {
  ok(!cleanBusinessInput({ business: { name: "Goed" } }, false).ok, "id verplicht");
  const r = cleanBusinessInput({ id: ID, business: { website: null, address: "" } }, false);
  ok(r.ok && r.value.website === null && r.value.address === null && !("name" in r.value), "wissen en laten staan");
  ok(!cleanBusinessInput({ id: ID, business: {} }, false).ok, "niets te bewaren");
});

Deno.test("stempelkaart van het beheer", () => {
  const r = cleanCardInput({ business_id: ID, card: { name: " Koffiekaart ", reward: "1 gratis koffie", stamps_total: 8, color: "#12a77e",
    text_color: "#ffffff", logo: "data:image/png;base64,iVBORw0KGgoAAAA=", published: true } });
  ok(r.ok && r.card.color === "#12A77E" && r.card.text_color === "#FFFFFF" && r.card.logo === "iVBORw0KGgoAAAA=" && r.card.published === true, JSON.stringify(r));
  ok(r.ok && !("id" in r.card), "nieuw zonder id");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", stamps_total: 1 } }).ok, "minstens 2 stempels");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", stamps_total: 31 } }).ok, "hoogstens 30 stempels");
  ok(!cleanCardInput({ business_id: ID, card: { name: "", reward: "r" } }).ok, "naam");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "" } }).ok, "beloning");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", color: "rood" } }).ok, "kleur");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", logo: "<svg>" } }).ok, "logo");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", logo: "iVBORw0KGgo" + "A".repeat(220_000) } }).ok, "logo te groot");
  ok(!cleanCardInput({ business_id: "x", card: { name: "K", reward: "r" } }).ok, "zaak-id");
  const keep = cleanCardInput({ business_id: ID, card: { id: ID, name: "K", reward: "r" } });
  ok(keep.ok && !("logo" in keep.card) && !("text_color" in keep.card) && !("published" in keep.card), "weglaten = laten staan");
  const clear = cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", logo: null, text_color: "" } });
  ok(clear.ok && clear.card.logo === null && clear.card.text_color === "", "wissen");
});

Deno.test("databasefouten", () => {
  ok(dbError({ message: "owner_taken" })?.status === 409, "eigenaar bezet");
  ok(dbError({ message: "Max per scan moet tussen 1 en 30 liggen.", hint: "bad_settings" })?.error === "bad_settings", "hint");
  ok(dbError({ message: "not_found" })?.status === 404, "niet gevonden");
  ok(dbError({ message: "test_limit" })?.error === "test_limit", "hoogstens 10 testklanten");
  ok(dbError({ message: "iets anders" }) === null, "onbekend = serverfout");
});

Deno.test("zaak verwijderen: id en bevestiging verplicht", () => {
  const v = cleanBusinessDelete({ id: ID, confirm: "Bakkerij Jansen" });
  ok(v.ok && v.id === ID && v.confirm === "Bakkerij Jansen", "geldig");
  ok(!cleanBusinessDelete({ id: "x", confirm: "a" }).ok, "id");
  const noConfirm = cleanBusinessDelete({ id: ID });
  ok(!noConfirm.ok && noConfirm.error === "bad_confirm", "zonder naam kan het niet");
  ok(!cleanBusinessDelete({ id: ID, confirm: "" }).ok && !cleanBusinessDelete({ id: ID, confirm: 5 }).ok, "leeg of geen tekst");
  ok(!cleanBusinessDelete({ id: ID, confirm: "x".repeat(201) }).ok, "te lang");
});

Deno.test("zaak verwijderen: de naam moet exact kloppen", () => {
  ok(confirmMatches("Bakkerij Jansen", "Bakkerij Jansen"), "gelijk");
  ok(!confirmMatches("Bakkerij Jansen", "bakkerij jansen"), "hoofdlettergevoelig");
  ok(!confirmMatches("Bakkerij Jansen", "Bakkerij Jansen "), "geen losse spatie");
  ok(!confirmMatches("Bakkerij Jansen", "Bakkerij"), "niet een stuk ervan");
  ok(!confirmMatches("", ""), "lege naam telt nooit");
  ok(!confirmMatches(undefined, "x") && !confirmMatches("x", undefined), "ontbrekend");
  ok(confirmMatches("Caf\u00e9", "Cafe\u0301"), "Unicode-gelijk (é als losse accent)");
});

Deno.test("zaak verwijderen: auditregel zonder persoonsgegevens", () => {
  const line = deleteAuditLine(ID, "Weg   Zaak", { cards: 2, members: 14, staff: 1, events: 3, tickets: 20, member_cards: 1, campaigns: 0, offers: 4, email: "iemand@voorbeeld.example" });
  ok(line.startsWith(ID + ' "Weg Zaak" cards=2 members=14 staff=1 events=3 tickets=20 mcards=1 campaigns=0 offers=4'), line);
  ok(!line.includes("@") && line.length < 300, "alleen id, naam en aantallen");
  ok(deleteAuditLine(ID, "X", null).includes("cards=0"), "zonder aantallen");
});

Deno.test("zaak verwijderen: foutcodes uit de database", () => {
  ok(dbError({ message: "not_found" })?.status === 404, "niet gevonden");
  ok(dbError({ message: "x", hint: "confirm_mismatch" })?.status === 400, "naam klopt niet");
});

Deno.test("zaak verwijderen: notify_owner is standaard aan en moet een boolean zijn", () => {
  const a = cleanBusinessDelete({ id: ID, confirm: "X" });
  ok(a.ok && a.notifyOwner === true, "standaard aan");
  const b = cleanBusinessDelete({ id: ID, confirm: "X", notify_owner: false });
  ok(b.ok && b.notifyOwner === false, "uit");
  const c = cleanBusinessDelete({ id: ID, confirm: "X", notify_owner: "nee" });
  ok(!c.ok && c.error === "bad_notify", "geen tekst");
  ok(dbError({ message: "x", hint: "bad_notify" })?.status === 400, "foutcode");
});

const NOTIFY = {
  owner: "Eigenaar@Zaak.example",
  campaigns: [{ title: "Actie 1", reward: "Taart", ends_at: "2026-12-31T00:00:00Z", recipients: ["a@x.example", "B@x.example", "a@x.example"] }, { title: "Actie 2", reward: "", ends_at: null, recipients: ["a@x.example"] }],
  organizers: [{ title: "Actie van Y", email: "y@x.example" }, { title: "Zonder adres", email: "" }],
};
Deno.test("zaak verwijderen: welke mails gaan er uit", () => {
  const counts = { cards: 2, members: 14, staff: 1, log: 99, mail_participants: 5 };
  const all = buildNotices("Zaak", NOTIFY, counts, true);
  ok(all.length === 5, "eigenaar + 2 + 1 deelnemers (dubbele eruit) + organisator: " + all.length);
  ok(all[0].kind === "owner_deleted" && all[0].to === "eigenaar@zaak.example" && all[0].counts?.cards === 2 && !("log" in (all[0].counts ?? {})), "eigenaarsmail met aantallen");
  ok(all.filter((m) => m.kind === "campaign_cancelled").length === 3, "per actie en adres één");
  ok(all.filter((m) => m.kind === "participant_left").length === 1 && all.at(-1)!.to === "y@x.example", "organisator met adres");
  const off = buildNotices("Zaak", NOTIFY, counts, false);
  ok(!off.some((m) => m.kind === "owner_deleted") && off.length === 4, "schakelaar uit: geen eigenaarsmail, deelnemers wel");
  ok(buildNotices("Zaak", { owner: null }, counts, true).length === 0, "zonder adres geen mail");
  ok(buildNotices("Zaak", null, null, true).length === 0, "zonder gegevens niets");
});

Deno.test("zaak verwijderen: verslag van de mails (aantallen, nooit adressen)", () => {
  const planned = buildNotices("Zaak", NOTIFY, {}, true);
  const good = JSON.stringify({ ok: true, results: planned.map((m) => ({ kind: m.kind, ok: true })) });
  const r1 = mailsReport(planned, true, true, 200, good);
  ok(r1.sent === 5 && r1.failed === 0 && r1.owner === "sent" && r1.participants.sent === 4 && !r1.error, "alles verstuurd");
  const part = JSON.stringify({ results: planned.map((m, i) => ({ kind: m.kind, ok: i !== 0 && i !== 2 })) });
  const r2 = mailsReport(planned, true, true, 200, part);
  ok(r2.sent === 3 && r2.failed === 2 && r2.owner === "failed" && r2.participants.failed === 1, "deels mislukt: " + JSON.stringify(r2));
  const down = mailsReport(planned, true, true, 502, JSON.stringify({ error: "mail_unreachable" }));
  ok(down.sent === 0 && down.failed === 5 && down.owner === "failed" && down.error === "mail_unreachable", "mailfunctie onbereikbaar");
  const nosmtp = mailsReport(planned, true, true, 503, JSON.stringify({ error: "smtp_not_configured" }));
  ok(nosmtp.failed === 5 && nosmtp.error === "smtp_not_configured", "geen SMTP");
  ok(mailsReport(planned, true, true, 200, "geen json").failed === 5, "onleesbaar antwoord telt als mislukt");
  const off = mailsReport(buildNotices("Zaak", NOTIFY, {}, false), false, true, 200, JSON.stringify({ results: buildNotices("Zaak", NOTIFY, {}, false).map((m) => ({ kind: m.kind, ok: true })) }));
  ok(off.owner === "off" && off.failed === 0, "eigenaar uit");
  ok(mailsReport([], true, false, 200, JSON.stringify({ results: [] })).owner === "none", "geen adres");
  ok(!JSON.stringify([r1, r2, down]).includes("@"), "geen adressen in het verslag");
  const line = deleteAuditLine(ID, "Zaak", { cards: 1 }, { sent: 4, failed: 2 });
  ok(line.endsWith(" mails=4/6") && !line.includes("@"), "auditregel: aantallen mails: " + line);
});
