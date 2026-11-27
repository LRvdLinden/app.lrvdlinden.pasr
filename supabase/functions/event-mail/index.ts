// Pasr: mails bij gratis tickets voor een event (sinds 27-11-2026, docs/tickets-klantenkaart.md). De database zet elke
// gebeurtenis in de outbox (pasr_tk_outbox) en stuurt via pg_net {action: "run"} met de kop x-pasr-hook (elke 10
// minuten ook als vangnet, plus de herinneringen de dag ervoor). De functie vraagt pasr_tk_mail_due wat er gemaild
// moet worden, stuurt per aanmelding een mail in de Pasr-huisstijl (template.ts, gemaakt door
// supabase/templates/build.py) met de QR-codes als afbeelding in de mail, en meldt met pasr_tk_mail_sent wat er weg is.
//
// Soorten (kind):
//   ticket_confirmed   aangemeld (of op de wachtlijst)       -> tickets met QR, knop "Voeg toe aan Pasr", afmeldlink
//   event_reminder     de dag ervoor (vanaf 10:00)             -> tickets met QR
//   event_changed      datum, tijd, naam of adres gewijzigd    -> nieuwe gegevens en de tickets
//   event_cancelled    afgelast (met het bericht van de zaak)  -> geen tickets
//   waitlist_promoted  plek vrij: van de wachtlijst            -> het nieuwe ticket met QR
//
// Function-secrets: dezelfde PASR_SMTP_* als group-invite. Zonder SMTP doet de functie niets (503) en blijft alles in
// de outbox. Nooit e-mailadressen, namen of ticketcodes loggen.
import nodemailer from "npm:nodemailer@6.9.16";
import QRCode from "npm:qrcode@1.5.4";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { BADGE, CORAL, HTML, IRIS, MINT, ROW, TICKET } from "./template.ts";

export const KINDS = ["ticket_confirmed", "event_reminder", "event_changed", "event_cancelled", "waitlist_promoted"] as const;
export type Kind = typeof KINDS[number];
export type Ticket = { ticket_id: string; code: string; status: string; ticket_type?: string | null; add_link?: string | null };
export type Item = {
  id: number;
  kind: Kind;
  to: string | null;
  first_name?: string | null;
  message?: string | null;
  event: {
    id: string; name: string; description?: string | null; starts_at: string; ends_at?: string | null; doors_at?: string | null;
    address?: string | null; color?: string | null; status?: string | null; business_name?: string | null;
    business_city?: string | null; cancel_message?: string | null;
  } | null;
  tickets: Ticket[];
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

export const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
export const oneLine = (s: unknown, n = 80) => String(s ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim().slice(0, n);
export const okEmail = (to: unknown) =>
  typeof to === "string" && to.length <= 200 && /^[^@\s<>"',;]+@[^@\s<>"',;]+\.[^@\s<>"',;]+$/.test(to);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Alleen een add-link van pasr.nl voor een ticket met een geldige code. */
export const okAddLink = (link: unknown) =>
  typeof link === "string" && /^https:\/\/pasr\.nl\/add\/t\/[0-9a-f-]{36}\?c=[A-Z2-7]{20,40}$/.test(link);
export const cancelLink = (link: string) => `${link}&afmelden=1`;
const hexOk = (v: unknown) => (typeof v === "string" && /^#[0-9A-Fa-f]{6}$/.test(v) ? v.toUpperCase() : "#6A5CFF");
/** Witte of donkere tekst op de eventkleur. */
export function textOn(hex: string): string {
  const v = parseInt(hex.slice(1), 16), r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.62 ? "#17162A" : "#FFFFFF";
}

const TZ = "Europe/Amsterdam";
function fmt(iso: string | null | undefined, o: Intl.DateTimeFormatOptions) {
  if (!iso) return "";
  const d = new Date(iso);
  return isNaN(d.getTime()) ? "" : new Intl.DateTimeFormat("nl-NL", { ...o, timeZone: TZ }).format(d);
}
export const dayLong = (iso?: string | null) => fmt(iso, { weekday: "long", day: "numeric", month: "long", year: "numeric" });
export const dayShort = (iso?: string | null) => fmt(iso, { weekday: "short", day: "numeric", month: "short" });
export const time = (iso?: string | null) => fmt(iso, { hour: "2-digit", minute: "2-digit" });
/** "za 19 dec · 16:00–19:00" */
export function when(e: NonNullable<Item["event"]>): string {
  const start = dayShort(e.starts_at), from = time(e.starts_at), to = time(e.ends_at);
  const sameDay = e.ends_at && dayShort(e.ends_at) === start;
  return [start, from ? (to && sameDay ? `${from}–${to}` : from) : ""].filter(Boolean).join(" · ");
}

/** Inhoud van de mail per soort, als platte tekst; render() maakt het HTML-veilig. */
export function content(i: Item) {
  const e = i.event!;
  const name = oneLine(e.name, 80) || "het event";
  const biz = oneLine(e.business_name, 60) || "de organisator";
  const hi = oneLine(i.first_name, 40) ? `Hoi ${oneLine(i.first_name, 40)}, ` : "";
  const valid = i.tickets.filter((t) => t.status === "registered" || t.status === "checked_in");
  const waiting = i.tickets.filter((t) => t.status === "waitlist");
  const n = valid.length;
  const rows: [string, string][] = [];
  const date = dayLong(e.starts_at);
  if (date) rows.push(["Datum", date]);
  const t1 = time(e.starts_at), t2 = time(e.ends_at);
  if (t1) rows.push(["Tijd", t2 ? `${t1} – ${t2}` : t1]);
  if (e.doors_at) rows.push(["Deuren open", time(e.doors_at)]);
  if (e.address) rows.push(["Locatie", oneLine(e.address, 120)]);
  const types = [...new Set(i.tickets.map((t) => oneLine(t.ticket_type, 40)).filter(Boolean))];
  if (n) rows.push(["Tickets", `${n}× ${types.join(", ") || "Toegang"}`]);
  else if (waiting.length) rows.push(["Wachtlijst", `${waiting.length}× ${types.join(", ") || "Toegang"}`]);
  const q = `“${name}”`;
  const keep = "Laat de QR-code zien bij de ingang, op je telefoon of geprint. Op het ticket staat alleen je naam.";
  switch (i.kind) {
    case "ticket_confirmed":
      if (!n && waiting.length) {
        return {
          subject: `Je staat op de wachtlijst voor ${name}`, eyebrow: "Wachtlijst", accent: IRIS, title: "Je staat op de wachtlijst",
          intro: `${hi}${q} van ${biz} is vol. Je staat op de wachtlijst${waiting.length > 1 ? ` met ${waiting.length} tickets` : ""}. Komt er een plek vrij, dan krijg je meteen een mail met je ticket.`,
          rows, tickets: [] as Ticket[], badge: true, cancel: true,
          note: "Kun je toch niet? Meld je af via de link hierboven, dan schuift de volgende op de wachtlijst door.",
        };
      }
      return {
        subject: `Je ${n > 1 ? "tickets" : "ticket"} voor ${name}`, eyebrow: n > 1 ? "Je tickets" : "Je ticket", accent: MINT,
        title: `Je ${n > 1 ? "tickets" : "ticket"} voor ${name}`,
        intro: `${hi}je bent aangemeld bij ${biz}. ${keep}`,
        rows, tickets: valid, badge: true, cancel: true,
        note: "Kun je niet? Meld je af via de link hierboven, dan gaat je plek naar de wachtlijst.",
      };
    case "event_reminder":
      return {
        subject: `Morgen: ${name}`, eyebrow: "Herinnering", accent: IRIS, title: `Morgen: ${name}`,
        intro: `${hi}morgen is het zover. ${e.doors_at ? `De deuren gaan open om ${time(e.doors_at)}. ` : ""}${keep}`,
        rows, tickets: valid, badge: true, cancel: true,
        note: "Kun je toch niet? Meld je af via de link hierboven, dan gaat je plek naar iemand op de wachtlijst.",
      };
    case "event_changed":
      return {
        subject: `${name} is gewijzigd`, eyebrow: "Wijziging", accent: IRIS, title: `${name} is gewijzigd`,
        intro: `${hi}${biz} heeft ${q} aangepast. Kijk hieronder naar de nieuwe datum, tijd en locatie. Je ${n > 1 ? "tickets blijven" : "ticket blijft"} geldig.`,
        rows, tickets: valid, badge: n > 0, cancel: true,
        note: "Past het nu niet meer? Meld je af via de link hierboven, dan gaat je plek naar de wachtlijst.",
      };
    case "event_cancelled": {
      const msg = oneLine(i.message ?? e.cancel_message, 500);
      return {
        subject: `${name} gaat niet door`, eyebrow: "Afgelast", accent: CORAL, title: `${name} gaat niet door`,
        intro: `${hi}${biz} heeft ${q} afgelast. Je ${i.tickets.length > 1 ? "tickets zijn" : "ticket is"} niet meer geldig; je hoeft niets te doen.` +
          (msg ? ` Bericht van ${biz}: “${msg}”` : ""),
        rows: rows.filter((r) => r[0] !== "Tickets" && r[0] !== "Wachtlijst"), tickets: [] as Ticket[], badge: false, cancel: false,
        note: "Vragen? Neem contact op met de organisator.",
      };
    }
    case "waitlist_promoted":
      return {
        subject: `Er is een plek vrij: ${name}`, eyebrow: "Plek vrij", accent: MINT, title: "Er is een plek vrij voor je",
        intro: `${hi}goed nieuws: er kwam een plek vrij bij ${q}. Je ${n > 1 ? "tickets staan" : "ticket staat"} hieronder. ${keep}`,
        rows, tickets: valid, badge: true, cancel: true,
        note: "Kun je toch niet? Meld je af via de link hierboven, dan gaat de plek naar de volgende op de wachtlijst.",
      };
  }
}

export type Rendered = { subject: string; html: string; text: string; qr: { cid: string; code: string }[]; from: string };

/** De hele mail. null als er niets te sturen is (geen geldige ontvanger of geen event). */
export function render(i: Item): Rendered | null {
  if (!(KINDS as readonly unknown[]).includes(i?.kind) || !okEmail(i.to) || !i.event || !i.event.name) return null;
  i = { ...i, tickets: (Array.isArray(i.tickets) ? i.tickets : []).filter((t) => t && UUID.test(t.ticket_id) && /^[A-Z2-7]{20,40}$/.test(t.code)) };
  const m = content(i);
  const e = i.event!;
  const color = hexOk(e.color);
  const link = i.tickets.map((t) => t.add_link).find(okAddLink) ?? null;
  const qr: { cid: string; code: string }[] = [];
  const total = m.tickets.length;
  const tickets = m.tickets.map((t, k) => {
    const cid = `qr-${t.ticket_id.toLowerCase()}@pasr.nl`;
    qr.push({ cid, code: t.code });
    return TICKET.replaceAll("{{QR}}", esc(`cid:${cid}`))
      .replaceAll("{{LABEL}}", esc(oneLine(t.ticket_type, 40) || "Toegang"))
      .replaceAll("{{SUB}}", esc(total > 1 ? `Ticket ${k + 1} van ${total}` : "Ticket"))
      .replaceAll("{{CODE}}", esc(t.code.match(/.{1,4}/g)!.join(" ")));
  }).join("");
  const extra = m.cancel && link
    ? `<p style="margin:16px 0 0;font-size:13px;line-height:20px;color:#9A9DAB">Kun je niet? <a href="${esc(cancelLink(link))}" style="color:#6A5CFF">Meld je af</a>.</p>`
    : "";
  const desc = oneLine(e.description, 300);
  const html = HTML
    .replaceAll("{{TITLE}}", esc(m.title))
    .replaceAll("{{EYEBROW}}", esc(m.eyebrow))
    .replaceAll("{{ACCENT}}", esc(m.accent))
    .replaceAll("{{PREHEADER}}", esc(m.intro.slice(0, 140)))
    .replaceAll("{{INTRO}}", esc(m.intro))
    .replaceAll("{{EVCOLOR}}", esc(color))
    .replaceAll("{{EVTEXT}}", esc(textOn(color)))
    .replaceAll("{{EVBUSINESS}}", esc(oneLine(e.business_name, 60)))
    .replaceAll("{{EVNAME}}", esc(oneLine(e.name, 80)))
    .replaceAll("{{EVWHEN}}", esc(when(e)))
    .replaceAll("{{ROWS}}", m.rows.map(([l, v]) => ROW.replaceAll("{{LABEL}}", esc(l)).replaceAll("{{VALUE}}", esc(v))).join("") +
      (desc && i.kind !== "event_cancelled" ? ROW.replaceAll("{{LABEL}}", "Over").replaceAll("{{VALUE}}", esc(desc)) : ""))
    .replaceAll("{{TICKETS}}", tickets)
    .replaceAll("{{BADGE}}", m.badge && link ? BADGE.replaceAll("{{LINK}}", esc(link)) : "")
    .replaceAll("{{EXTRA}}", extra)
    .replaceAll("{{NOTE}}", esc(m.note));
  const text = [m.title, "", m.intro, "", ...m.rows.map(([l, v]) => `${l}: ${v}`),
    ...m.tickets.map((t, k) => `Ticket ${k + 1}: ${t.code}`), "",
    ...(m.badge && link ? [`Voeg toe aan Pasr: ${link}`] : []),
    ...(m.cancel && link ? [`Afmelden: ${cancelLink(link)}`] : []), "", m.note, "", "Pasr · https://pasr.nl"].join("\n");
  const from = `${oneLine(e.business_name, 50).replace(/["<>\\,;:@]/g, "") || "Pasr"} via Pasr`;
  return { subject: oneLine(m.subject, 140), html, text, qr, from };
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

    const { data, error } = await db.rpc("pasr_tk_mail_due", { p_limit: 40 });
    if (error) {
      console.error("event-mail: due", error.message);
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
      if (!m) { skipped++; done.push(item.id); continue; }
      try {
        const attachments = await Promise.all(m.qr.map(async (q, k) => ({
          filename: `ticket-${k + 1}.png`, cid: q.cid, contentType: "image/png",
          content: await QRCode.toBuffer(q.code, { type: "png", margin: 1, width: 336, errorCorrectionLevel: "M" }),
        })));
        await transport.sendMail({ from: `${m.from} <${sender}>`, to: item.to!, subject: m.subject, html: m.html, text: m.text, attachments });
        sent++;
        done.push(item.id);
      } catch (e) {
        failed++;   // blijft staan; de volgende run (hoogstens 5 pogingen) probeert opnieuw
        console.error("event-mail: mail", (e as Error).name);
      }
    }
    transport.close();
    if (done.length) {
      const { error: e } = await db.rpc("pasr_tk_mail_sent", { p_ids: done });
      if (e) console.error("event-mail: log", e.message);
    }
    return json({ due: list.length, sent, skipped, failed });
  });
}
