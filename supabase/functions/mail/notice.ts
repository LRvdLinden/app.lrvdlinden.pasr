// Pasr beheer › zaak verwijderen: de mails aan de eigenaar en aan de deelnemers van gezamenlijke acties (merk Pasr Zakelijk).
// De functie admin stuurt alleen gegevens (kind, adres, zaaknaam, titel, aantallen); de tekst staat hier, zodat er nooit vrije tekst
// van buiten in een mail komt. Namen en titels gaan als platte tekst door plainToMarkdown (letterlijk, geen opmaak of links) en
// worden daarna door de gewone renderer ge-escaped. Puur, getest in notice_test.ts. Adressen komen nooit in een fout of log.
import { cleanText, validEmail } from "./logic.ts";
import { plainToMarkdown } from "./markdown.ts";
import type { Res } from "./requests.ts";

export const NOTICE_KINDS = ["owner_deleted", "campaign_cancelled", "participant_left"] as const;
export type NoticeKind = typeof NOTICE_KINDS[number];
export const NOTICE_MAX = 100;
export const COUNT_KEYS = ["cards", "members", "staff", "events", "tickets", "member_cards", "campaigns", "offers"] as const;

export type Notice = {
  kind: NoticeKind; to: string; business: string;
  campaign?: { title: string; reward: string; ends_at: string | null };
  counts: Partial<Record<typeof COUNT_KEYS[number], number>>;
};

const fail = (error: string) => ({ ok: false, error }) as const;
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);

/** Het verzoek {mails:[{kind, to, business, campaign?, counts?}]} controleren; hoogstens 100 mails, dubbele (kind, adres, titel) eruit. */
export function parseNotices(b: Record<string, unknown>): Res<Notice[]> {
  if (!Array.isArray(b.mails) || b.mails.length < 1 || b.mails.length > NOTICE_MAX) return fail("bad_request");
  const out: Notice[] = [], seen = new Set<string>();
  for (const raw of b.mails) {
    if (!isObj(raw)) return fail("bad_request");
    if (!(NOTICE_KINDS as readonly unknown[]).includes(raw.kind)) return fail("bad_request");
    const to = typeof raw.to === "string" ? raw.to.trim().toLowerCase() : "";
    if (!validEmail(to)) return fail("bad_address");
    const business = cleanText(raw.business, 60);
    if (!business) return fail("bad_request");
    const n: Notice = { kind: raw.kind as NoticeKind, to, business, counts: {} };
    if (n.kind !== "owner_deleted") {
      if (!isObj(raw.campaign)) return fail("bad_request");
      const title = cleanText(raw.campaign.title, 80), reward = cleanText(raw.campaign.reward, 120);
      if (!title) return fail("bad_request");
      const end = typeof raw.campaign.ends_at === "string" && !Number.isNaN(Date.parse(raw.campaign.ends_at)) ? new Date(raw.campaign.ends_at).toISOString() : null;
      n.campaign = { title, reward, ends_at: end };
    }
    if (n.kind === "owner_deleted" && isObj(raw.counts)) {
      for (const k of COUNT_KEYS) {
        const v = raw.counts[k];
        if (v === undefined || v === null) continue;
        if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > 10_000_000) return fail("bad_request");
        n.counts[k] = v;
      }
    }
    const key = `${n.kind}|${to}|${n.campaign?.title ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(n);
  }
  return { ok: true, value: out };
}

const nl = (n: number) => new Intl.NumberFormat("nl-NL").format(n);
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("nl-NL", { day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Amsterdam" }) : "");
/** Platte tekst letterlijk in Markdown. Een los https-adres in een naam zou een link worden: dat komt als code (letterlijk, geen link). */
const lit = (s: string) => s.split(/(https:\/\/[^\s<>"'`]+)/gi).map((part, i) => (i % 2 ? "`" + part.replace(/`/g, "") + "`" : plainToMarkdown(part))).join("");
const q = (s: string) => `**${lit(s)}**`;

/** Onderwerp (platte tekst) en tekst (Markdown) van één mail. */
export function buildNotice(n: Notice): { subject: string; markdown: string } {
  const bz = lit(n.business);
  const help = "Vragen, of denk je dat dit niet klopt? Mail ons op [zakelijk@pasr.nl](mailto:zakelijk@pasr.nl).";
  if (n.kind === "owner_deleted") {
    const c = n.counts, lines: string[] = [];
    if (c.cards) lines.push(`- ${nl(c.cards)} ${c.cards === 1 ? "stempelkaart" : "stempelkaarten"}${c.members ? ` met ${nl(c.members)} ${c.members === 1 ? "lid" : "leden"}` : ""}`);
    if (c.staff) lines.push(`- ${nl(c.staff)} ${c.staff === 1 ? "medewerker" : "medewerkers"}`);
    if (c.events) lines.push(`- ${nl(c.events)} ${c.events === 1 ? "event" : "events"}${c.tickets ? ` met ${nl(c.tickets)} ${c.tickets === 1 ? "ticket" : "tickets"}` : ""}, inclusief de gegevens van de aanmeldingen`);
    if (c.member_cards) lines.push(`- ${nl(c.member_cards)} ${c.member_cards === 1 ? "klantenkaart" : "klantenkaarten"}`);
    if (c.offers) lines.push(`- ${nl(c.offers)} ${c.offers === 1 ? "kortingsbon of actiecode" : "kortingsbonnen en actiecodes"}`);
    if (c.campaigns) lines.push(`- ${nl(c.campaigns)} ${c.campaigns === 1 ? "gezamenlijke actie" : "gezamenlijke acties"} (geannuleerd)`);
    lines.push("- de instellingen, de log en alle andere gegevens van de zaak");
    return {
      subject: `Je zaak ${n.business} is verwijderd uit Pasr voor ondernemers`,
      markdown: [
        "# Je zaak is verwijderd",
        `Hallo,`,
        `Je zaak **${bz}** is verwijderd uit Pasr voor ondernemers. Dit is definitief en kan niet ongedaan worden gemaakt.`,
        "Dit is verwijderd:",
        lines.join("\n"),
        "Je klanten zien de stempelkaart van de zaak bij het volgende verversen niet meer in Pasr. Je eigen Pasr-account blijft gewoon bestaan.",
        "Opnieuw beginnen kan altijd, en is gratis: meld een nieuwe zaak aan via [pasr.nl/zakelijk](https://pasr.nl/zakelijk/).",
        help,
        "Groet,\\\nPasr voor ondernemers",
      ].join("\n\n"),
    };
  }
  const title = n.campaign!.title, tt = lit(title);
  if (n.kind === "campaign_cancelled") {
    const end = day(n.campaign!.ends_at), reward = n.campaign!.reward;
    return {
      subject: `De gezamenlijke actie ${title} is geannuleerd`,
      markdown: [
        "# De gezamenlijke actie is geannuleerd",
        "Hallo,",
        `De gezamenlijke actie ${q(title)} is geannuleerd. De organisator, **${bz}**, is niet meer bij Pasr voor ondernemers; daardoor kan de actie niet doorgaan.`,
        [`- ${reward ? `Er wordt geen beloning meer uitgegeven (${lit(reward)}).` : "Er worden geen beloningen meer uitgegeven."}`,
         "- Beloningen die klanten al hebben gekregen, blijven van hen.",
         `- Je hoeft niets te doen${end ? `; de actie liep nog tot ${end}` : ""}.`].join("\n"),
        "Wil je zelf een gezamenlijke actie starten? Dat kan in Pasr Zakelijk, onder Gezamenlijke acties.",
        help,
        "Groet,\\\nPasr voor ondernemers",
      ].join("\n\n"),
    };
  }
  return {
    subject: `${n.business} doet niet meer mee aan ${title}`,
    markdown: [
      "# Een deelnemer doet niet meer mee",
      "Hallo,",
      `De zaak **${bz}** is niet meer bij Pasr voor ondernemers en doet daarom niet meer mee aan jouw gezamenlijke actie **${tt}**.`,
      "De actie loopt door met de andere deelnemers. Kijk in Pasr Zakelijk onder Gezamenlijke acties of er nog genoeg zaken meedoen, en nodig zo nodig een nieuwe zaak uit.",
      help,
      "Groet,\\\nPasr voor ondernemers",
    ].join("\n\n"),
  };
}
