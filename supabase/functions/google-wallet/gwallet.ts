// Pasr → Google Wallet: pure hulpjes van de functie google-wallet (geen netwerk, geen database), getest in
// gwallet_test.ts. Nooit sleutels of kaartnummers loggen.

const te = new TextEncoder();

/** Wat de app stuurt (camelCase, zoals de kaart in de sync). Alles behalve id/name optioneel. */
export type GCard = {
  id: string;
  name: string;
  number?: string;
  format?: string;         // ean13, ean8, upcA, code128, code39, itf, qr, pdf417, aztec
  kind?: string;           // loyalty | voucher | code | ticket | subscription | stamps
  colorHex?: string;
  balance?: number;
  currency?: string;
  expiresAt?: string;      // ISO
  note?: string;
  pin?: string;
  details?: {
    eventDate?: string; venue?: string; seat?: string; renewsAt?: string; cost?: number; period?: string;
    codeAsBarcode?: boolean; stampsTotal?: number; stampsCount?: number; reward?: string; issuer?: string;
    businessCardId?: string; memberCode?: string;
  };
  logo?: string;           // PNG/JPEG base64 (optioneel)
};

export const isUuid = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const isKey = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{32,128}$/i.test(v);

/** Object-id bij Google: <issuer>.pasr_<uuid zonder streepjes>. */
export function objectId(issuer: string, cardId: string): string {
  return `${issuer}.pasr_${cardId.toLowerCase().replace(/-/g, "")}`;
}

const BARCODES: Record<string, string> = {
  ean13: "EAN_13", ean8: "EAN_8", upcA: "UPC_A", code128: "CODE_128", code39: "CODE_39", itf: "ITF_14",
  qr: "QR_CODE", pdf417: "PDF_417", aztec: "AZTEC",
};

/** Barcode-type voor Google. ITF alleen met 14 cijfers (Google kent alleen ITF-14), anders Code 128. */
export function barcodeType(format: string | undefined, value: string): string {
  const t = BARCODES[format ?? ""] ?? "CODE_128";
  if (t === "ITF_14" && !/^\d{14}$/.test(value)) return "CODE_128";
  if ((t === "EAN_13" && !/^\d{13}$/.test(value)) || (t === "EAN_8" && !/^\d{8}$/.test(value)) ||
      (t === "UPC_A" && !/^\d{12}$/.test(value))) return "CODE_128";
  return t;
}

export function cleanText(v: unknown, max = 120): string {
  return String(v ?? "").replace(/[\u0000-\u001f<>]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
}

export function cleanHex(v: unknown): string {
  const s = String(v ?? "").trim();
  const h = s.startsWith("#") ? s : "#" + s;
  return /^#[0-9A-Fa-f]{6}$/.test(h) ? h.toUpperCase() : "#6A5CFF";
}

const KIND_NL: Record<string, string> = {
  loyalty: "Klantenkaart", voucher: "Cadeaukaart", code: "Kortingscode", ticket: "Ticket",
  subscription: "Abonnement", stamps: "Stempelkaart",
};

const PERIOD_NL: Record<string, string> = { week: "per week", month: "per maand", quarter: "per kwartaal", year: "per jaar" };

function nlDate(iso?: string): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (!isFinite(t)) return null;
  return new Date(t).toLocaleDateString("nl-NL", { day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Amsterdam" });
}

function money(n: number, currency = "EUR"): string {
  try {
    return new Intl.NumberFormat("nl-NL", { style: "currency", currency }).format(n);
  } catch {
    return `€ ${n.toFixed(2)}`;
  }
}

export type Stand = { total: number; count: number; reward: string };

export function stand(card: GCard, server?: { total?: number; count?: number; reward?: string } | null): Stand {
  const d = card.details ?? {};
  const n = (v: unknown, def: number) => (typeof v === "number" && isFinite(v) ? Math.round(v) : def);
  const total = Math.min(30, Math.max(2, n(server?.total ?? d.stampsTotal, 10)));
  const count = Math.max(0, n(server?.count ?? d.stampsCount, 0));
  return { total, count, reward: cleanText(server?.reward ?? d.reward ?? "", 60) };
}

const lv = (value: string) => ({ defaultValue: { language: "nl", value } });

/** Tekstmodules (de regels op de achterkant van de pas). */
export function modules(card: GCard, s?: Stand): { id: string; header: string; body: string }[] {
  const out: { id: string; header: string; body: string }[] = [];
  const d = card.details ?? {};
  const kind = card.kind ?? "loyalty";
  if (kind === "stamps" && s) {
    const shown = Math.min(s.count, s.total);
    out.push({ id: "stamps", header: "Stempels", body: `${"●".repeat(shown)}${"○".repeat(s.total - shown)}  ${shown} van ${s.total}` });
    if (s.reward) out.push({ id: "reward", header: "Beloning", body: s.reward });
    out.push({ id: "how", header: "Zo werkt het", body: "Laat de QR-code scannen bij de kassa. Alleen de zaak zet stempels." });
  }
  if (kind === "voucher" && typeof card.balance === "number") out.push({ id: "balance", header: "Tegoed", body: money(card.balance, card.currency || "EUR") });
  if (card.pin) out.push({ id: "pin", header: "Pincode", body: cleanText(card.pin, 20) });
  const exp = nlDate(card.expiresAt);
  if (exp) out.push({ id: "expires", header: "Geldig tot", body: exp });
  if (kind === "ticket") {
    const when = nlDate(d.eventDate);
    if (when) out.push({ id: "event", header: "Datum", body: when });
    if (d.venue) out.push({ id: "venue", header: "Locatie", body: cleanText(d.venue) });
    if (d.seat) out.push({ id: "seat", header: "Plaats", body: cleanText(d.seat, 60) });
  }
  if (kind === "subscription") {
    const renew = nlDate(d.renewsAt);
    if (renew) out.push({ id: "renews", header: "Verlengt op", body: renew });
    if (typeof d.cost === "number") out.push({ id: "cost", header: "Kosten", body: `${money(d.cost)} ${PERIOD_NL[d.period ?? "month"] ?? ""}`.trim() });
  }
  if (card.note) out.push({ id: "note", header: "Notitie", body: cleanText(card.note, 500) });
  out.push({ id: "pasr", header: "Pasr", body: "Bewaard met Pasr – pasr.nl" });
  return out.slice(0, 10);
}

/** Het genericObject voor Google Wallet. */
export function genericObject(issuer: string, card: GCard, logoUri: string, server?: { total?: number; count?: number; reward?: string } | null) {
  const kind = card.kind && KIND_NL[card.kind] ? card.kind : "loyalty";
  const number = cleanText(card.number ?? "", 200);
  const d = card.details ?? {};
  const s = kind === "stamps" ? stand(card, server) : undefined;
  const header = s ? `${Math.min(s.count, s.total)} van ${s.total} stempels` : (number || KIND_NL[kind]);
  const obj: Record<string, unknown> = {
    id: objectId(issuer, card.id),
    classId: `${issuer}.pasr_generic`,
    state: "ACTIVE",
    hexBackgroundColor: cleanHex(card.colorHex),
    logo: { sourceUri: { uri: logoUri }, contentDescription: lv(cleanText(card.name, 60) || "Pasr") },
    cardTitle: lv(cleanText(card.name, 60) || "Pasr"),
    subheader: lv(KIND_NL[kind]),
    header: lv(header),
    textModulesData: modules({ ...card, kind }, s),
  };
  const asText = kind === "code" && d.codeAsBarcode !== true;
  if (number) {
    obj.barcode = asText
      ? { type: "TEXT_ONLY", value: number, alternateText: number }
      : { type: barcodeType(card.format, number), value: number, alternateText: number.length <= 40 ? number : undefined };
  }
  if (card.expiresAt && isFinite(Date.parse(card.expiresAt)) && (kind === "voucher" || kind === "code")) {
    const end = new Date(Date.parse(card.expiresAt));
    end.setUTCHours(23, 59, 59, 0);
    obj.validTimeInterval = { end: { date: end.toISOString() } };
  }
  return obj;
}

// ---- JWT (RS256) ----

export function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? te.encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

export async function signJwt(payload: Record<string, unknown>, key: CryptoKey): Promise<string> {
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const body = b64url(JSON.stringify(payload));
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, te.encode(`${head}.${body}`)));
  return `${head}.${body}.${b64url(sig)}`;
}

/** "Opslaan in Google Wallet"-JWT met alleen de verwijzing naar het (al aangemaakte) object. */
export function saveClaims(serviceEmail: string, objectIdValue: string, origins: string[] = ["https://pasr.nl"]) {
  return {
    iss: serviceEmail, aud: "google", typ: "savetowallet", iat: Math.floor(Date.now() / 1000), origins,
    payload: { genericObjects: [{ id: objectIdValue }] },
  };
}

export async function sha256hex(text: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", te.encode(text)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let x = 0;
  for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}

/** Logo uit de app: base64 PNG/JPEG van hoogstens ~200 kB, anders null. */
export function cleanLogo(v: unknown): string | null {
  if (typeof v !== "string" || !v) return null;
  const raw = (v.includes(",") ? v.split(",").pop()! : v).replace(/\s+/g, "");
  if (raw.length > 280_000 || !/^[A-Za-z0-9+/]+=*$/.test(raw)) return null;
  return raw;
}

/** Soort afbeelding uit de eerste bytes. */
export function imageType(bytes: Uint8Array): string | null {
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return "image/png";
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return "image/jpeg";
  return null;
}

// ---- tickets en klantenkaart met barcode uit de database (27-11-2026, docs/tickets-klantenkaart.md) ----
// Een eventTicketClass per event (pasr_event_<event>) met eventTicketObjects per ticket, en een loyaltyClass per
// klantenkaart (pasr_mcard_<kaart>) met een loyaltyObject per lid. Gegevens uit pasr_tk_pass_data; nooit geboortedatum.

type Row = Record<string, unknown>;
const nodash = (id: unknown) => String(id ?? "").toLowerCase().replace(/-/g, "");
const iso = (v: unknown) => (typeof v === "string" && isFinite(Date.parse(v)) ? new Date(Date.parse(v)).toISOString() : undefined);
const pctText = (v: unknown) => {
  const n = Number(v);
  return isFinite(n) && n > 0 ? `${n.toLocaleString("nl-NL", { maximumFractionDigits: 2 })}%` : "";
};

export const eventClassId = (issuer: string, eventId: unknown) => `${issuer}.pasr_event_${nodash(eventId)}`;
export const loyaltyClassId = (issuer: string, cardId: unknown) => `${issuer}.pasr_mcard_${nodash(cardId)}`;

export function eventTicketClass(issuer: string, d: Row, logoUri: string) {
  const address = cleanText(d.address, 200);
  return {
    id: eventClassId(issuer, d.event_id),
    issuerName: cleanText(d.business_name, 60) || "Pasr",
    reviewStatus: "UNDER_REVIEW",
    eventName: lv(cleanText(d.event_name, 80) || "Event"),
    eventId: String(d.event_id ?? ""),
    hexBackgroundColor: cleanHex(d.color),
    logo: { sourceUri: { uri: logoUri }, contentDescription: lv(cleanText(d.business_name, 60) || "Pasr") },
    dateTime: { start: iso(d.starts_at), end: iso(d.ends_at), doorsOpen: iso(d.doors_at) },
    ...(address ? { venue: { name: lv(address), address: lv(address) } } : {}),
  };
}

export function eventTicketObject(issuer: string, d: Row) {
  const code = cleanText(d.code, 60);
  const inactive = d.status === "cancelled" || d.event_status === "cancelled";
  return {
    id: objectId(issuer, String(d.ticket_id)),
    classId: eventClassId(issuer, d.event_id),
    state: inactive ? "INACTIVE" : "ACTIVE",
    hexBackgroundColor: cleanHex(d.color),
    barcode: { type: "QR_CODE", value: code, alternateText: code },
    ...(cleanText(d.holder_name, 60) ? { ticketHolderName: cleanText(d.holder_name, 60) } : {}),
    ticketType: lv(cleanText(d.ticket_type, 40) || "Toegang"),
    groupingInfo: { groupingId: String(d.event_id ?? ""), sortIndex: Number(d.index) || 1 },
    ...(iso(d.ends_at) ? { validTimeInterval: { end: { date: new Date(Date.parse(String(d.ends_at)) + 6 * 3600_000).toISOString() } } } : {}),
  };
}

export function loyaltyClass(issuer: string, d: Row, logoUri: string) {
  return {
    id: loyaltyClassId(issuer, d.card_id),
    issuerName: cleanText(d.business_name, 60) || "Pasr",
    programName: cleanText(d.name, 40) || "Klantenkaart",
    programLogo: { sourceUri: { uri: logoUri }, contentDescription: lv(cleanText(d.business_name, 60) || "Pasr") },
    hexBackgroundColor: cleanHex(d.color),
    reviewStatus: "UNDER_REVIEW",
  };
}

export function loyaltyObject(issuer: string, d: Row) {
  const number = cleanText(d.number, 40);
  const fmt = d.barcode_type === "qr" ? "qr" : d.barcode_type === "ean13" ? "ean13" : "code128";
  const now = (d.discount_now ?? null) as Row | null, next = (d.next_discount ?? null) as Row | null;
  const saving = (d.saving ?? null) as Row | null;
  const modulesOut: { id: string; header: string; body: string }[] = [];
  if (now && pctText(now.percent)) modulesOut.push({ id: "now", header: "Korting nu", body: `${pctText(now.percent)} · ${cleanText(now.label, 40)}` });
  if (next && pctText(next.percent)) {
    modulesOut.push({ id: "next", header: "Volgende korting", body: `${pctText(next.percent)} vanaf ${nlDate(String(next.starts_at ?? "")) ?? ""}`.trim() });
  }
  if (saving && saving.reward) modulesOut.push({ id: "reward", header: "Beloning", body: `${cleanText(saving.reward, 80)} bij ${saving.target}` });
  modulesOut.push({ id: "pasr", header: "Pasr", body: "Laat deze kaart scannen bij de kassa. Bewaard met Pasr – pasr.nl" });
  return {
    id: objectId(issuer, String(d.member_id)),
    classId: loyaltyClassId(issuer, d.card_id),
    state: d.active === false ? "INACTIVE" : "ACTIVE",
    accountId: number,
    ...(cleanText(d.member_name, 60) ? { accountName: cleanText(d.member_name, 60) } : {}),
    barcode: { type: barcodeType(fmt, number), value: number, alternateText: number },
    ...(saving && typeof saving.target === "number"
      ? { loyaltyPoints: { label: saving.unit === "points" ? "Punten" : "Spaarstand", balance: { string: `${Number(saving.count) || 0}/${saving.target}` } } }
      : {}),
    ...(now && pctText(now.percent) ? { secondaryLoyaltyPoints: { label: "Korting", balance: { string: pctText(now.percent) } } } : {}),
    textModulesData: modulesOut.slice(0, 10),
  };
}

/** "Opslaan in Google Wallet"-JWT voor een eventTicket- of loyalty-object. */
export function saveClaimsFor(serviceEmail: string, type: "eventTicketObjects" | "loyaltyObjects" | "genericObjects", id: string,
  origins: string[] = ["https://pasr.nl"]) {
  return { iss: serviceEmail, aud: "google", typ: "savetowallet", iat: Math.floor(Date.now() / 1000), origins, payload: { [type]: [{ id }] } };
}

/** Sleutel in pasr_gwallet_objects.member_code: "ET:<ticket>" of "MC:<lid>". */
export const serverCode = (kind: string, id: string) => `${kind === "event_ticket" ? "ET" : "MC"}:${id.toLowerCase()}`;
