// deno test --no-check --allow-env supabase/functions/community-mail/
import { content, DASHBOARD, type Item, KINDS, okEmail, okLink, render } from "./index.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const TOKEN = "0123456789abcdef".repeat(4);

const base: Item = {
  id: 1, kind: "invite", to: "info@bakkerij.example", business: "De Bakkerij <b>", actor: "De Koffiehoek",
  actor_city: "Apeldoorn",
  campaign: { id: "c", title: "Binnenstad & route", reward: "Gratis taartje", starts_at: "2026-11-27T10:00:00Z",
    ends_at: "2026-12-27T10:00:00Z", required: 3, min_participants: 3, accepted_count: 1, organizer: "De Koffiehoek",
    organizer_city: "Apeldoorn" },
  participant_names: ["De Koffiehoek"],
};

Deno.test("alle soorten: volledig ingevuld, HTML-veilig, huisstijl", () => {
  for (const kind of KINDS) {
    const m = render({ ...base, kind, link: `https://pasr.nl/zakelijk/uitnodiging/?t=${TOKEN}` });
    ok(m, `mail voor ${kind}`);
    ok(!m!.html.includes("{{"), `${kind}: alles ingevuld`);
    ok(m!.html.includes("https://pasr.nl/assets/mail-icon.png"), `${kind}: mail-icoon`);
    ok(m!.html.includes("#0A0B10"), `${kind}: donkere achtergrond`);
    ok(!m!.html.includes("<b>") || !m!.html.includes("De Bakkerij <b>"), `${kind}: naam escaped`);
    ok(m!.html.includes("Binnenstad &amp; route"), `${kind}: titel escaped`);
    ok(!m!.subject.includes("\n"), `${kind}: onderwerp op één regel`);
    ok(m!.text.includes("Binnenstad & route"), `${kind}: tekstversie`);
  }
});

Deno.test("(a) uitnodiging bestaande zaak: knop naar het dashboard", () => {
  const m = render(base)!;
  ok(m.subject === "De Koffiehoek nodigt De Bakkerij <b> uit voor “Binnenstad & route”", m.subject);
  ok(m.html.includes(DASHBOARD), "dashboard");
  ok(m.html.includes("De Koffiehoek in Apeldoorn"), "organisator met plaats");
  ok(m.html.includes("3 deelnemende zaken"), "minimum");
});

Deno.test("(b) uitnodiging per e-mail: met de link, zonder geldige link niets", () => {
  const link = `https://pasr.nl/zakelijk/uitnodiging/?t=${TOKEN}`;
  const m = render({ ...base, kind: "invite_email", to: "nieuw@winkel.example", business: null, link })!;
  ok(m.html.includes(link) && m.text.includes(link), "link");
  ok(m.html.includes("14 dagen"), "geldigheid");
  ok(render({ ...base, kind: "invite_email", link: "https://evil.example/?t=" + TOKEN }) === null, "vreemde link");
  ok(render({ ...base, kind: "invite_email", link: null }) === null, "geen link");
});

Deno.test("(c) geaccepteerd en geweigerd naar de organisator", () => {
  const a = content({ ...base, kind: "accepted", actor: "De Bakkerij", campaign: { ...base.campaign, accepted_count: 2 } });
  ok(a.subject === "De Bakkerij doet mee aan “Binnenstad & route”", a.subject);
  ok(a.intro.includes("nog 1 nodig"), a.intro);
  const full = content({ ...base, kind: "accepted", campaign: { ...base.campaign, accepted_count: 3 } });
  ok(!full.intro.includes("dan start de actie"), full.intro);
  const d = content({ ...base, kind: "declined", actor: "De Bakkerij" });
  ok(d.subject.includes("doet niet mee") && d.intro.includes("geweigerd"), d.subject);
});

Deno.test("(d) gestart en (e) verwijderd / ingetrokken", () => {
  ok(content({ ...base, kind: "active" }).subject === "“Binnenstad & route” is gestart", "gestart");
  const r = content({ ...base, kind: "removed", actor: null });
  ok(r.intro.startsWith("Pasr heeft"), "door het beheer");
  ok(content({ ...base, kind: "revoked" }).title === "Uitnodiging ingetrokken", "ingetrokken");
});

Deno.test("ontvanger en link controleren", () => {
  ok(okEmail("a@b.nl") && !okEmail("a@b") && !okEmail("a b@c.nl") && !okEmail(null), "e-mail");
  ok(okLink(`https://pasr.nl/zakelijk/uitnodiging/?t=${TOKEN}`) && !okLink(`https://pasr.nl/zakelijk/uitnodiging/?t=abc`), "link");
  ok(render({ ...base, to: null }) === null, "geen ontvanger");
  ok(render({ ...base, kind: "unknown" as never }) === null, "onbekende soort");
});
