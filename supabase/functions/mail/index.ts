// Pasr beheer › Mail: functie mail (verify_jwt = false, eigen kopregels). Uitleg, foutcodes en secrets: docs/beheer-mail.md.
//
// Alleen aanroepbaar met x-pasr-admin (de functie admin stuurt de acties mail_* door na haar sessiecontrole) of x-pasr-cron
// (pg_cron/pg_net, alleen poll_inbox). POST JSON {action, …}:
//   status {} · poll_inbox {} / admin_poll {} · thread_list · thread_get · thread_reply · thread_status · thread_note
//   compose · attachment_get · preview · test · campaign_audience · campaign_send · campaign_list · campaign_cancel
// Daarnaast, zonder kopregel: POST ?stop=<code> (afmelden met één klik uit het mailprogramma, RFC 8058).
// Nooit loggen: adressen, onderwerpen, inhoud, wachtwoorden.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { adminOk, sameText } from "./auth.ts";
import { runCampaign, continueCampaigns, withSignatureFlag } from "./campaign.ts";
import { BRAND_STYLE, type Kind, renderMail } from "./layout.ts";
import {
  type Attachment, type Brand, BRAND_FROM, chunk, fromFor, LIMITS, newMessageId, randomId, statusAfter, toBase64, tooLarge,
} from "./logic.ts";
import { renderMarkdown, textToHtml } from "./markdown.ts";
import { buildMessage, type BuiltMail, genericUnsubPage } from "./outbound.ts";
import { boxes, imapConfigured, pollInbox, replyToFor } from "./poll.ts";
import {
  parseAttachmentId, parseAudience, parseCampaign, parseCompose, parseId, parseNote, parsePreview, parseReply, parseTest, parseThreadList,
  parseThreadStatus, statusFor,
} from "./requests.ts";
import { makeTransport, sendBuilt, smtpConfigured, type Transport } from "./send.ts";

const env = (k: string) => (Deno.env.get(k) ?? "").trim();
/** Maximale grootte van een verzoek: bijlagen als base64 in JSON (20 MB bijlagen = ruim 26,7 MB) */
export const MAX_BODY = 32 * 1024 * 1024;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
const fail = (error: string, extra: Record<string, unknown> = {}) => json({ error, ...(error === "too_large" ? tooLarge() : {}), ...extra }, statusFor(error));

/** Foutcodes die de database zelf geeft (RAISE EXCEPTION 'not_found' enz.) */
const DB_CODES = new Set(["not_found", "bad_status", "bad_priority", "too_large", "not_cancellable", "bad_request", "bad_audience", "bad_scope"]);
const dbCode = (m: string) => (DB_CODES.has(m) ? m : "server_error");

let db: ReturnType<typeof createClient>;
const rpc = (name: string, args: Record<string, unknown> = {}) => db.rpc(name, args) as unknown as Promise<{ data: unknown; error: { message: string } | null }>;
async function call<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await rpc(name, args);
  if (error) throw new Error(error.message);
  return data as T;
}

// ---- hook-geheim (cron) en grenzen ----
let hookSecret: string | null = null, hookUntil = 0;
async function cronOk(given: string | null): Promise<boolean> {
  if (!given || given.length > 200) return false;
  if (!hookSecret || Date.now() > hookUntil) {
    const { data, error } = await db.from("pasr_secret").select("hook_secret").eq("id", 1).maybeSingle();
    if (error || !data?.hook_secret) return false;
    hookSecret = String(data.hook_secret);
    hookUntil = Date.now() + 300_000;
  }
  return sameText(given, hookSecret);
}
// per instantie: hoogstens 60 verzonden acties per uur (compose, antwoord) en 20 testmails; de database telt daarnaast de uitgaande berichten
let sends: number[] = [], tests: number[] = [];
function budget(list: number[], max: number): boolean {
  const cut = Date.now() - 3600_000;
  const l = list.filter((t) => t > cut);
  list.length = 0; list.push(...l);
  if (l.length >= max) return false;
  list.push(Date.now());
  return true;
}
const sendBudget = async () => budget(sends, LIMITS.composePerHour) && (await call<number>("pasr_mail_out_recent", { p_minutes: 60 })) < LIMITS.composePerHour * 3;

// ---- versturen ----
function withTransport<T>(fn: (send: (m: BuiltMail, brand: Brand) => Promise<{ ok: boolean; code?: string; permanent?: boolean }>) => Promise<T>): Promise<T> {
  const t: Transport = makeTransport(env);
  const send = async (m: BuiltMail, brand: Brand) => {
    const r = await sendBuilt(t, m, env, BRAND_FROM[brand].name);
    return r.ok ? { ok: true } : { ok: false, code: r.code, permanent: r.permanent };
  };
  return fn(send).finally(() => { try { t.close(); } catch { /* al dicht */ } });
}
const themeOf = (brand: Brand) => BRAND_STYLE[brand].theme;
const scopeOf = (brand: Brand) => (brand === "zakelijk" ? "news-owners" : "news-users");

async function storeAtts(messageId: string, list: Attachment[]) {
  for (const a of list) await call("pasr_mail_attach", { p_message: messageId, p_campaign: null, p_name: a.name, p_type: a.type, p_b64: toBase64(a.data) });
}

// ---- acties ----
async function handle(action: string, b: Record<string, unknown>, viaCron: boolean): Promise<Response> {
  if (viaCron && action !== "poll_inbox") return fail("forbidden");
  switch (action) {
    case "status": {
      const [sync, counts] = await Promise.all([call<Record<string, unknown> | null>("pasr_mail_sync_state"), call<Record<string, number>>("pasr_mail_counts")]);
      return json({
        smtp: smtpConfigured(env), imap: imapConfigured(env), mailboxes: boxes(env).map((x) => x.brand),
        brands: { pasr: { from: fromFor("pasr", env) }, zakelijk: { from: fromFor("zakelijk", env) } },
        autoreply: env("PASR_MAIL_AUTOREPLY") === "1",
        sync: { last_run: sync?.last_run ?? null, last_error: sync?.last_error ?? null, fetched: sync?.fetched ?? 0, imported: sync?.imported ?? 0 },
        counts,
      });
    }
    case "poll_inbox": case "admin_poll": {
      const r = await withTransport((send) => pollInbox({ rpc, env, send }).then(async (p) => {
        // lopende campagnes gaan verder waar een aanroep stopte (cron)
        const resumed = smtpConfigured(env) ? await continueCampaigns({ rpc, env, send }, 60_000).catch(() => 0) : 0;
        return { ...p, campaigns: resumed };
      }));
      return json(r);
    }
    case "thread_list": {
      const v = parseThreadList(b);
      if (!v.ok) return fail(v.error);
      return json(await call("pasr_mail_thread_list", { p_status: v.value.status, p_q: v.value.q, p_brand: v.value.brand, p_page: v.value.page, p_size: v.value.size, p_box: v.value.box }));
    }
    case "thread_get": {
      const n = parseId(b.number);
      if (!n) return fail("bad_number");
      const r = await call<unknown>("pasr_mail_thread_get", { p_number: n, p_mark_read: true });
      return r ? json(r) : fail("not_found");
    }
    case "thread_status": {
      const v = parseThreadStatus(b);
      if (!v.ok) return fail(v.error);
      return json({ ok: true, ...(await call<Record<string, unknown>>("pasr_mail_thread_set", { p_number: v.value.number, p_status: v.value.status, p_priority: v.value.priority })) });
    }
    case "thread_note": {
      const v = parseNote(b);
      if (!v.ok) return fail(v.error);
      const r = await call<{ id: string }>("pasr_mail_message_add", {
        p_number: v.value.number, p_direction: "note", p_from: "beheer", p_to: [], p_cc: [], p_bcc_count: 0, p_subject: "", p_text: v.value.text,
        p_html: textToHtml(v.value.text), p_md: null, p_message_id: null, p_in_reply_to: null, p_refs: [], p_brand: null, p_status: null, p_error: null, p_sent: false,
      });
      return json({ ok: true, id: r.id });
    }
    case "thread_reply": {
      const v = parseReply(b);
      if (!v.ok) return fail(v.error);
      if (!smtpConfigured(env)) return fail("smtp_not_configured");
      if (!(await sendBudget())) return fail("rate_limited");
      const meta = await call<{ brand: Brand; status: "new" | "open" | "pending" | "closed"; subject: string; contact_email: string; ids: string[] } | null>("pasr_mail_thread_meta", { p_number: v.value.number });
      if (!meta) return fail("not_found");
      if (!meta.contact_email) return fail("bad_address");
      const brand = v.value.brand ?? meta.brand;
      const messageId = newMessageId(v.value.number, randomId());
      const built = buildMessage({
        brand, kind: "reply", from: fromFor(brand, env), replyTo: replyToFor(env, brand), to: [meta.contact_email], cc: v.value.cc, bcc: v.value.bcc,
        subject: meta.subject, markdown: v.value.body_md, number: v.value.number, messageId, inReplyTo: meta.ids.at(-1), references: meta.ids,
        attachments: v.value.attachments, signature: v.value.signature,
      });
      const res = await withTransport((send) => send(built, brand));
      if (!res.ok) return json({ error: "send_failed", code: res.code ?? "error" }, 502);
      const rendered = renderMarkdown(v.value.body_md, themeOf(brand));
      const status = v.value.status ?? statusAfter(meta.status, "support");
      const r = await call<{ id: string | null }>("pasr_mail_message_add", {
        p_number: v.value.number, p_direction: "out", p_from: fromFor(brand, env), p_to: [meta.contact_email], p_cc: v.value.cc, p_bcc_count: v.value.bcc.length,
        p_subject: built.subject, p_text: rendered.text, p_html: rendered.html, p_md: v.value.body_md, p_message_id: messageId, p_in_reply_to: meta.ids.at(-1) ?? null,
        p_refs: meta.ids, p_brand: brand, p_status: status, p_error: null, p_sent: true,
      });
      if (r.id) await storeAtts(r.id, v.value.attachments).catch((e) => console.error("mail reply attach", String(e?.message ?? e).slice(0, 60)));
      return json({ ok: true, status, email_sent: true, message_id: messageId });
    }
    case "compose": {
      const v = parseCompose(b);
      if (!v.ok) return fail(v.error);
      if (!smtpConfigured(env)) return fail("smtp_not_configured");
      if (!(await sendBudget())) return fail("rate_limited");
      const c = v.value;
      // uitnodigingen per BCC: wie zich heeft afgemeld, krijgt niets meer
      let bcc = c.bcc, skipped = 0;
      const scope = scopeOf(c.brand);
      if (bcc.length) {
        const keep = new Set((await call<{ email: string }[] | null>("pasr_mail_list_tokens", { p_emails: bcc, p_scope: scope }) ?? []).map((x) => x.email));
        bcc = bcc.filter((a) => keep.has(a));
        skipped = c.bcc.length - bcc.length;
      }
      if (c.to.length + c.cc.length + bcc.length === 0) return json({ ok: true, sent: 0, failed: 0, skipped });
      const kind: Kind = bcc.length ? "invite" : "mail";
      const unsub = bcc.length ? { page: genericUnsubPage(c.brand === "zakelijk" ? "owners" : "users") } : undefined;
      const number = c.thread
        ? await call<number>("pasr_mail_thread_create", { p_brand: c.brand, p_subject: c.subject, p_email: c.to[0] ?? c.cc[0] ?? "", p_name: "" })
        : null;
      // BCC in groepen van 50 per mail; de eerste mail heeft ook Aan en CC
      const groups = bcc.length ? chunk(bcc, LIMITS.bccPerMail) : [[]];
      const ids: string[] = [];
      let sent = 0, failed = 0, lastCode = "";
      await withTransport(async (send) => {
        for (let i = 0; i < groups.length; i++) {
          const id = newMessageId(number, randomId());
          const to = i === 0 ? c.to : [], cc = i === 0 ? c.cc : [];
          const m = buildMessage({
            brand: c.brand, kind, from: fromFor(c.brand, env), replyTo: replyToFor(env, c.brand), to, cc, bcc: groups[i],
            subject: c.subject, markdown: c.body_md, number, messageId: id, attachments: c.attachments, unsub, signature: c.signature,
          });
          const r = await send(m, c.brand);
          const n = to.length + cc.length + groups[i].length;
          if (r.ok) { sent += n; ids.push(id); } else { failed += n; lastCode = r.code ?? "error"; }
        }
      });
      if (number) {
        if (ids.length) {
          const rendered = renderMarkdown(c.body_md, themeOf(c.brand));
          const r = await call<{ id: string | null }>("pasr_mail_message_add", {
            p_number: number, p_direction: "out", p_from: fromFor(c.brand, env), p_to: c.to, p_cc: c.cc, p_bcc_count: bcc.length, p_subject: c.subject,
            p_text: rendered.text, p_html: rendered.html, p_md: c.body_md, p_message_id: ids[0], p_in_reply_to: null, p_refs: ids, p_brand: c.brand,
            p_status: "pending", p_error: failed ? `${failed} niet verstuurd` : null, p_sent: true,
          });
          if (r.id) await storeAtts(r.id, c.attachments).catch((e) => console.error("mail compose attach", String(e?.message ?? e).slice(0, 60)));
        } else await rpc("pasr_mail_thread_delete_empty", { p_number: number });
      }
      if (bcc.length) {
        // overzicht van uitnodigingen: alleen aantallen, nooit de adressen
        const camp = await call<{ id: number }>("pasr_mail_campaign_create", { p_brand: c.brand, p_audience: "list", p_subject: c.subject, p_body_md: "", p_request: crypto.randomUUID(), p_recipients: bcc.length });
        const bccSent = Math.min(bcc.length, sent), bccFailed = Math.min(bcc.length, failed);
        await rpc("pasr_mail_campaign_progress", { p_id: camp.id, p_sent_hashes: [], p_failed: bccFailed, p_done: false, p_sent_extra: bccSent, p_failed_hashes: [] });
      }
      if (sent === 0) return json({ error: "send_failed", code: lastCode || "error", sent, failed }, 502);
      return json({ ok: true, sent, failed, skipped, ...(number ? { number } : {}) });
    }
    case "attachment_get": {
      const id = parseAttachmentId(b);
      if (!id) return fail("bad_id");
      const r = await call<unknown>("pasr_mail_attachment_get", { p_id: id });
      return r ? json(r) : fail("not_found");
    }
    case "preview": {
      const v = parsePreview(b);
      if (!v.ok) return fail(v.error);
      const kind: Kind = b.kind === "news" || b.kind === "invite" || b.kind === "reply" ? b.kind : "mail";
      const m = renderMail({
        brand: v.value.brand, kind, subject: v.value.subject || "Voorbeeld", markdown: v.value.body_md,
        unsubUrl: kind === "news" || kind === "invite" ? genericUnsubPage(v.value.brand === "zakelijk" ? "owners" : "users") : undefined,
        signature: v.value.signature,
        vars: { voornaam: typeof b.voornaam === "string" ? b.voornaam.slice(0, 40) : undefined },
      });
      return json({ html: m.html, text: m.text });
    }
    case "test": {
      const v = parseTest(b);
      if (!v.ok) return fail(v.error);
      if (!smtpConfigured(env)) return fail("smtp_not_configured");
      if (!budget(tests, 20)) return fail("rate_limited");
      const brand = v.value.brand;
      const built = buildMessage({
        brand, kind: "news", from: fromFor(brand, env), replyTo: replyToFor(env, brand), to: [v.value.to], cc: [], bcc: [], subject: `[Test] ${v.value.subject}`,
        markdown: v.value.body_md, messageId: newMessageId(null, randomId()), unsub: { page: genericUnsubPage(brand === "zakelijk" ? "owners" : "users") }, signature: v.value.signature,
      });
      const r = await withTransport((send) => send(built, brand));
      return r.ok ? json({ ok: true }) : json({ error: "send_failed", code: r.code ?? "error" }, 502);
    }
    case "campaign_audience": {
      const v = parseAudience(b);
      if (!v.ok) return fail(v.error);
      return json({ count: await call<number>("pasr_mail_audience_count", { p_audience: v.value }) });
    }
    case "campaign_send": {
      const v = parseCampaign(b);
      if (!v.ok) return fail(v.error);
      if (!smtpConfigured(env)) return fail("smtp_not_configured");
      const c = v.value;
      const count = await call<number>("pasr_mail_audience_count", { p_audience: c.audience });
      if (count < 1) return fail("no_recipients");
      const camp = await call<{ id: number; created: boolean; status: string; recipients: number; sent: number; failed: number }>("pasr_mail_campaign_create", {
        p_brand: c.brand, p_audience: c.audience, p_subject: c.subject, p_body_md: withSignatureFlag(c.body_md, c.signature), p_request: c.request_id, p_recipients: count,
      });
      // dezelfde aanvraag (dubbele tik): de bestaande campagne, niets opnieuw versturen
      if (!camp.created) return json({ ok: true, campaign_id: camp.id, recipients: camp.recipients, sent: camp.sent, failed: camp.failed, status: camp.status, duplicate: true });
      for (const a of c.attachments) await call("pasr_mail_attach", { p_message: null, p_campaign: camp.id, p_name: a.name, p_type: a.type, p_b64: toBase64(a.data) });
      // eerste ronde meteen (hoogstens 90 s); de rest volgt via de cron
      const r = await withTransport((send) => runCampaign({ rpc, env, send }, camp.id, 90_000));
      return json({ ok: true, campaign_id: camp.id, recipients: camp.recipients, sent: r.sent, failed: r.failed, status: r.status, left: r.left });
    }
    case "campaign_list": return json(await call("pasr_mail_campaign_list"));
    case "campaign_cancel": {
      const id = parseId(b.id);
      if (!id) return fail("bad_id");
      return json({ ok: true, ...(await call<Record<string, unknown>>("pasr_mail_campaign_cancel", { p_id: id })) });
    }
    default: return fail("unknown_action");
  }
}

export async function serve(req: Request): Promise<Response> {
  const u = new URL(req.url);
  // afmelden met één klik uit het mailprogramma (List-Unsubscribe-Post); de code is de autorisatie
  const stop = u.searchParams.get("stop");
  if (stop && req.method === "POST") {
    const { error } = await rpc("pasr_mail_unsubscribe", { p_token: stop.slice(0, 64) });
    return json({ ok: !error }, error ? 500 : 200);
  }
  if (req.method !== "POST") return fail("method_not_allowed");
  const viaAdmin = await adminOk(req.headers.get("x-pasr-admin"), env("PASR_TOKEN_SECRET"));
  const viaCron = !viaAdmin && (await cronOk(req.headers.get("x-pasr-cron")));
  if (!viaAdmin && !viaCron) return fail("forbidden");
  let body: Record<string, unknown>;
  try {
    const text = await req.text();
    if (text.length > MAX_BODY) return fail("too_large");
    const b = JSON.parse(text || "{}");
    if (!b || typeof b !== "object" || Array.isArray(b)) return fail("bad_json");
    body = b;
  } catch { return fail("bad_json"); }
  const action = typeof body.action === "string" ? body.action : "";
  try {
    return await handle(action, body, viaCron);
  } catch (e) {
    const m = e instanceof Error ? e.message : "?";
    // alleen de code, nooit adressen of inhoud
    console.error("mail", action || "?", m.replace(/[^\s@]+@[^\s@]+/g, "…").slice(0, 120));
    const code = dbCode(m);
    return fail(code);
  }
}

if (import.meta.main) {
  db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { autoRefreshToken: false, persistSession: false } });
  Deno.serve(serve);
}
