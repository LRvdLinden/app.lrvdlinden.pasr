// deno test --no-check --allow-env supabase/functions/event-mail/
import { cancelLink, content, type Item, KINDS, okAddLink, okEmail, render, textOn, when } from "./index.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const T1 = "6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f", T2 = "7f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f";
const C1 = "ABCDEFGHIJKLMNOPQRSTUVWX", C2 = "K7Q2MXDATRZ5VWUY3ST2HJBN";
const link = (t: string, c: string) => `https://pasr.nl/add/t/${t}?c=${c}`;

const base: Item = {
  id: 1, kind: "ticket_confirmed", to: "anna@example.nl", first_name: "Anna", message: null,
  event: { id: "e", name: "Winterborrel & glühwein", description: "Kom proeven <b>", starts_at: "2026-12-19T15:00:00Z",
    ends_at: "2026-12-19T18:00:00Z", doors_at: "2026-12-19T14:45:00Z", address: "Hoofdstraat 12, Apeldoorn",
    color: "#1f3a5f", business_name: "Bakkerij de Korenschoof" },
  tickets: [
    { ticket_id: T1, code: C1, status: "registered", ticket_type: "Toegang", add_link: link(T1, C1) },
    { ticket_id: T2, code: C2, status: "registered", ticket_type: "Toegang", add_link: link(T2, C2) },
  ],
};

Deno.test("alle soorten: volledig ingevuld, HTML-veilig, huisstijl", () => {
  for (const kind of KINDS) {
    const m = render({ ...base, kind });
    ok(m, `mail voor ${kind}`);
    ok(!m!.html.includes("{{"), `${kind}: alles ingevuld`);
    ok(m!.html.includes("https://pasr.nl/assets/mail-icon.png"), `${kind}: mail-icoon`);
    ok(m!.html.includes("#0A0B10"), `${kind}: donkere achtergrond`);
    ok(m!.html.includes("Winterborrel &amp; glühwein"), `${kind}: naam escaped`);
    ok(!m!.html.includes("<b>"), `${kind}: geen HTML uit de omschrijving`);
    ok(!m!.subject.includes("\n"), `${kind}: onderwerp op één regel`);
    ok(m!.html.includes("background:#1F3A5F"), `${kind}: eventkleur`);
    ok(!/\d{4}-\d{2}-\d{2}/.test(m!.text.split("Afmelden")[0].replace(/https:\S+/g, "")), `${kind}: geen ISO-datums`);
  }
});

Deno.test("bevestiging: QR per ticket als inline afbeelding, badge met add-link, afmeldlink", () => {
  const m = render(base)!;
  ok(m.subject === "Je tickets voor Winterborrel & glühwein", m.subject);
  ok(m.qr.length === 2 && m.qr[0].code === C1 && m.qr[0].cid === `qr-${T1}@pasr.nl`, "qr");
  ok(m.html.includes(`src="cid:qr-${T1}@pasr.nl"`) && m.html.includes(`cid:qr-${T2}@pasr.nl`), "cid in html");
  ok(m.html.includes("https://pasr.nl/badge/nl/zwart.png") && m.html.includes(`href="${link(T1, C1)}"`), "badge");
  ok(m.html.includes(cancelLink(link(T1, C1)).replace("&", "&amp;")), "afmelden");
  ok(m.html.includes("Ticket 1 van 2") && m.html.includes("ABCD EFGH"), "volgnummer en code");
  ok(m.html.includes("za 19 dec · 16:00–19:00"), when(base.event!));
  ok(m.html.includes("Deuren open") && m.html.includes("15:45"), "deuren in Nederlandse tijd");
  ok(m.from === "Bakkerij de Korenschoof via Pasr", m.from);
  ok(m.text.includes(link(T1, C1)), "tekstversie met link");
});

Deno.test("wachtlijst: geen QR, wel uitleg", () => {
  const m = render({ ...base, tickets: base.tickets.map((t) => ({ ...t, status: "waitlist" })) })!;
  ok(m.subject.startsWith("Je staat op de wachtlijst"), m.subject);
  ok(m.qr.length === 0 && !m.html.includes("cid:"), "geen qr");
});

Deno.test("afgelast: bericht van de zaak, geen tickets of badge", () => {
  const m = render({ ...base, kind: "event_cancelled", message: "Helaas ziek <script>" })!;
  ok(m.subject === "Winterborrel & glühwein gaat niet door", m.subject);
  ok(m.html.includes("Helaas ziek &lt;script&gt;"), "bericht escaped");
  ok(m.qr.length === 0 && !m.html.includes("badge/nl/zwart.png") && !m.html.includes("afmelden=1"), "geen tickets");
});

Deno.test("plek vrij, herinnering en wijziging", () => {
  ok(content({ ...base, kind: "waitlist_promoted" }).subject === "Er is een plek vrij: Winterborrel & glühwein", "plek vrij");
  const r = content({ ...base, kind: "event_reminder" });
  ok(r.subject === "Morgen: Winterborrel & glühwein" && r.intro.includes("15:45"), r.intro);
  ok(content({ ...base, kind: "event_changed" }).intro.includes("aangepast"), "wijziging");
  // een gecancelled ticket krijgt nooit een QR
  const m = render({ ...base, kind: "event_reminder", tickets: [{ ...base.tickets[0], status: "cancelled" }, base.tickets[1]] })!;
  ok(m.qr.length === 1 && m.qr[0].code === C2, "alleen geldige tickets");
});

Deno.test("geen persoonsgegevens behalve de voornaam; ontvanger en links controleren", () => {
  const m = render(base)!;
  ok(!m.html.includes("1991"), "geen geboortedatum");
  ok(okEmail("a@b.nl") && !okEmail("a@b") && !okEmail(null), "e-mail");
  ok(okAddLink(link(T1, C1)) && !okAddLink(`https://evil.example/add/t/${T1}?c=${C1}`) && !okAddLink(link(T1, "abc")), "add-link");
  ok(render({ ...base, to: null }) === null, "geen ontvanger");
  ok(render({ ...base, event: null }) === null, "geen event");
  ok(render({ ...base, kind: "unknown" as never }) === null, "onbekende soort");
  const bad = render({ ...base, tickets: [{ ...base.tickets[0], add_link: "javascript:alert(1)" }] })!;
  ok(!bad.html.includes("javascript:") && !bad.html.includes("badge/nl/zwart.png"), "vreemde link geweigerd");
  ok(textOn("#FFFFFF") === "#17162A" && textOn("#1F3A5F") === "#FFFFFF", "tekstkleur");
});
