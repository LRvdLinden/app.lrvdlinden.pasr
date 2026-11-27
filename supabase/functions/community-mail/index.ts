// Pasr Zakelijk: mails bij gezamenlijke acties (sinds 27-11-2026). De database zet elke gebeurtenis in de outbox
// (pasr_business_community_outbox) en stuurt via pg_net {action: "run"} met de kop x-pasr-hook (ook elke 10 minuten
// als vangnet). De functie vraagt pasr_business_community_mail_due wat er gemaild moet worden, stuurt per ontvanger een
// mail in de Pasr-huisstijl (template.ts, gemaakt door supabase/templates/build.py) en meldt met
// pasr_business_community_mail_sent wat er verstuurd is.
//
// Soorten (kind):
//   invite        bestaande zaak is uitgenodigd                         -> ontvanger: uitgenodigde zaak
//   invite_email  uitnodiging per e-mail/link (zaak nog niet in Pasr)   -> ontvanger: het e-mailadres, met de link
//   accepted      uitnodiging geaccepteerd (of open meedoen)            -> ontvanger: organisator
//   declined      uitnodiging geweigerd                                 -> ontvanger: organisator
//   active        minimum bereikt, actie is gestart                     -> ontvanger: elke deelnemer
//   removed       deelnemer verwijderd                                  -> ontvanger: verwijderde zaak
//   revoked       uitnodiging ingetrokken                               -> ontvanger: uitgenodigde zaak of e-mailadres
//
// Function-secrets (gezet door de workflow Backend uit de GitHub-secrets PASR_SMTP_*, dezelfde als group-invite):
//   PASR_SMTP_HOST, PASR_SMTP_PORT (465), PASR_SMTP_USER, PASR_SMTP_PASSWORD, PASR_SMTP_FROM
// Zonder SMTP doet de functie niets (503) en blijft alles in de outbox staan. Nooit e-mailadressen of tokens loggen.
import nodemailer from "npm:nodemailer@6.9.16";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { CORAL, HTML, IRIS, MINT, ROW } from "./template.ts";

export const KINDS = ["invite", "invite_email", "accepted", "declined", "active", "removed", "revoked"] as const;
export type Kind = typeof KINDS[number];
export type Item = {
  id: number;
  kind: Kind;
  to: string | null;
  business?: string | null;
  actor?: string | null;
  actor_city?: string | null;
  link?: string | null;
  campaign: {
    id: string; title: string; reward: string; starts_at?: string; ends_at?: string; required?: number;
    min_participants?: number; accepted_count?: number; organizer?: string; organizer_city?: string | null;
  };
  participant_names?: string[];
};

export const DASHBOARD = "https://pasr.nl/zakelijk/dashboard/#gezamenlijke-acties";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

export const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export const oneLine = (s: unknown, n = 80) => String(s ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim().slice(0, n);

export function day(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  return new Intl.DateTimeFormat("nl-NL", { day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Amsterdam" }).format(d);
}

/** Alleen een uitnodigingslink van pasr.nl met een token van 64 tekens. */
export const okLink = (link: unknown) =>
  typeof link === "string" && /^https:\/\/pasr\.nl\/zakelijk\/uitnodiging\/\?t=[0-9a-f]{64}$/.test(link);

export const okEmail = (to: unknown) =>
  typeof to === "string" && to.length <= 200 && /^[^@\s<>"',;]+@[^@\s<>"',;]+\.[^@\s<>"',;]+$/.test(to);

const names = (list: unknown, n = 8) => {
  const all = (Array.isArray(list) ? list : []).map((x) => oneLine(x, 60)).filter(Boolean);
  return all.length > n ? `${all.slice(0, n).join(", ")} en nog ${all.length - n}` : all.join(", ");
};

/** Inhoud van de mail per soort, als platte tekst; render() maakt het HTML-veilig. */
export function content(i: Item) {
  const c = i.campaign;
  const title = oneLine(c.title, 80) || "Gezamenlijke actie";
  const reward = oneLine(c.reward, 120);
  const organizer = oneLine(c.organizer, 60) || "Een ondernemer";
  const orgWhere = c.organizer_city ? `${organizer} in ${oneLine(c.organizer_city, 60)}` : organizer;
  const business = oneLine(i.business, 60) || "je zaak";
  const actor = oneLine(i.actor, 60);
  const accepted = Number(c.accepted_count ?? 0), min = Number(c.min_participants ?? 2);
  const period = [day(c.starts_at), day(c.ends_at)].filter(Boolean).join(" t/m ");
  const rows: [string, string][] = [["Actie", title]];
  if (reward) rows.push(["Beloning", c.required ? `${reward} na ${c.required} verschillende zaken` : reward]);
  if (period) rows.push(["Looptijd", period]);
  const who = names(i.participant_names);
  if (who) rows.push(["Doen mee", who]);
  const q = `“${title}”`;
  switch (i.kind) {
    case "invite":
      return {
        subject: `${organizer} nodigt ${business} uit voor ${q}`, eyebrow: "Uitnodiging", accent: IRIS,
        title: "Uitnodiging voor een gezamenlijke actie",
        intro: `${orgWhere} nodigt ${business} uit voor de gezamenlijke actie ${q}. Klanten sparen bij alle deelnemende zaken samen voor één beloning. Accepteer of weiger de uitnodiging in Pasr Zakelijk of in je dashboard.`,
        rows: [...rows, ["Start bij", `${min} deelnemende zaken`] as [string, string]],
        button: "Uitnodiging bekijken", link: DASHBOARD,
        note: "Doe je niet mee? Weiger de uitnodiging; de organisator ziet alleen dat je niet meedoet. Er worden nooit klantgegevens tussen zaken gedeeld.",
      };
    case "invite_email":
      return {
        subject: `${organizer} nodigt je uit voor een gezamenlijke actie met Pasr`, eyebrow: "Uitnodiging", accent: IRIS,
        title: `Doe mee met ${q}`,
        intro: `${orgWhere} houdt samen met andere ondernemers een gezamenlijke klantenactie met Pasr en nodigt jouw zaak uit. Meld je zaak gratis aan bij Pasr Zakelijk (of log in) en accepteer de uitnodiging.`,
        rows: [...rows, ["Start bij", `${min} deelnemende zaken`] as [string, string]],
        button: "Uitnodiging bekijken", link: i.link ?? "",
        note: "De link is 14 dagen geldig en werkt voor één zaak. Ken je de afzender niet? Dan kun je deze mail negeren.",
      };
    case "accepted": {
      const left = Math.max(0, min - accepted);
      return {
        subject: `${actor || "Een zaak"} doet mee aan ${q}`, eyebrow: "Gezamenlijke actie", accent: MINT,
        title: `${actor || "Een zaak"} doet mee`,
        intro: `${actor || "Een uitgenodigde zaak"} heeft je uitnodiging voor ${q} geaccepteerd. Er doen nu ${accepted} ${accepted === 1 ? "zaak" : "zaken"} mee` +
          (left > 0 ? `; nog ${left} nodig, dan start de actie.` : "."),
        rows, button: "Naar je dashboard", link: DASHBOARD,
        note: "Je ziet de status van al je uitnodigingen in Pasr Zakelijk en in je dashboard op pasr.nl.",
      };
    }
    case "declined":
      return {
        subject: `${actor || "Een zaak"} doet niet mee aan ${q}`, eyebrow: "Gezamenlijke actie", accent: CORAL,
        title: `${actor || "Een zaak"} doet niet mee`,
        intro: `${actor || "Een uitgenodigde zaak"} heeft je uitnodiging voor ${q} geweigerd. Je kunt een andere zaak uitnodigen; zoek op naam of plaats, of stuur een link.`,
        rows, button: "Naar je dashboard", link: DASHBOARD,
        note: "Je ziet de status van al je uitnodigingen in Pasr Zakelijk en in je dashboard op pasr.nl.",
      };
    case "active":
      return {
        subject: `${q} is gestart`, eyebrow: "Gezamenlijke actie", accent: MINT,
        title: "De gezamenlijke actie is gestart",
        intro: `Er doen nu genoeg zaken mee: ${q} is gestart. Klanten zien de actie vanaf nu in Pasr en sparen bij alle deelnemende zaken. Bij het scannen zie je vanzelf of een klant de beloning heeft verdiend.`,
        rows, button: "Naar je dashboard", link: DASHBOARD,
        note: "Er worden geen klantgegevens tussen zaken gedeeld: elke zaak ziet alleen aantallen.",
      };
    case "removed":
      return {
        subject: `${business} doet niet meer mee aan ${q}`, eyebrow: "Gezamenlijke actie", accent: CORAL,
        title: "Je zaak doet niet meer mee",
        intro: `${actor || "Pasr"} heeft ${business} uit de gezamenlijke actie ${q} gehaald. Bezoeken bij jouw zaak tellen niet meer mee voor deze actie; je eigen stempelkaarten werken gewoon door.`,
        rows: rows.filter((r) => r[0] !== "Doen mee"), button: "Naar je dashboard", link: DASHBOARD,
        note: "Klopt dit niet? Neem contact op met de organisator, of mail support@pasr.nl.",
      };
    case "revoked":
      return {
        subject: `Uitnodiging voor ${q} ingetrokken`, eyebrow: "Uitnodiging", accent: CORAL,
        title: "Uitnodiging ingetrokken",
        intro: `${actor || "Pasr"} heeft de uitnodiging voor de gezamenlijke actie ${q} ingetrokken. Je hoeft niets te doen.`,
        rows: rows.filter((r) => r[0] !== "Doen mee"), button: "Pasr voor ondernemers", link: "https://pasr.nl/zakelijk/",
        note: "Vragen? Neem contact op met de organisator, of mail support@pasr.nl.",
      };
  }
}

/** De hele mail (onderwerp, HTML, tekst). null als er niets te sturen is (geen geldige ontvanger of link). */
export function render(i: Item) {
  if (!(KINDS as readonly unknown[]).includes(i?.kind) || !okEmail(i.to) || !i.campaign) return null;
  if (i.kind === "invite_email" && !okLink(i.link)) return null;
  const m = content(i);
  const html = HTML
    .replaceAll("{{TITLE}}", esc(m.title))
    .replaceAll("{{EYEBROW}}", esc(m.eyebrow))
    .replaceAll("{{ACCENT}}", esc(m.accent))
    .replaceAll("{{PREHEADER}}", esc(m.intro.slice(0, 140)))
    .replaceAll("{{INTRO}}", esc(m.intro))
    .replaceAll("{{BUTTON}}", esc(m.button))
    .replaceAll("{{NOTE}}", esc(m.note))
    .replaceAll("{{LINK}}", esc(m.link))
    .replaceAll("{{ROWS}}", m.rows.map(([label, value]) => ROW.replaceAll("{{LABEL}}", esc(label)).replaceAll("{{VALUE}}", esc(value))).join(""));
  const text = [m.title, "", m.intro, "", ...m.rows.map(([l, v]) => `${l}: ${v}`), "", `${m.button}: ${m.link}`, "", m.note, "",
    "Pasr Zakelijk · https://pasr.nl/zakelijk/"].join("\n");
  return { subject: oneLine(m.subject, 140), html, text };
}

if (import.meta.main) {
  const url = Deno.env.get("SUPABASE_URL")!, service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db = createClient(url, service, { auth: { persistSession: false } });

  let hookSecret: string | null = null, hookUntil = 0;
  const hookOk = async (given: string | null) => {
    if (!given || given.length > 200) return false;
    if (!hookSecret || Date.now() > hookUntil) {
      const { data, error } = await db.from("pasr_secret").select("hook_secret").eq("id", 1).maybeSingle();
      if (error || !data?.hook_secret) return false;
      hookSecret = String(data.hook_secret);
      hookUntil = Date.now() + 300_000;
    }
    const a = new TextEncoder().encode(given), b = new TextEncoder().encode(hookSecret);
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff === 0;
  };

  Deno.serve(async (req) => {
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    if (!(await hookOk(req.headers.get("x-pasr-hook")))) return json({ error: "forbidden" }, 403);

    const host = Deno.env.get("PASR_SMTP_HOST"), user = Deno.env.get("PASR_SMTP_USER");
    const pass = Deno.env.get("PASR_SMTP_PASSWORD"), sender = Deno.env.get("PASR_SMTP_FROM");
    if (!host || !user || !pass || !sender) return json({ error: "smtp_not_configured" }, 503);

    const { data, error } = await db.rpc("pasr_business_community_mail_due", { p_limit: 50 });
    if (error) {
      console.error("community-mail: due", error.message);
      return json({ error: "server_error" }, 502);
    }
    const list = (Array.isArray(data) ? data : []) as Item[];
    if (!list.length) return json({ due: 0, sent: 0, skipped: 0, failed: 0 });
    const port = Number(Deno.env.get("PASR_SMTP_PORT") || 465);
    const transport = nodemailer.createTransport({ host, port, secure: port === 465, auth: { user, pass }, pool: true, maxConnections: 2 });
    const done: number[] = [];
    let sent = 0, skipped = 0, failed = 0;
    for (const item of list) {
      const m = render(item);
      if (!m) { skipped++; done.push(item.id); continue; }   // geen (geldige) ontvanger: niet opnieuw proberen
      try {
        await transport.sendMail({ from: `Pasr Zakelijk <${sender}>`, to: item.to!, subject: m.subject, html: m.html, text: m.text });
        sent++;
        done.push(item.id);
      } catch (e) {
        failed++;   // blijft staan; de volgende run (hoogstens 5 pogingen) probeert opnieuw
        console.error("community-mail: mail", (e as Error).name);
      }
    }
    transport.close();
    if (done.length) {
      const { error: e } = await db.rpc("pasr_business_community_mail_sent", { p_ids: done });
      if (e) console.error("community-mail: log", e.message);
    }
    return json({ due: list.length, sent, skipped, failed });
  });
}
