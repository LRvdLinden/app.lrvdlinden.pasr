// Pasr beheer › Mail: pure hulpfuncties (geen database, geen netwerk), getest in mail_test.ts.
// Het contract staat in docs/beheer-mail.md.

export type Lang = "nl" | "en";
export const STATUSES = ["new", "open", "pending", "closed"] as const;
export type Status = typeof STATUSES[number];
export const PRIORITIES = ["low", "normal", "high", "urgent"] as const;
export const BRANDS = ["pasr", "zakelijk"] as const;
export type Brand = typeof BRANDS[number];
export const AUDIENCES = ["users", "owners", "list"] as const;
export type Audience = typeof AUDIENCES[number];

export const LIMITS = {
  name: 80, email: 254, subject: 150, minSubject: 1, message: 20000, bodyMd: 50000, note: 5000,
  /** BCC-adressen per mail en adressen (aan + cc + bcc) per aanroep */
  bccPerMail: 50, perCall: 200, cc: 20, to: 20,
  /** bijlagen: per mail in totaal (uitgaand en inkomend), per bijlage, en het aantal */
  attachmentsTotal: 20 * 1024 * 1024, attachmentName: 120, attachmentCount: 10,
  /** aanvragen per uur: losse mails (compose/reply/test) per beheer-instantie */
  composePerHour: 60,
};

export const isStatus = (v: unknown): v is Status => typeof v === "string" && (STATUSES as readonly string[]).includes(v);
export const isBrand = (v: unknown): v is Brand => typeof v === "string" && (BRANDS as readonly string[]).includes(v);
export const isAudience = (v: unknown): v is Audience => typeof v === "string" && (AUDIENCES as readonly string[]).includes(v);

/** Tekst opschonen: geen stuurtekens (wel regeleinden en tabs), CRLF naar LF, onzichtbare richtingtekens weg. */
export function cleanText(v: unknown, max: number, multiline = false): string {
  let s = String(v ?? "").replace(/\r\n?/g, "\n").replace(/[​-‏‪-‮⁦-⁩﻿]/g, "");
  s = multiline ? s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "") : s.replace(/[\u0000-\u001f\u007f]+/g, " ");
  s = s.trim();
  if (multiline) s = s.replace(/[ \t]+\n/g, "\n").replace(/\n{4,}/g, "\n\n\n");
  else s = s.replace(/\s{2,}/g, " ");
  return s.slice(0, max);
}

export const EMAIL_RE = /^[^\s@<>()",;:\\[\]]{1,64}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
export const validEmail = (e: string) => e.length <= LIMITS.email && EMAIL_RE.test(e) && !/\.\./.test(e);

/** Adreslijst uit een veld: komma, puntkomma, spatie of regeleinde als scheiding ("Naam <a@b.nl>" mag ook), kleine letters,
 *  zonder dubbelen. `bad` telt wat geen geldig adres is (de adressen zelf komen nooit in een foutmelding of log). */
export function parseAddressList(v: unknown): { list: string[]; bad: number } {
  const items = Array.isArray(v) ? v.map(String) : typeof v === "string" ? v.split(/[\s,;]+/) : [];
  const list: string[] = [];
  let bad = 0;
  for (const raw of items) {
    const t = raw.trim().replace(/^<|>$/g, "").replace(/^mailto:/i, "");
    if (!t) continue;
    const a = t.toLowerCase();
    if (!validEmail(a)) { bad++; continue; }
    if (!list.includes(a)) list.push(a);
  }
  return { list, bad };
}

export type ComposeAddresses = { to: string[]; cc: string[]; bcc: string[] };
export type AddressCheck = { ok: true; value: ComposeAddresses } | { ok: false; error: "bad_address" | "too_many" | "no_recipient" };
/** Aan, CC en BCC samen: ongeldig = bad_address, te veel = too_many (max. 200 in totaal, max. 20 aan en 20 cc), minstens één. Een adres
 *  dat al in Aan staat, valt weg uit CC en BCC (en CC voor BCC), zodat niemand dubbel een mail krijgt. */
export function checkAddresses(b: Record<string, unknown>, opts: { requireRecipient?: boolean } = {}): AddressCheck {
  const to = parseAddressList(b.to), cc = parseAddressList(b.cc), bcc = parseAddressList(b.bcc);
  if (to.bad || cc.bad || bcc.bad) return { ok: false, error: "bad_address" };
  if (to.list.length > LIMITS.to || cc.list.length > LIMITS.cc) return { ok: false, error: "too_many" };
  const ccL = cc.list.filter((a) => !to.list.includes(a));
  const bccL = bcc.list.filter((a) => !to.list.includes(a) && !ccL.includes(a));
  if (to.list.length + ccL.length + bccL.length > LIMITS.perCall) return { ok: false, error: "too_many" };
  if (opts.requireRecipient !== false && to.list.length + ccL.length + bccL.length === 0) return { ok: false, error: "no_recipient" };
  return { ok: true, value: { to: to.list, cc: ccL, bcc: bccL } };
}
/** BCC in groepen van hoogstens 50 (één mail per groep). */
export function chunk<T>(list: T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < list.length; i += n) out.push(list.slice(i, i + n));
  return out;
}

export type Attachment = { name: string; type: string; data: Uint8Array };
const MIME_RE = /^[a-z0-9][a-z0-9.+-]{0,60}\/[a-z0-9][a-z0-9.+-]{0,100}$/i;
/** Bestandsnaam: geen paden of stuurtekens, max. 120 tekens, nooit leeg. */
export function cleanFileName(v: unknown): string {
  const n = cleanText(v, 300).replace(/[\\/:*?"<>|]+/g, "_").replace(/^\.+/, "").slice(-LIMITS.attachmentName);
  return n || "bijlage";
}
/** Bijlagen uit het verzoek ({name, type, data_b64}): max. 10 bestanden, samen 20 MB (ruwe bytes) per mail; geeft bytes of een foutcode. */
export function parseAttachments(v: unknown): { ok: true; list: Attachment[] } | { ok: false; error: "bad_attachment" | "too_large" } {
  if (v === undefined || v === null) return { ok: true, list: [] };
  if (!Array.isArray(v)) return { ok: false, error: "bad_attachment" };
  if (v.length > LIMITS.attachmentCount) return { ok: false, error: "too_large" };
  const list: Attachment[] = [];
  let total = 0;
  for (const a of v) {
    if (!a || typeof a !== "object") return { ok: false, error: "bad_attachment" };
    const o = a as Record<string, unknown>;
    let b64 = typeof o.data_b64 === "string" ? o.data_b64 : "";
    if (/[\s]/.test(b64.slice(0, 200)) || b64.includes("\n") || b64.includes(" ")) b64 = b64.replace(/\s+/g, "");
    if (!b64 || b64.length > Math.ceil(LIMITS.attachmentsTotal * 4 / 3) + 8 || b64.length % 4 === 1) {
      return { ok: false, error: b64.length > Math.ceil(LIMITS.attachmentsTotal * 4 / 3) + 8 ? "too_large" : "bad_attachment" };
    }
    let data: Uint8Array;
    try { data = fromBase64(b64, true); } catch { return { ok: false, error: "bad_attachment" }; }
    total += data.length;
    if (total > LIMITS.attachmentsTotal) return { ok: false, error: "too_large" };
    const type = typeof o.type === "string" && MIME_RE.test(o.type.trim()) ? o.type.trim().toLowerCase() : "application/octet-stream";
    list.push({ name: cleanFileName(o.name), type, data });
  }
  return { ok: true, list };
}
/** Velden bij de foutcode too_large: het echte maximum (ruwe bytes aan bijlagen per mail) en een leesbare melding. */
export function tooLarge(): { max_bytes: number; max_mb: number; message: string } {
  const mb = LIMITS.attachmentsTotal / 1024 / 1024;
  return { max_bytes: LIMITS.attachmentsTotal, max_mb: mb, message: `De bijlagen zijn samen groter dan ${mb} MB (maximaal ${mb} MB per mail). Gebruik een downloadlink voor grotere bestanden.` };
}
/** Base64 in blokken (zonder een enorme tussenstring; nodig voor bijlagen tot 20 MB binnen het geheugen van een edge function). */
export function toBase64(b: Uint8Array): string {
  const parts: string[] = [];
  const step = 3 * 16384;   // veelvoud van 3: elk blok is zelf geldige base64 zonder opvulling
  for (let i = 0; i < b.length; i += step) parts.push(btoa(String.fromCharCode.apply(null, b.subarray(i, i + step) as unknown as number[])));
  return parts.join("");
}
/** Base64 naar bytes in blokken van 64 kB; gooit bij een ongeldig teken (atob controleert het alfabet). */
export function fromBase64(s: string, strict = false): Uint8Array {
  const clean = !strict && /[^A-Za-z0-9+/=]/.test(s.length > 4096 ? s.slice(0, 4096) : s) ? s.replace(/[^A-Za-z0-9+/=]/g, "") : s;
  const padded = clean.length % 4 ? clean + "=".repeat(4 - (clean.length % 4)) : clean;
  const end = padded.endsWith("==") ? 2 : padded.endsWith("=") ? 1 : 0;
  const out = new Uint8Array(padded.length / 4 * 3 - end);
  const step = 4 * 16384;
  let o = 0;
  for (let i = 0; i < padded.length; i += step) {
    const bin = atob(padded.slice(i, i + step));
    for (let k = 0; k < bin.length; k++) out[o++] = bin.charCodeAt(k);
  }
  return out;
}

/** Onderwerp voor een uitgaande mail: één regel, max. 150; bij een antwoord met [#1001]. */
export function subjectFor(subject: string, number?: number): string {
  const s = cleanText(subject, LIMITS.subject);
  if (!number) return s;
  const tag = `[#${number}]`;
  return s.includes(tag) ? s : `${tag} ${s}`.slice(0, LIMITS.subject + 10);
}

/** Message-ID van een uitgaande mail: <pasr-ticket-1001.<willekeurig>@pasr.nl> (met willekeurig deel = niet te raden). */
export function newMessageId(number: number | null, rand: string): string {
  return number ? `<pasr-ticket-${number}.${rand}@pasr.nl>` : `<pasr-mail-${rand}@pasr.nl>`;
}
export function randomId(bytes = 12): string {
  const b = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
}

/** Afzender met weergavenaam: een kaal adres wordt "Naam <adres>". */
export function withName(from: string, name: string): string {
  const f = from.trim();
  return !f || f.includes("<") ? f : `${name} <${f}>`;
}
export const addressOf = (from: string) => (/<([^<>]+)>/.exec(from)?.[1] ?? from).trim().toLowerCase();

export const BRAND_FROM: Record<Brand, { env: string; fallback: string; name: string }> = {
  pasr: { env: "PASR_MAIL_FROM_PASR", fallback: "Pasr <support@pasr.nl>", name: "Pasr" },
  zakelijk: { env: "PASR_MAIL_FROM_ZAKELIJK", fallback: "Pasr Zakelijk <zakelijk@pasr.nl>", name: "Pasr Zakelijk" },
};
export function fromFor(brand: Brand, get: (k: string) => string): string {
  const b = BRAND_FROM[brand];
  return withName(get(b.env).trim() || b.fallback, b.name);
}

/** Nieuwe status na een bericht: antwoord van ons = wacht op contact; reactie van contact = open (gesloten blijft via follow-up). */
export function statusAfter(current: Status, who: "contact" | "support"): Status {
  if (who === "support") return current === "closed" ? "closed" : "pending";
  return "open";
}

/** Ticketregel voor de lijst: voorbeeld van het laatste bericht (max. 140 tekens). */
export const preview = (text: string) => cleanText(text, 600).replace(/\s+/g, " ").slice(0, 140);

/** Foutcode voor logs: nooit het adres of de servertekst. */
export function mailErrorCode(e: unknown): string {
  const c = Number((e as { responseCode?: number })?.responseCode ?? 0);
  if (c >= 200 && c < 600) return `smtp_${c}`;
  const code = String((e as { code?: string })?.code ?? "");
  return /^[A-Z]{2,20}$/.test(code) ? code.toLowerCase() : "error";
}
