// Pasr beheer › Mail: de acties mail_* van de functie admin sturen door naar de functie mail (supabase/functions/mail). admin heeft al de
// sessiecontrole (token) en het logboek (admin_audit); mail kent alleen de kopregel x-pasr-admin met een sleutel die uit PASR_TOKEN_SECRET
// volgt (HMAC-SHA256 van "pasr-mail-admin", zie mail/auth.ts; hier dezelfde berekening). Het logboek bevat alleen aantallen en
// onderwerpen, nooit adressen of inhoud. Groot verzoek (bijlagen als base64) tot 20 MB, alleen met een geldig token.

export const MAIL_MAX_BODY = 20 * 1024 * 1024;
export const NORMAL_MAX_BODY = 700_000;

/** admin-actie -> actie van de functie mail, met de velden die doorgestuurd worden (verder niets). */
export const MAIL_ACTIONS: Record<string, { action: string; fields: string[]; audit: boolean }> = {
  mail_status: { action: "status", fields: [], audit: false },
  mail_poll: { action: "poll_inbox", fields: [], audit: true },
  mail_thread_list: { action: "thread_list", fields: ["status", "q", "brand", "page", "page_size"], audit: false },
  mail_thread_get: { action: "thread_get", fields: ["number"], audit: false },
  mail_thread_reply: { action: "thread_reply", fields: ["number", "body_md", "brand", "cc", "bcc", "attachments", "status"], audit: true },
  mail_thread_status: { action: "thread_status", fields: ["number", "status", "priority"], audit: true },
  mail_thread_note: { action: "thread_note", fields: ["number", "text"], audit: true },
  mail_compose: { action: "compose", fields: ["to", "cc", "bcc", "subject", "body_md", "brand", "attachments", "thread"], audit: true },
  mail_attachment: { action: "attachment_get", fields: ["id"], audit: false },
  mail_preview: { action: "preview", fields: ["body_md", "brand", "subject", "kind", "voornaam"], audit: false },
  mail_test: { action: "test", fields: ["body_md", "brand", "subject", "to"], audit: true },
  mail_campaign_audience: { action: "campaign_audience", fields: ["audience"], audit: false },
  mail_campaign_send: { action: "campaign_send", fields: ["audience", "brand", "subject", "body_md", "request_id", "attachments"], audit: true },
  mail_campaign_list: { action: "campaign_list", fields: [], audit: false },
  mail_campaign_cancel: { action: "campaign_cancel", fields: ["id"], audit: true },
};
export const isMailAction = (a: unknown): a is string => typeof a === "string" && Object.prototype.hasOwnProperty.call(MAIL_ACTIONS, a);

/** De body voor de functie mail: alleen de toegestane velden. */
export function forwardBody(action: string, body: Record<string, unknown>): Record<string, unknown> {
  const spec = MAIL_ACTIONS[action];
  const out: Record<string, unknown> = { action: spec.action };
  for (const f of spec.fields) if (body[f] !== undefined) out[f] = body[f];
  return out;
}

/** Dezelfde sleutel als mail/auth.ts adminKey(); leeg als PASR_TOKEN_SECRET te kort is. */
export async function mailKey(tokenSecret: string): Promise<string> {
  if (!tokenSecret || tokenSecret.length < 32) return "";
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(tokenSecret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode("pasr-mail-admin")));
  return Array.from(sig, (x) => x.toString(16).padStart(2, "0")).join("");
}

const oneLine = (s: unknown, n: number) => String(s ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, n);
const count = (v: unknown) => (Array.isArray(v) ? v.length : typeof v === "string" ? v.split(/[\s,;]+/).filter(Boolean).length : 0);
/** Regel voor admin_audit: aantallen en onderwerpen, nooit adressen of inhoud. */
export function auditDetail(action: string, body: Record<string, unknown>, result: unknown): string {
  const r = (result && typeof result === "object" ? result : {}) as Record<string, unknown>;
  switch (action) {
    case "mail_compose":
      return `to=${count(body.to)} cc=${count(body.cc)} bcc=${count(body.bcc)} att=${count(body.attachments)} sent=${Number(r.sent) || 0} failed=${Number(r.failed) || 0} "${oneLine(body.subject, 60)}"`;
    case "mail_thread_reply":
      return `#${Number(body.number) || 0} cc=${count(body.cc)} bcc=${count(body.bcc)} att=${count(body.attachments)}`;
    case "mail_thread_status": return `#${Number(body.number) || 0} ${oneLine(body.status, 10)} ${oneLine(body.priority, 10)}`.trim();
    case "mail_thread_note": return `#${Number(body.number) || 0}`;
    case "mail_test": return `"${oneLine(body.subject, 60)}"`;
    case "mail_campaign_send":
      return `${oneLine(body.audience, 10)} ${oneLine(body.brand, 10)} recipients=${Number(r.recipients) || 0} sent=${Number(r.sent) || 0} failed=${Number(r.failed) || 0} id=${Number(r.campaign_id) || 0} "${oneLine(body.subject, 60)}"`;
    case "mail_campaign_cancel": return `id=${Number(body.id) || 0}`;
    case "mail_poll": return `fetched=${Number(r.fetched) || 0} imported=${Number(r.imported) || 0}`;
    default: return "";
  }
}

/** Het verzoek lezen met een bovengrens: gewoon tot 700 kB; groter (bijlagen) tot 20 MB, maar alleen als `mayGrow()` (geldig token) ja zegt. */
export async function readBody(req: Request, mayGrow: () => Promise<boolean>): Promise<{ text: string } | { error: "too_large" }> {
  if (!req.body) return { text: "" };
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0, allowedBig = false;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > NORMAL_MAX_BODY && !allowedBig) {
      allowedBig = await mayGrow();
      if (!allowedBig) { await reader.cancel().catch(() => {}); return { error: "too_large" }; }
    }
    if (total > MAIL_MAX_BODY) { await reader.cancel().catch(() => {}); return { error: "too_large" }; }
    chunks.push(value);
  }
  const all = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) { all.set(c, o); o += c.length; }
  return { text: new TextDecoder().decode(all) };
}

export type Forwarded = { status: number; text: string };
/** POST naar de functie mail; bij een netwerkfout 502 mail_unreachable. */
export async function forwardToMail(url: string, key: string, payload: Record<string, unknown>, fetchFn: typeof fetch = fetch): Promise<Forwarded> {
  try {
    const res = await fetchFn(url, {
      method: "POST", headers: { "Content-Type": "application/json", "x-pasr-admin": key }, body: JSON.stringify(payload), signal: AbortSignal.timeout(140_000),
    });
    return { status: res.status, text: await res.text() };
  } catch {
    return { status: 502, text: JSON.stringify({ error: "mail_unreachable" }) };
  }
}
