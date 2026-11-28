// Pasr beheer › Mail: de verzoeken van het beheer controleren (puur, getest in requests_test.ts). Elke functie geeft
// {ok:true, value} of {ok:false, error}; de foutcodes staan in docs/beheer-mail.md. Adressen komen nooit in een foutmelding.
import {
  type Attachment, type Audience, type Brand, checkAddresses, cleanText, type ComposeAddresses, isAudience, isBrand, isStatus,
  LIMITS, parseAttachments, PRIORITIES, type Status, validEmail,
} from "./logic.ts";
import { markdownProblem } from "./markdown.ts";

export type Err = { ok: false; error: string };
export type Res<T> = { ok: true; value: T } | Err;
const fail = (error: string): Err => ({ ok: false, error });
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function cleanNumber(v: unknown): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" && /^#?\d{1,12}$/.test(v.trim()) ? Number(v.trim().replace("#", "")) : NaN;
  return Number.isInteger(n) && n > 0 && n < 1e12 ? n : null;
}

function subjectOf(b: Record<string, unknown>): string | null {
  const s = cleanText(b.subject, LIMITS.subject + 1);
  return s.length >= 1 && s.length <= LIMITS.subject ? s : null;
}
function bodyOf(b: Record<string, unknown>): string | null {
  const s = typeof b.body_md === "string" ? b.body_md.replace(/\r\n?/g, "\n").trim() : "";
  if (!s || s.length > LIMITS.bodyMd || markdownProblem(s)) return null;
  return s;
}
/** signature: standaard true; alleen false (of "false"/0) zet hem uit */
export const signatureOf = (v: unknown): boolean => !(v === false || v === "false" || v === 0);
const brandOf = (v: unknown, fallback: Brand = "pasr"): Brand | null => (v === undefined || v === null || v === "" ? fallback : isBrand(v) ? v : null);

export type Compose = ComposeAddresses & { subject: string; body_md: string; brand: Brand; attachments: Attachment[]; thread: boolean; signature: boolean };
export function parseCompose(b: Record<string, unknown>): Res<Compose> {
  const a = checkAddresses(b);
  if (!a.ok) return fail(a.error === "no_recipient" ? "bad_address" : a.error);
  const subject = subjectOf(b);
  if (!subject) return fail("bad_subject");
  const body = bodyOf(b);
  if (!body) return fail("bad_body");
  const brand = brandOf(b.brand);
  if (!brand) return fail("bad_brand");
  const att = parseAttachments(b.attachments);
  if (!att.ok) return fail(att.error);
  return { ok: true, value: { ...a.value, subject, body_md: body, brand, attachments: att.list, thread: b.thread !== false, signature: signatureOf(b.signature) } };
}

export type Reply = { number: number; body_md: string; brand: Brand | null; cc: string[]; bcc: string[]; attachments: Attachment[]; status: Status | null; signature: boolean };
export function parseReply(b: Record<string, unknown>): Res<Reply> {
  const number = cleanNumber(b.number);
  if (!number) return fail("bad_number");
  const body = bodyOf(b);
  if (!body) return fail("bad_body");
  const brand = brandOf(b.brand, "pasr");
  if (!brand) return fail("bad_brand");
  // het antwoord gaat naar het contact van het ticket; hier alleen cc en bcc (to wordt genegeerd)
  const a = checkAddresses({ to: [], cc: b.cc, bcc: b.bcc }, { requireRecipient: false });
  if (!a.ok) return fail(a.error);
  const att = parseAttachments(b.attachments);
  if (!att.ok) return fail(att.error);
  if (b.status !== undefined && b.status !== null && b.status !== "" && !isStatus(b.status)) return fail("bad_status");
  return { ok: true, value: {
    number, body_md: body, brand: b.brand === undefined || b.brand === null || b.brand === "" ? null : brand, cc: a.value.cc, bcc: a.value.bcc,
    attachments: att.list, status: isStatus(b.status) ? b.status : null, signature: signatureOf(b.signature),
  } };
}

export function parseThreadStatus(b: Record<string, unknown>): Res<{ number: number; status: Status | null; priority: string | null }> {
  const number = cleanNumber(b.number);
  if (!number) return fail("bad_number");
  const status = b.status === undefined || b.status === null || b.status === "" ? null : b.status;
  const priority = b.priority === undefined || b.priority === null || b.priority === "" ? null : b.priority;
  if (status !== null && !isStatus(status)) return fail("bad_status");
  if (priority !== null && !(PRIORITIES as readonly unknown[]).includes(priority)) return fail("bad_priority");
  if (status === null && priority === null) return fail("bad_request");
  return { ok: true, value: { number, status: status as Status | null, priority: priority as string | null } };
}

export function parseNote(b: Record<string, unknown>): Res<{ number: number; text: string }> {
  const number = cleanNumber(b.number);
  if (!number) return fail("bad_number");
  const text = cleanText(b.text, LIMITS.note + 1, true);
  if (!text || text.length > LIMITS.note) return fail("bad_body");
  return { ok: true, value: { number, text } };
}

export function parseTest(b: Record<string, unknown>): Res<{ to: string; subject: string; body_md: string; brand: Brand; signature: boolean }> {
  const to = typeof b.to === "string" ? b.to.trim().toLowerCase() : "";
  if (!validEmail(to)) return fail("bad_address");
  const subject = subjectOf(b);
  if (!subject) return fail("bad_subject");
  const body = bodyOf(b);
  if (!body) return fail("bad_body");
  const brand = brandOf(b.brand);
  if (!brand) return fail("bad_brand");
  return { ok: true, value: { to, subject, body_md: body, brand, signature: signatureOf(b.signature) } };
}

export function parsePreview(b: Record<string, unknown>): Res<{ subject: string; body_md: string; brand: Brand; signature: boolean }> {
  const body = typeof b.body_md === "string" ? b.body_md.replace(/\r\n?/g, "\n") : "";
  if (body.length > LIMITS.bodyMd || markdownProblem(body)) return fail("bad_body");
  const brand = brandOf(b.brand);
  if (!brand) return fail("bad_brand");
  return { ok: true, value: { subject: cleanText(b.subject, LIMITS.subject), body_md: body, brand, signature: signatureOf(b.signature) } };
}

export function parseThreadList(b: Record<string, unknown>): Res<{ status: string; q: string | null; brand: Brand | null; page: number; size: number; box: "inbox" | "sent" | "all" }> {
  const box = b.box === undefined || b.box === null || b.box === "" ? "inbox" : b.box;
  if (box !== "inbox" && box !== "sent" && box !== "all") return fail("bad_box");
  // zonder statusfilter: Inbox = actief; Verzonden en Alles = ook gesloten tickets
  const raw = b.status === undefined || b.status === null || b.status === "" ? (box === "inbox" ? "active" : "all") : b.status;
  if (raw !== "active" && raw !== "all" && !isStatus(raw)) return fail("bad_status");
  const brand = b.brand === undefined || b.brand === null || b.brand === "" ? null : isBrand(b.brand) ? b.brand : undefined;
  if (brand === undefined) return fail("bad_brand");
  const page = Math.max(1, Math.min(10000, Math.trunc(Number(b.page ?? 1)) || 1));
  const size = Math.max(1, Math.min(100, Math.trunc(Number(b.page_size ?? 30)) || 30));
  const q = cleanText(b.q, 100);
  return { ok: true, value: { status: raw as string, q: q || null, brand, page, size, box } };
}

export type CampaignReq = { audience: Audience; brand: Brand; subject: string; body_md: string; request_id: string; attachments: Attachment[]; signature: boolean };
/** Doelgroep users (standaard merk Pasr) of owners (standaard Pasr Zakelijk). list kan hier niet: losse adressen gaan via compose met BCC. */
export function parseCampaign(b: Record<string, unknown>): Res<CampaignReq> {
  if (!isAudience(b.audience) || b.audience === "list") return fail("bad_audience");
  const subject = subjectOf(b);
  if (!subject) return fail("bad_subject");
  const body = bodyOf(b);
  if (!body) return fail("bad_body");
  const brand = brandOf(b.brand, b.audience === "owners" ? "zakelijk" : "pasr");
  if (!brand) return fail("bad_brand");
  const id = typeof b.request_id === "string" ? b.request_id.trim().toLowerCase() : "";
  if (!UUID.test(id)) return fail("bad_request_id");
  const att = parseAttachments(b.attachments);
  if (!att.ok) return fail(att.error);
  return { ok: true, value: { audience: b.audience, brand, subject, body_md: body, request_id: id, attachments: att.list, signature: signatureOf(b.signature) } };
}

export function parseAudience(b: Record<string, unknown>): Res<"users" | "owners"> {
  return b.audience === "users" || b.audience === "owners" ? { ok: true, value: b.audience } : fail("bad_audience");
}
export function parseId(v: unknown): number | null { return cleanNumber(v); }
export function parseAttachmentId(b: Record<string, unknown>): string | null {
  return typeof b.id === "string" && UUID.test(b.id) ? b.id.toLowerCase() : null;
}

/** HTTP-status bij een foutcode. */
export function statusFor(error: string): number {
  if (error === "too_large") return 413;
  if (error === "rate_limited") return 429;
  if (error === "smtp_not_configured") return 503;
  if (error === "not_found") return 404;
  if (error === "forbidden") return 403;
  if (error === "unauthorized") return 401;
  if (error === "server_error" || error === "send_failed") return 500;
  return 400;
}
export { isObj };
