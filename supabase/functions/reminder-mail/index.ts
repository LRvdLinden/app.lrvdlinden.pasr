// Pasr: herinneringen per e-mail (sinds 1.0.2). Elke ochtend stuurt de database (pg_cron → pasr_mail_kick, via pg_net)
// {action: "run"} met de kop x-pasr-hook. De functie vraagt pasr_mail_due wat er te melden is, stuurt per gebruiker één
// mail in Pasr-stijl vanaf PASR_SMTP_FROM (support@pasr.nl) en schrijft met pasr_mail_sent weg wat er verstuurd is.
//
// Afmelden met één klik vanuit het mailprogramma (RFC 8058): POST ?stop=<code> met List-Unsubscribe=One-Click.
// De link in de mail gaat naar pasr.nl/afmelden/?t=<code> (die pagina roept pasr_mail_unsubscribe aan).
//
// Function-secrets (gezet door de workflow Backend uit de GitHub-secrets PASR_SMTP_*, dezelfde als group-invite):
//   PASR_SMTP_HOST, PASR_SMTP_PORT (465), PASR_SMTP_USER, PASR_SMTP_PASSWORD, PASR_SMTP_FROM
// Zonder SMTP verstuurt de functie niets en schrijft ze ook niets weg (dan gaat het de volgende ochtend alsnog).
import nodemailer from "npm:nodemailer@6.9.16";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { CORAL, HTML, MINT, ROW } from "./template.ts";

export type Item = {
  key: string;
  type: "expiry" | "renew" | "balance";
  kind?: string;
  store?: string;
  days?: number;
  date?: string | null;
  balance?: number | null;
  currency?: string;
  cost?: number | null;
  period?: string;
};
export type Due = { user_id: string; email: string; first_name?: string; unsub: string; items: Item[] };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

export const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

const oneLine = (s: unknown, n = 60) => String(s ?? "").replace(/[\r\n\t]+/g, " ").trim().slice(0, n);

export function money(value: number, currency = "EUR"): string {
  try {
    return new Intl.NumberFormat("nl-NL", { style: "currency", currency }).format(value);
  } catch {
    return `€ ${value.toFixed(2).replace(".", ",")}`;
  }
}

export function day(date: string | null | undefined): string {
  if (!date) return "";
  const d = new Date(`${date}T12:00:00Z`);
  if (isNaN(d.getTime())) return "";
  return new Intl.DateTimeFormat("nl-NL", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(d);
}

const PERIOD: Record<string, string> = { week: "per week", month: "per maand", quarter: "per kwartaal", year: "per jaar" };

/** Eén regel in de mail: winkel, uitleg en (rechts) bedrag of termijn. Alles als platte tekst; render() maakt het veilig. */
export function line(i: Item): { store: string; detail: string; value: string; urgent: boolean } {
  const store = oneLine(i.store) || "Je kaart";
  const cur = i.currency || "EUR";
  if (i.type === "expiry") {
    const what = i.kind === "code" ? "Kortingscode" : "Cadeaukaart";
    const detail = i.days === 0 ? `${what} verloopt vandaag` : `${what} verloopt op ${day(i.date)}`;
    const value = typeof i.balance === "number" ? money(i.balance, cur) : i.days === 0 ? "Vandaag" : "Over 7 dagen";
    return { store, detail, value, urgent: true };
  }
  if (i.type === "renew") {
    const cost = typeof i.cost === "number" ? `${money(i.cost, cur)} ${PERIOD[i.period ?? ""] ?? "per maand"}` : "";
    return { store, detail: `Abonnement verlengt op ${day(i.date)}${cost ? ` · ${cost}` : ""}`, value: "Over 2 dagen", urgent: true };
  }
  const until = i.date ? `Geldig tot ${day(i.date)}` : "Geen vervaldatum";
  return { store, detail: until, value: money(Number(i.balance ?? 0), cur), urgent: false };
}

/** Onderwerp en inleiding, afhankelijk van wat er in de mail staat. */
export function summary(items: Item[]): { subject: string; title: string; intro: string } {
  const expiring = items.filter((i) => i.type === "expiry");
  const renew = items.filter((i) => i.type === "renew");
  const balance = items.filter((i) => i.type === "balance");
  if (items.length === 1) {
    const i = items[0], store = oneLine(i.store) || "je kaart";
    if (i.type === "expiry") {
      const today = i.days === 0;
      const subject = `${i.kind === "code" ? "Kortingscode " : ""}${store} verloopt ${today ? "vandaag" : "over een week"}`;
      return { subject, title: subject,
        intro: typeof i.balance === "number"
          ? `Je hebt nog ${money(i.balance, i.currency)} tegoed. Gebruik ${today ? "het vandaag nog" : "het op tijd"}.`
          : `Gebruik ${i.kind === "code" ? "je code" : "je kaart"} ${today ? "vandaag nog" : "op tijd"}.` };
    }
    if (i.type === "renew") {
      const subject = `${store} verlengt over 2 dagen`;
      return { subject, title: subject, intro: "Wil je opzeggen of iets wijzigen? Doe het dan op tijd." };
    }
    const subject = `Je hebt nog ${money(Number(i.balance ?? 0), i.currency)} bij ${store}`;
    return { subject, title: subject, intro: "Een kleine herinnering: je cadeaukaart heeft nog tegoed. Vergeet hem niet." };
  }
  if (expiring.length === 0 && renew.length === 0) {
    const cur = new Set(balance.map((i) => i.currency || "EUR"));
    const total = cur.size === 1 ? money(balance.reduce((s, i) => s + Number(i.balance ?? 0), 0), [...cur][0]) : "";
    const subject = total ? `Je hebt nog ${total} tegoed op ${balance.length} cadeaukaarten` : `Je hebt nog tegoed op ${balance.length} cadeaukaarten`;
    return { subject, title: subject, intro: "Een kleine herinnering aan het tegoed op je cadeaukaarten. Vergeet ze niet." };
  }
  const parts: string[] = [];
  if (expiring.length) parts.push(`${expiring.length} ${expiring.length === 1 ? "kaart verloopt" : "kaarten verlopen"} binnenkort`);
  if (renew.length) parts.push(`${renew.length} ${renew.length === 1 ? "abonnement verlengt" : "abonnementen verlengen"}`);
  if (balance.length) parts.push(`tegoed op ${balance.length} ${balance.length === 1 ? "cadeaukaart" : "cadeaukaarten"}`);
  const subject = `Pasr · ${parts.join(", ")}`;
  return { subject, title: "Je herinneringen van Pasr", intro: "Dit speelt er bij je kaarten. Op tijd gebruiken voorkomt dat je tegoed verloopt." };
}

export function stopURL(token: string) {
  return `https://pasr.nl/afmelden/?t=${encodeURIComponent(token)}`;
}

/** De hele mail. Verlopend eerst, dan verlengingen, dan tegoed (hoogste bedrag eerst). */
export function render(due: Due) {
  const order = { expiry: 0, renew: 1, balance: 2 } as const;
  const items = [...due.items].sort((a, b) =>
    order[a.type] - order[b.type] || (a.days ?? 0) - (b.days ?? 0) || Number(b.balance ?? 0) - Number(a.balance ?? 0));
  const s = summary(items);
  const rows = items.map(line);
  const name = oneLine(due.first_name, 40);
  const greeting = name
    ? `<p style="margin:0 0 12px;font-size:15px;line-height:23px;font-weight:600;color:#ffffff">Hoi ${esc(name)},</p>`
    : "";
  const html = HTML
    .replaceAll("{{TITLE}}", esc(s.title))
    .replaceAll("{{PREHEADER}}", esc(rows.map((r) => `${r.store} ${r.value}`).join(" · ").slice(0, 140)))
    .replaceAll("{{GREETING}}", greeting)
    .replaceAll("{{INTRO}}", esc(s.intro))
    .replaceAll("{{STOP}}", esc(stopURL(due.unsub)))
    .replaceAll("{{ROWS}}", rows.map((r) => ROW
      .replaceAll("{{STORE}}", esc(r.store))
      .replaceAll("{{DETAIL}}", esc(r.detail))
      .replaceAll("{{VALUE}}", esc(r.value))
      .replaceAll("{{COLOR}}", r.urgent ? CORAL : MINT)).join(""));
  const text = [name ? `Hoi ${name},` : "", s.intro, "",
    ...rows.map((r) => `- ${r.store}: ${r.detail} (${r.value})`), "",
    "Open Pasr om je kaart te tonen of je tegoed bij te werken.", "",
    `Geen herinneringen per e-mail meer? Zet ze uit in Pasr › Instellingen › Meldingen, of meld je af: ${stopURL(due.unsub)}`,
  ].filter((l, i) => i > 0 || l).join("\n");
  return { subject: oneLine(s.subject, 120), html, text };
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
    const u = new URL(req.url);
    // Eén klik afmelden vanuit het mailprogramma (List-Unsubscribe-Post)
    const stop = u.searchParams.get("stop");
    if (stop && req.method === "POST") {
      const { error } = await db.rpc("pasr_mail_unsubscribe", { p_token: stop.slice(0, 64) });
      return json({ ok: !error }, error ? 500 : 200);
    }
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    if (!(await hookOk(req.headers.get("x-pasr-hook")))) return json({ error: "forbidden" }, 403);

    const host = Deno.env.get("PASR_SMTP_HOST"), user = Deno.env.get("PASR_SMTP_USER");
    const pass = Deno.env.get("PASR_SMTP_PASSWORD"), sender = Deno.env.get("PASR_SMTP_FROM");
    if (!host || !user || !pass || !sender) return json({ error: "smtp_not_configured" }, 503);

    const { data, error } = await db.rpc("pasr_mail_due", {});
    if (error) {
      console.error("reminder-mail: due", error.message);
      return json({ error: "server_error" }, 502);
    }
    const list = (Array.isArray(data) ? data : []) as Due[];
    const port = Number(Deno.env.get("PASR_SMTP_PORT") || 465);
    const transport = nodemailer.createTransport({ host, port, secure: port === 465, auth: { user, pass }, pool: true, maxConnections: 2 });
    const oneClick = `${url}/functions/v1/reminder-mail?stop=`;
    let sent = 0, failed = 0;
    for (const due of list) {
      if (!due?.email || !Array.isArray(due.items) || due.items.length === 0) continue;
      try {
        const m = render(due);
        await transport.sendMail({
          from: `Pasr <${sender}>`, to: due.email, subject: m.subject, html: m.html, text: m.text,
          headers: {
            "List-Unsubscribe": `<${oneClick}${encodeURIComponent(due.unsub)}>, <${stopURL(due.unsub)}>`,
            "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
          },
        });
        const keys = [...new Set(due.items.map((i) => i.key))];
        const { error: e } = await db.rpc("pasr_mail_sent", { p_user: due.user_id, p_keys: keys });
        if (e) console.error("reminder-mail: log", e.message);
        sent++;
      } catch (e) {
        failed++;
        console.error("reminder-mail: mail", (e as Error).name);
      }
    }
    transport.close();
    return json({ users: list.length, sent, failed });
  });
}
