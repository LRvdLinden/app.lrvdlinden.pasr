// Pasr beheer › Mail: de inbox-import (IMAP). Elke 5 minuten (pg_cron) of met "Nu ophalen" in het beheer. Alle mails in INBOX zonder
// het trefwoord $PasrDone gaan langs (hoogstens 25 per ronde); de beslissing per mail staat in inbox.ts (decide). Geen
// bevestigingsmail aan afzenders tenzij PASR_MAIL_AUTOREPLY=1. Wat we loggen zijn alleen codes en aantallen, nooit adressen of onderwerpen.
// Alles wat met de database praat gaat via rpc (pasr_mail_*), zodat poll_test.ts het met een nep-database kan testen.
import { Imap } from "./imap.ts";
import { type ParsedMail, parseMessage } from "./mime.ts";
import {
  agentList, authservNames, candidateNumbers, cleanSubject, type Decision, decide, DONE_KEYWORD, findFolder, FOLLOW_UP, guessLang,
  isFinal, keywordAllowed, MAX_FETCH_BYTES, messageBody, OTHER_SENDER, pickQueue, referencedIds, RELATED, senderName, type TicketLite,
} from "./inbox.ts";
import { addressOf, type Brand, fromFor, LIMITS, newMessageId, randomId, statusAfter, validEmail } from "./logic.ts";
import { plainToMarkdown, textToHtml } from "./markdown.ts";
import { buildMessage, type BuiltMail } from "./outbound.ts";

export type Rpc = (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
export type PollDeps = {
  rpc: Rpc;
  env: (k: string) => string;
  connect?: (o: { host: string; port: number; timeoutMs: number }) => Promise<Imap>;
  /** een mail versturen (antwoord van een medewerker per mail; ontvangstbevestiging) */
  send: (m: BuiltMail, brand: Brand) => Promise<{ ok: boolean; code?: string }>;
  now?: () => number;
};
export type PollResult = {
  ok: boolean; skipped?: string; busy?: boolean; error?: string;
  fetched: number; imported: number; new_threads: number; replies: number; agent: number; ignored: number; rejected: number; duplicates: number; errors: number;
  reasons?: Record<string, number>; pending?: number; more?: boolean; ms?: number; notified?: number;
};

export const IMAP_BUDGET_MS = 45000;
export const IMAP_MAX_PER_RUN = 25;
/** Bijlagen uit binnengekomen mail: per mail in totaal hoogstens dit (de rest krijgt een regel "niet overgenomen"). */
export const KEEP_BYTES = LIMITS.attachmentsTotal;

const lc = (s: string) => s.trim().toLowerCase();
const errText = (e: unknown) => (e instanceof Error ? e.message : String(e)).replace(/[\r\n]+/g, " ").replace(/[^\s@]+@[^\s@]+/g, "…").slice(0, 300);

export type Box = { brand: Brand; user: string; pass: string };
export function boxes(env: (k: string) => string): Box[] {
  const out: Box[] = [];
  if (env("PASR_IMAP_HOST") && env("PASR_IMAP_USER") && env("PASR_IMAP_PASSWORD")) {
    out.push({ brand: "pasr", user: env("PASR_IMAP_USER"), pass: env("PASR_IMAP_PASSWORD") });
    if (env("PASR_IMAP_ZAKELIJK_USER") && env("PASR_IMAP_ZAKELIJK_PASSWORD")) {
      out.push({ brand: "zakelijk", user: env("PASR_IMAP_ZAKELIJK_USER"), pass: env("PASR_IMAP_ZAKELIJK_PASSWORD") });
    }
  }
  return out;
}
export const imapConfigured = (env: (k: string) => string) => boxes(env).length > 0;

/** Adressen die als medewerker mogen antwoorden: de afzenders van beide merken, de IMAP-logins en PASR_MAIL_AGENTS. */
export function ownAddresses(env: (k: string) => string): string[] {
  return [addressOf(fromFor("pasr", env)), addressOf(fromFor("zakelijk", env)), env("PASR_IMAP_USER"), env("PASR_IMAP_ZAKELIJK_USER")].filter(Boolean);
}
export const agentsOf = (env: (k: string) => string) => agentList(ownAddresses(env), env("PASR_MAIL_AGENTS"));

type Found = TicketLite & { brand: Brand };
type Rec = { number: number; email: string; status: TicketLite["status"]; brand: Brand; mids?: string[] };
const STRONG = /^<pasr-ticket-\d+\.[A-Za-z0-9_-]{6,}@/;

async function call<T>(rpc: Rpc, name: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data as T;
}

export async function ticketsFor(rpc: Rpc, mail: ParsedMail): Promise<Found[]> {
  const nums = candidateNumbers(mail);
  const ids = referencedIds(mail).filter((i) => i.length > 2);
  if (!nums.length && !ids.length) return [];
  const rows = (await call<Rec[] | null>(rpc, "pasr_mail_threads_for", { p_numbers: nums, p_ids: ids })) ?? [];
  const list: Found[] = rows.map((r) => ({
    number: Number(r.number), email: String(r.email ?? ""), status: r.status, lang: "nl" as const, brand: r.brand,
    strong: (r.mids ?? []).some((m) => STRONG.test(m) && ids.includes(m)),
  }));
  const ordered = nums.map((n) => list.find((t) => t.number === n)).filter((t): t is Found => !!t);
  for (const t of list) if (!ordered.includes(t)) ordered.push(t);
  return ordered;
}

/** Wat een pushmelding nodig heeft: nummer, merk en onderwerp (nooit adressen of inhoud). */
export type NewMail = { number: number; brand: Brand; subject: string };
export type InboxResult = { result: string; ticket?: number | null; seen: boolean; move: boolean; notify?: NewMail };

type Ctx = PollDeps & { box: Brand; agents: string[]; authserv: string[] };

/** Bijlagen die we opslaan: in volgorde tot 10 MB in totaal; de rest verliest zijn bytes (en krijgt een regel in de tekst). */
export function pickAttachments(mail: ParsedMail): ParsedMail["attachments"] {
  let total = 0;
  for (const a of mail.attachments) {
    if (a.data && total + a.data.length <= KEEP_BYTES) total += a.data.length; else delete a.data;
  }
  return mail.attachments.filter((a) => a.data);
}
const b64 = (b: Uint8Array) => { let s = ""; for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192)); return btoa(s); };

async function storeAttachments(rpc: Rpc, messageId: string, list: ParsedMail["attachments"]) {
  for (const a of list) {
    try {
      await call(rpc, "pasr_mail_attach", { p_message: messageId, p_campaign: null, p_name: a.filename, p_type: a.contentType, p_b64: b64(a.data!) });
    } catch (e) { console.error("mail poll attach", errText(e).slice(0, 60)); }
  }
}

const mailRef = (m: ParsedMail) => ({ id: m.messageId.slice(0, 300), irt: m.inReplyTo[0]?.slice(0, 300) ?? null, refs: [...m.references, ...m.inReplyTo].slice(-20) });

export async function handleMail(mail: ParsedMail, ctx: Ctx): Promise<InboxResult> {
  const { rpc } = ctx;
  if (await call<boolean>(rpc, "pasr_mail_message_exists", { p_message_id: mail.messageId.slice(0, 300) })) return { result: "duplicate", seen: true, move: true };
  const tickets = await ticketsFor(rpc, mail);
  const d: Decision = decide(mail, tickets, ctx.agents, ctx.authserv);
  const ref = mailRef(mail);
  const from = mail.from?.address ? lc(mail.from.address) : "";
  const to = mail.to.slice(0, 10).map((a) => a.address);

  switch (d.kind) {
    case "ignore": return { result: `ignored:${d.reason}`, seen: false, move: false };
    case "reject": return { result: `rejected:${d.reason}`, ticket: tickets[0]?.number ?? null, seen: false, move: false };
    case "customer_reply": {
      const t = d.ticket as Found;
      const kept = pickAttachments(mail);
      let body = messageBody(mail, t.lang);
      if (!body) return { result: "rejected:empty", ticket: t.number, seen: false, move: false };
      if (d.otherSender) body = `${OTHER_SENDER[t.lang]}\n\n${body}`.slice(0, LIMITS.message);
      const r = await call<{ id: string | null; duplicate: boolean }>(rpc, "pasr_mail_message_add", {
        p_number: t.number, p_direction: "in", p_from: from, p_to: to, p_cc: [], p_bcc_count: 0, p_subject: mail.subject, p_text: body, p_html: textToHtml(body),
        p_md: null, p_message_id: ref.id, p_in_reply_to: ref.irt, p_refs: ref.refs, p_brand: t.brand, p_status: statusAfter(t.status, "contact"), p_error: null, p_sent: false,
      });
      if (r.duplicate || !r.id) return { result: "duplicate", ticket: t.number, seen: true, move: true };
      await storeAttachments(rpc, r.id, kept);
      return { result: "imported", ticket: t.number, seen: true, move: true, notify: { number: t.number, brand: t.brand, subject: cleanSubject(mail.subject, t.lang).slice(0, 60) } };
    }
    case "agent_reply": {
      const t = d.ticket as Found;
      const kept = pickAttachments(mail);
      const body = messageBody(mail, t.lang);
      if (!body) return { result: "rejected:empty", ticket: t.number, seen: false, move: false };
      if (!validEmail(t.email)) return { result: "rejected:no_contact", ticket: t.number, seen: false, move: false };
      const out = await sendToContact(ctx, t, body, kept, from);
      const r = await call<{ id: string | null; duplicate: boolean }>(rpc, "pasr_mail_message_add", {
        p_number: t.number, p_direction: "out", p_from: from, p_to: [t.email], p_cc: [], p_bcc_count: 0, p_subject: mail.subject, p_text: body,
        p_html: textToHtml(body), p_md: plainToMarkdown(body), p_message_id: ref.id, p_in_reply_to: ref.irt, p_refs: ref.refs, p_brand: t.brand,
        p_status: statusAfter(t.status, "support"), p_error: out.ok ? null : `niet gemaild: ${out.code ?? "error"}`, p_sent: out.ok,
      });
      if (r.duplicate || !r.id) return { result: "duplicate", ticket: t.number, seen: true, move: true };
      await storeAttachments(rpc, r.id, kept);
      return { result: out.ok ? "agent" : `agent:not_sent`, ticket: t.number, seen: true, move: true };
    }
    case "new_ticket": {
      if (!validEmail(from)) return { result: "rejected:bad_email", seen: false, move: false };
      // per afzender 3 nieuwe tickets per uur
      if ((await call<number>(rpc, "pasr_mail_contact_recent", { p_email: from, p_hours: 1 })) >= 3) return { result: "rejected:rate_limited", seen: false, move: false };
      const lang = guessLang(mail, mail.text);
      const kept = pickAttachments(mail);
      let body = messageBody(mail, lang);
      if (!body) return { result: "rejected:empty", seen: false, move: false };
      if (d.followUp) body = `${FOLLOW_UP[lang](d.followUp)}\n\n${body}`.slice(0, LIMITS.message);
      else if (d.related) body = `${RELATED[lang](d.related)}\n\n${body}`.slice(0, LIMITS.message);
      const number = await call<number>(rpc, "pasr_mail_thread_create", { p_brand: ctx.box, p_subject: cleanSubject(mail.subject, lang), p_email: from, p_name: senderName(mail) });
      const r = await call<{ id: string | null; duplicate: boolean }>(rpc, "pasr_mail_message_add", {
        p_number: number, p_direction: "in", p_from: from, p_to: to, p_cc: [], p_bcc_count: 0, p_subject: mail.subject, p_text: body, p_html: textToHtml(body),
        p_md: null, p_message_id: ref.id, p_in_reply_to: ref.irt, p_refs: ref.refs, p_brand: ctx.box, p_status: "new", p_error: null, p_sent: false,
      });
      if (r.duplicate || !r.id) {
        await rpc("pasr_mail_thread_delete_empty", { p_number: number });
        return { result: "duplicate", seen: true, move: true };
      }
      await storeAttachments(rpc, r.id, kept);
      if (ctx.env("PASR_MAIL_AUTOREPLY") === "1") await autoReply(ctx, number, from, ctx.box).catch((e) => console.error("mail poll autoreply", errText(e).slice(0, 60)));
      return { result: "new_ticket", ticket: number, seen: true, move: true, notify: { number, brand: ctx.box, subject: cleanSubject(mail.subject, lang).slice(0, 60) } };
    }
  }
}

/** Antwoord van een medewerker per mail: als gebrande mail naar het contact van het ticket (met het ticketnummer in het onderwerp). */
async function sendToContact(ctx: Ctx, t: Found, body: string, kept: ParsedMail["attachments"], _agent: string) {
  const meta = await call<{ subject: string; ids: string[] } | null>(ctx.rpc, "pasr_mail_thread_meta", { p_number: t.number });
  const ids = meta?.ids ?? [];
  const m = buildMessage({
    brand: t.brand, kind: "reply", from: fromFor(t.brand, ctx.env), replyTo: replyToFor(ctx.env, t.brand), to: [t.email], cc: [], bcc: [],
    subject: meta?.subject ?? "Bericht van Pasr", markdown: plainToMarkdown(body), number: t.number,
    messageId: newMessageId(t.number, randomId()), inReplyTo: ids[ids.length - 1], references: ids,
    attachments: kept.map((a) => ({ name: a.filename, type: a.contentType, data: a.data! })),
  });
  return await ctx.send(m, t.brand);
}
async function autoReply(ctx: Ctx, number: number, to: string, brand: Brand) {
  const text = `Bedankt voor je bericht. We hebben het ontvangen (ticket #${number}) en reageren zo snel mogelijk.`;
  const m = buildMessage({
    brand, kind: "reply", from: fromFor(brand, ctx.env), replyTo: replyToFor(ctx.env, brand), to: [to], cc: [], bcc: [], subject: "We hebben je bericht ontvangen",
    markdown: text, number, messageId: newMessageId(number, randomId()),
  });
  m.headers["Auto-Submitted"] = "auto-replied";
  await ctx.send(m, brand);
}
/** Reply-To = het adres van de postbus van het merk, zodat antwoorden in het beheer terugkomen. */
export function replyToFor(env: (k: string) => string, brand: Brand): string {
  if (brand === "zakelijk") return env("PASR_IMAP_ZAKELIJK_USER") || addressOf(fromFor(brand, env));
  return env("PASR_IMAP_USER") || addressOf(fromFor(brand, env));
}

export async function pollInbox(d: PollDeps): Promise<PollResult> {
  const bx = boxes(d.env);
  const zero = { fetched: 0, imported: 0, new_threads: 0, replies: 0, agent: 0, ignored: 0, rejected: 0, duplicates: 0, errors: 0 };
  if (!bx.length) return { ok: true, skipped: "imap not configured", ...zero };
  const got = await call<boolean>(d.rpc, "pasr_mail_sync_lock", { p_seconds: 120 });
  if (got !== true) return { ok: true, busy: true, ...zero };
  const now = d.now ?? Date.now;
  const started = now();
  const c = { ...zero };
  const reasons: Record<string, number> = {};
  let pending = 0, stopped = false, lastUid: number | null = null, uidvalidity: number | null = null, err: string | null = null;
  let errorUid: number | null = null, errorCount = 0;
  const fresh: NewMail[] = [];
  const agents = agentsOf(d.env);
  const authserv = authservNames(d.env("PASR_IMAP_HOST"), d.env("PASR_MAIL_AUTHSERV"));
  const state = await call<{ error_uid?: number; error_count?: number } | null>(d.rpc, "pasr_mail_sync_state", {}).catch(() => null);
  try {
    for (const box of bx) {
      if (stopped || now() - started > IMAP_BUDGET_MS) { stopped = true; break; }
      let imap: Imap | null = null;
      try {
        imap = await (d.connect ?? ((o) => Imap.connect(o)))({ host: d.env("PASR_IMAP_HOST"), port: Number(d.env("PASR_IMAP_PORT") || 993), timeoutMs: 20000 });
        imap.maxLiteral = MAX_FETCH_BYTES + 1024 * 1024;
        await imap.login(box.user, box.pass);
        const folders = await imap.list().catch(() => []);
        const done = findFolder(folders);
        const sel = await imap.select("INBOX");
        if (box.brand === "pasr") uidvalidity = sel.uidvalidity;
        const kw = keywordAllowed(sel.permanentFlags);
        const cands = sel.exists ? await imap.uidSearch(`NOT KEYWORD ${DONE_KEYWORD}`) : [];
        const doneInLog = new Set<number>();
        for (let i = 0; i < cands.length; i += 500) {
          const part = cands.slice(i, i + 500);
          const rows = await call<number[] | null>(d.rpc, "pasr_mail_log_done", { p_box: box.brand, p_uidvalidity: sel.uidvalidity, p_uids: part });
          for (const u of rows ?? []) doneInLog.add(Number(u));
        }
        const { queue, pending: p } = pickQueue(cands, doneInLog, IMAP_MAX_PER_RUN - c.fetched);
        pending += p;
        const seen: number[] = [], move: number[] = [], final: number[] = [];
        for (const uid of queue) {
          if (now() - started > IMAP_BUDGET_MS) { stopped = true; break; }
          let mail: ParsedMail | null = null;
          let r: InboxResult;
          try {
            const [it] = await imap.uidFetch([uid], `(UID RFC822.SIZE BODY.PEEK[]<0.${MAX_FETCH_BYTES}>)`);
            if (!it?.body) r = { result: "error:retry", seen: false, move: false };
            else {
              c.fetched++;
              mail = parseMessage(it.body, { truncated: (it.size ?? 0) > MAX_FETCH_BYTES, keepBytes: KEEP_BYTES });
              if (!mail.messageId) mail.messageId = `<imap-${box.brand}-${sel.uidvalidity}-${uid}@pasr.invalid>`;
              r = await handleMail(mail, { ...d, box: box.brand, agents, authserv });
            }
          } catch (e) {
            // databasefout of iets onverwachts: deze mail de volgende ronde opnieuw; drie rondes achter elkaar fout = overslaan
            console.error("mail poll", uid, errText(e));
            const tries = Number(state?.error_uid) === uid ? Number(state?.error_count ?? 0) + 1 : 1;
            if (tries < 3) {
              c.errors++; errorUid = uid; errorCount = tries;
              await d.rpc("pasr_mail_log_add", { p_box: box.brand, p_uid: uid, p_uidvalidity: sel.uidvalidity, p_result: "error", p_ticket: null }).catch(() => {});
              stopped = true;
              break;
            }
            r = { result: "error:skipped", seen: false, move: false };
          }
          await d.rpc("pasr_mail_log_add", { p_box: box.brand, p_uid: uid, p_uidvalidity: sel.uidvalidity, p_result: r.result, p_ticket: r.ticket ?? null }).catch(() => {});
          if (r.notify) fresh.push(r.notify);
          const key = r.result.split(":")[0];
          if (key === "imported") { c.replies++; c.imported++; }
          else if (key === "agent") { c.agent++; c.imported++; }
          else if (key === "new_ticket") { c.new_threads++; c.imported++; }
          else if (key === "ignored") c.ignored++;
          else if (key === "duplicate") c.duplicates++;
          else if (key === "error") c.errors++;
          else c.rejected++;
          if (key === "ignored" || key === "rejected" || key === "error") reasons[r.result] = (reasons[r.result] ?? 0) + 1;
          if (isFinal(r.result)) { final.push(uid); pending--; }
          if (r.seen) seen.push(uid);
          if (r.move) move.push(uid);
          if (box.brand === "pasr") lastUid = Math.max(lastUid ?? 0, uid);
        }
        const seenSet = new Set(seen);
        if (kw) {
          const both = final.filter((u) => seenSet.has(u)), only = final.filter((u) => !seenSet.has(u));
          if (both.length) await imap.uidStore(both, `+FLAGS.SILENT (\\Seen ${DONE_KEYWORD})`);
          if (only.length) await imap.uidStore(only, `+FLAGS.SILENT (${DONE_KEYWORD})`);
          const rest = seen.filter((u) => !final.includes(u));
          if (rest.length) await imap.uidStore(rest, "+FLAGS.SILENT (\\Seen)");
        } else if (seen.length) await imap.uidStore(seen, "+FLAGS.SILENT (\\Seen)");
        if (move.length && done) await imap.uidMove(move, done);
        await imap.logout();
        imap = null;
      } catch (e) {
        err = errText(e);
        console.error("mail poll box", box.brand, err);
      } finally {
        imap?.close();
      }
    }
  } finally {
    await d.rpc("pasr_mail_sync_done", {
      p_fetched: c.fetched, p_imported: c.imported, p_error: err ?? (c.errors ? "Een mail gaf een fout; volgende ronde opnieuw" : null),
      p_uid: lastUid, p_uidvalidity: uidvalidity, p_error_uid: errorUid, p_error_count: errorCount,
    }).catch((e) => console.error("mail poll sync_done", errText(e)));
  }
  // één pushmelding per ronde voor alle nieuwe tickets en klantantwoorden (de database geeft de functie admin een seintje); een fout hier houdt de ronde niet op
  let notified = 0;
  if (fresh.length) {
    const { error } = await d.rpc("pasr_mail_notify", { p_items: fresh.slice(0, 20) }).catch((e) => ({ error: { message: errText(e) } }));
    if (error) console.error("mail poll notify", String(error.message).slice(0, 60)); else notified = fresh.length;
  }
  return { ok: !err, ...(err ? { error: err } : {}), ...c, notified, reasons, pending: Math.max(0, pending), more: stopped || pending > 0, ms: now() - started };
}
