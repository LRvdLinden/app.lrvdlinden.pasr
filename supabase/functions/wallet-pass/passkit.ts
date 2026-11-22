// Pasr → Apple Wallet: pure hulpjes van de functie wallet-pass (geen netwerk, geen database), getest in
// passkit_test.ts. Sinds 1.0.3: stempelkaarten en de PassKit-webservice (passen bijwerken).
// Nooit tokens, push-tokens of kaartnummers loggen.

const te = new TextEncoder();
const td = new TextDecoder();

/** Velden die de app stuurt (alles behalve id/name/number optioneel). */
export type Card = {
  id: string;
  name: string;
  number: string;
  format: string;             // ean13, code128, qr, pdf417, aztec, ...
  colorHex: string;
  kind?: string;              // loyalty | voucher | code | ticket | subscription | stamps
  codeAsText?: boolean;       // kortingscode: geen barcode, de code als tekst
  eventDate?: string;         // ticket (ISO)
  venue?: string;             // ticket
  seat?: string;              // ticket
  renewsAt?: string;          // abonnement (ISO)
  cost?: number;              // abonnement
  period?: string;            // week | month | quarter | year
  stampsTotal?: number;       // stempelkaart (1.0.3)
  stampsCount?: number;
  reward?: string;
  issuer?: string;            // "business": zakelijke stempelkaart, de stand komt van pasr_business_member
  memberCode?: string;
  businessCardId?: string;
  balance?: number;
  currency?: string;
  expiresAt?: string;         // ISO date
  note?: string;
  logo?: string;              // PNG, base64
  locations?: { latitude: number; longitude: number; name?: string }[];
  history?: string[];
  token?: string;             // authenticationToken van de pas (1.0.3); zonder token: een pas zonder webservice
  push?: boolean;             // na het maken de andere apparaten met deze pas inseinen
  action?: string;            // "update": alleen bewaren en inseinen, geen pas terug
};

/** Wat de app stuurt, ontdaan van wat niet in de bewaarde pas hoort. */
export function stored(card: Card): Card {
  const { token: _t, push: _p, action: _a, ...rest } = card;
  return rest as Card;
}

export const isToken = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{32,128}$/i.test(v);
export const isSerial = (v: unknown): v is string => typeof v === "string" && /^[0-9A-Fa-f-]{36}$/.test(v);

// ---- stempelkaart ----

export type Stamps = { total: number; count: number; left: number; full: boolean; dots: string; reward: string };

/** Stand binnen de grenzen: 2..30 vakjes, 0..vakjes stempels. */
export function stamps(card: Card): Stamps {
  const n = (v: unknown, d: number) => (typeof v === "number" && isFinite(v) ? Math.round(v) : d);
  const total = Math.min(30, Math.max(2, n(card.stampsTotal, 10)));
  const count = Math.min(total, Math.max(0, n(card.stampsCount, 0)));
  const reward = String(card.reward ?? "").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, 60);
  return { total, count, left: total - count, full: count >= total, dots: "●".repeat(count) + "○".repeat(total - count), reward };
}

/** Velden van een stempelkaart op de pas. */
export function stampFields(card: Card) {
  const s = stamps(card);
  const progress = s.full ? "Vol: wissel je beloning in" : `nog ${s.left} tot ${s.reward || "je beloning"}`;
  return {
    header: { key: "stamps", label: "STEMPELS", value: `${s.count}/${s.total}`, changeMessage: "Stempels nu %@" },
    // tot 12 vakjes past de rij bolletjes groot op de pas; daarboven klein bij de andere velden
    primary: s.total <= 12 ? [{ key: "dots", label: s.reward ? `BELONING: ${s.reward.toUpperCase()}` : "STEMPELKAART", value: s.dots }] : [],
    auxiliary: [
      ...(s.total > 12 ? [{ key: "dots", label: "STEMPELS", value: s.dots }] : []),
      { key: "progress", label: s.full ? "KLAAR" : "NOG", value: progress },
    ],
  };
}

// ---- PassKit-webservice ----

export type Route =
  | { kind: "register"; device: string; passType: string; serial: string }
  | { kind: "unregister"; device: string; passType: string; serial: string }
  | { kind: "serials"; device: string; passType: string }
  | { kind: "pass"; passType: string; serial: string }
  | { kind: "log" };

/** Het deel vanaf /v1/ van een verzoek van Wallet (de functie staat onder /functions/v1/wallet-pass). */
export function route(method: string, pathname: string): Route | null {
  const i = pathname.lastIndexOf("/v1/");
  if (i < 0) return null;
  const parts = pathname.slice(i + 4).split("/").filter(Boolean).map((p) => decodeURIComponent(p));
  const safe = (s: string) => /^[A-Za-z0-9._-]{1,128}$/.test(s);
  if (!parts.every(safe)) return null;
  if (parts[0] === "devices" && parts[2] === "registrations") {
    if (parts.length === 5 && method === "POST") return { kind: "register", device: parts[1], passType: parts[3], serial: parts[4] };
    if (parts.length === 5 && method === "DELETE") return { kind: "unregister", device: parts[1], passType: parts[3], serial: parts[4] };
    if (parts.length === 4 && method === "GET") return { kind: "serials", device: parts[1], passType: parts[3] };
  }
  if (parts[0] === "passes" && parts.length === 3 && method === "GET") return { kind: "pass", passType: parts[1], serial: parts[2] };
  if (parts[0] === "log" && parts.length === 1 && method === "POST") return { kind: "log" };
  return null;
}

/** "ApplePass <token>" uit de Authorization-header. */
export function applePassToken(header: string | null): string | null {
  const m = /^ApplePass\s+([0-9a-fA-F]{32,128})$/.exec((header ?? "").trim());
  return m ? m[1] : null;
}

// ---- versleuteling ----

export function hex(bytes: ArrayBuffer | Uint8Array): string {
  return Array.from(bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function b64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 8192) s += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(s);
}
function unb64(s: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

/** Hash van het token zoals hij in de database staat (nooit het token zelf). */
export async function tokenHash(token: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", te.encode("pasr-wallet-auth:" + token)));
}

async function keyFor(token: string): Promise<CryptoKey> {
  const raw = await crypto.subtle.digest("SHA-256", te.encode("pasr-wallet-v1:" + token));
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** JSON → base64(iv ‖ ciphertext), met een sleutel uit het token. */
export async function seal(value: unknown, token: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await keyFor(token), te.encode(JSON.stringify(value))));
  const out = new Uint8Array(iv.length + ct.length);
  out.set(iv);
  out.set(ct, iv.length);
  return b64(out);
}

export async function open<T>(sealed: string, token: string): Promise<T> {
  const all = unb64(sealed);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: all.subarray(0, 12) }, await keyFor(token), all.subarray(12));
  return JSON.parse(td.decode(pt)) as T;
}

/** Vergelijken zonder dat de tijd iets verraadt. */
export function sameText(a: string, b: string): boolean {
  const x = te.encode(a), y = te.encode(b);
  if (x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

/** Tag voor passesUpdatedSince: milliseconden sinds 1970 als tekst. */
export const tagFor = (iso: string) => String(Date.parse(iso) || 0);

/** Stand van pasr_business_member (snake_case of camelCase, of een rij in een lijst). */
export function businessStand(json: unknown): { total?: number; count?: number; reward?: string } | null {
  const d = (Array.isArray(json) ? json[0] : json) as Record<string, unknown> | null;
  if (!d || typeof d !== "object") return null;
  const num = (...keys: string[]) => {
    for (const k of keys) { const v = d[k]; if (typeof v === "number" && isFinite(v)) return v; if (typeof v === "string" && /^\d+$/.test(v)) return Number(v); }
    return undefined;
  };
  const reward = typeof d.reward === "string" ? d.reward : undefined;
  const out = { total: num("stamps_total", "stampsTotal", "total"), count: num("stamps_count", "stampsCount", "stamps", "count"), reward };
  return out.total === undefined && out.count === undefined && out.reward === undefined ? null : out;
}
