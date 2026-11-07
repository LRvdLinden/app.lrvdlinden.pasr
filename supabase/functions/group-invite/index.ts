// Pasr: iemand uitnodigen voor een gedeelde Pasr. De app stuurt {group, email} met het token van de ingelogde gebruiker.
// De functie maakt de uitnodiging aan via pasr_group_invite (met datzelfde token, dus alleen als je lid bent; de database
// bewaakt ook de limieten: 6 leden, 20 uitnodigingen per dag) en stuurt daarna de mail in Pasr-stijl.
//
// Function-secrets (gezet door de workflow Backend uit de GitHub-secrets PASR_SMTP_*):
//   PASR_SMTP_HOST, PASR_SMTP_PORT (465), PASR_SMTP_USER, PASR_SMTP_PASSWORD, PASR_SMTP_FROM
// Zonder SMTP wordt de uitnodiging wel aangemaakt (de ander ziet hem in de app) en antwoordt de functie mailed: false.
import nodemailer from "npm:nodemailer@6.9.16";
import { HTML, SUBJECT } from "./template.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

export const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

/** Mail invullen. Onderwerp zonder HTML, inhoud HTML-veilig; naam en groep worden ingekort. */
export function render(from: string, group: string) {
  const f = from.slice(0, 60), g = group.slice(0, 40);
  return {
    subject: SUBJECT.replaceAll("{{FROM}}", f.replace(/[\r\n]+/g, " ")),
    html: HTML.replaceAll("{{FROM}}", esc(f)).replaceAll("{{GROUP}}", esc(g)),
    text: `${f} wil klantenkaarten met je delen in de gedeelde Pasr "${g}". Open Pasr en log in met dit e-mailadres, ` +
      `of maak gratis een account. Daarna kun je de uitnodiging accepteren.\n\nhttps://pasr.nl/uitnodiging/\n\n` +
      `Ken je deze persoon niet? Dan kun je deze mail negeren. De uitnodiging verloopt na 14 dagen.`,
  };
}

const ERRORS = ["bad_email", "already_member", "member_limit", "rate_limited", "not a member", "not signed in"];

if (import.meta.main) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response(null, { headers: cors });
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const auth = req.headers.get("authorization") ?? "";
    if (!/^Bearer\s+\S+/.test(auth)) return json({ error: "unauthorized" }, 401);
    let body: { group?: string; email?: string };
    try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
    if (typeof body.group !== "string" || typeof body.email !== "string" || body.email.length > 200) {
      return json({ error: "bad_request" }, 400);
    }

    // 1. uitnodiging aanmaken als de gebruiker zelf (RLS en lidmaatschap worden in de database gecontroleerd)
    const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const res = await fetch(`${url}/rest/v1/rpc/pasr_group_invite`, {
      method: "POST",
      headers: { apikey: req.headers.get("apikey") ?? anon, authorization: auth, "Content-Type": "application/json" },
      body: JSON.stringify({ p_group: body.group, p_email: body.email }),
      signal: AbortSignal.timeout(15000),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg = String(data?.message ?? "");
      const code = ERRORS.find((e) => msg.includes(e))?.replace(/ /g, "_") ?? "server_error";
      return json({ error: code }, res.status === 401 ? 401 : code === "server_error" ? 502 : 400);
    }

    // 2. mail sturen
    const host = Deno.env.get("PASR_SMTP_HOST"), user = Deno.env.get("PASR_SMTP_USER");
    const pass = Deno.env.get("PASR_SMTP_PASSWORD"), sender = Deno.env.get("PASR_SMTP_FROM");
    if (!host || !user || !pass || !sender) return json({ ok: true, mailed: false, invite: data.id });
    try {
      const port = Number(Deno.env.get("PASR_SMTP_PORT") || 465);
      const t = nodemailer.createTransport({ host, port, secure: port === 465, auth: { user, pass } });
      const m = render(String(data.from ?? "Iemand"), String(data.group_name ?? "Gedeelde Pasr"));
      await t.sendMail({ from: `Pasr <${sender}>`, to: data.email, subject: m.subject, html: m.html, text: m.text });
      return json({ ok: true, mailed: true, invite: data.id });
    } catch (e) {
      console.error("group-invite: mail", (e as Error).name);
      return json({ ok: true, mailed: false, invite: data.id });
    }
  });
}
