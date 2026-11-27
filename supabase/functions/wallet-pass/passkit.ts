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
  // ticket uit de catalogus (1.0.5): evenementgegevens voor een echte eventTicket-pas (zie ticketPass)
  event?: string;             // titel, bijv. "Drakenboot 2027"
  brand?: string;             // naam naast het logo, bijv. "Drakenboot"
  ticketType?: string;        // bijv. "Early Bird"
  ticketNote?: string;        // bijv. "t/m 14 jaar"
  date?: string;              // eerste dag, YYYY-MM-DD
  endDate?: string;           // laatste dag (meerdaags), YYYY-MM-DD
  doors?: string;             // HH:MM
  ends?: string;              // HH:MM
  city?: string;
  address?: string;
  infoURL?: string;           // https
  textHex?: string;           // #RRGGBB
  labelHex?: string;          // #RRGGBB
  group?: string;             // tickets voor hetzelfde evenement: dezelfde groupingIdentifier
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
  const progress = s.full ? "Vol: wissel je beloning in" : `${s.left} tot ${s.reward || "je beloning"}`;
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

// ---- ticket (eventTicket, 1.0.5) ----

const MONTHS = ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december"];
const ymd = (v?: string) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v ?? ""));
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  return mo >= 1 && mo <= 12 && d >= 1 && d <= 31 ? { y, mo, d } : null;
};
const hhmm = (v?: string) => (/^([01]\d|2[0-3]):[0-5]\d$/.test(String(v ?? "")) ? String(v) : null);
const clean = (s: unknown, n = 60) => String(s ?? "").replace(/[\u0000-\u001f<>]/g, "").replace(/\s+/g, " ").trim().slice(0, n);

/** "18 juni 2027", of bij meerdaags "15 – 18 juli 2027" / "30 juni – 2 juli 2027". */
export function dutchDates(date?: string, endDate?: string): string | null {
  const a = ymd(date);
  if (!a) return null;
  const b = ymd(endDate);
  const one = (x: { y: number; mo: number; d: number }, year = true) => `${x.d} ${MONTHS[x.mo - 1]}${year ? " " + x.y : ""}`;
  if (!b || (b.y === a.y && b.mo === a.mo && b.d === a.d)) return one(a);
  if (a.y === b.y && a.mo === b.mo) return `${a.d} – ${one(b)}`;
  if (a.y === b.y) return `${one(a, false)} – ${one(b)}`;
  return `${one(a)} – ${one(b)}`;
}

/** UTC-offset van Nederland op die dag ("+02:00" in de zomertijd, van de laatste zondag van maart tot die van oktober). */
export function amsterdamOffset(y: number, mo: number, d: number): string {
  const lastSunday = (month: number) => {
    const last = new Date(Date.UTC(y, month, 0));
    return last.getUTCDate() - last.getUTCDay();
  };
  const summer = (mo > 3 && mo < 10) || (mo === 3 && d >= lastSunday(3)) || (mo === 10 && d < lastSunday(10));
  return summer ? "+02:00" : "+01:00";
}

/** Sleutel voor groupingIdentifier: tickets voor hetzelfde evenement staan in Wallet bij elkaar. */
export function ticketGroup(card: Card): string {
  const base = clean(card.group, 80) || clean(card.event, 80) || clean(card.name, 80).split(/\s+[–-]\s+/)[0];
  const slug = base.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return "pasr-event-" + (slug || "ticket");
}

const hexOk = (v?: string) => (/^#[0-9a-fA-F]{6}$/.test(String(v ?? "")) ? String(v).toUpperCase() : null);
const rgb = (h: string) => `rgb(${parseInt(h.slice(1, 3), 16)}, ${parseInt(h.slice(3, 5), 16)}, ${parseInt(h.slice(5, 7), 16)})`;

/**
 * Een ticket als echte eventTicket-pas, zoals een concertkaartje in Apple Wallet: merkkleur van het evenement, logo,
 * titel, soort ticket, datum, toegangstijden en locatie, en de QR-code van de bezoeker. Tickets voor hetzelfde
 * evenement krijgen dezelfde groupingIdentifier. Zet `pass.eventTicket` in plaats van `pass.storeCard`.
 */
export function ticketPass(pass: Record<string, unknown>, card: Card): Record<string, unknown> {
  const out: Record<string, unknown> = { ...pass };
  const store = (pass.storeCard ?? {}) as Record<string, unknown>;
  delete out.storeCard;
  const titleFromName = clean(card.name, 60).split(/\s+[–-]\s+/);
  const title = clean(card.event, 60) || titleFromName[0] || "Ticket";
  const type = clean(card.ticketType, 30) || (titleFromName.length > 1 ? titleFromName.slice(1).join(" – ") : "");
  const brand = clean(card.brand, 30);
  const dates = dutchDates(card.date, card.endDate);
  const doors = hhmm(card.doors), ends = hhmm(card.ends);
  const venue = clean(card.venue, 60), city = clean(card.city, 40);
  const place = [venue, city].filter(Boolean).join(", ");
  const note = clean(card.ticketNote, 40);
  const info = /^https:\/\/[^\s]+$/.test(String(card.infoURL ?? "")) ? String(card.infoURL).slice(0, 300) : null;
  const route = clean(card.address, 120) || place;

  const secondary: Record<string, unknown>[] = [];
  if (dates) secondary.push({ key: "date", label: "DATUM", value: dates });
  else if (card.eventDate && !isNaN(Date.parse(card.eventDate))) {
    secondary.push({ key: "date", label: "DATUM", value: card.eventDate, dateStyle: "PKDateStyleMedium", timeStyle: "PKDateStyleShort" });
  }
  if (doors) secondary.push({ key: "doors", label: "TOEGANG", value: ends ? `${doors} – ${ends}` : `vanaf ${doors}` });
  const auxiliary: Record<string, unknown>[] = [];
  if (place) auxiliary.push({ key: "venue", label: "LOCATIE", value: place });
  if (card.seat) auxiliary.push({ key: "seat", label: "PLAATS", value: clean(card.seat, 40) });
  if (note) auxiliary.push({ key: "note", label: /\bjaar\b/i.test(note) ? "LEEFTIJD" : "LET OP", value: note });

  const back = Array.isArray(store.backFields) ? [...store.backFields as Record<string, unknown>[]] : [];
  const extraBack: Record<string, unknown>[] = [];
  if (info) extraBack.push({ key: "info", label: "Informatie", value: info, attributedValue: `<a href="${info}">${info.replace(/^https:\/\//, "")}</a>` });
  if (route) {
    const maps = "https://maps.apple.com/?daddr=" + encodeURIComponent(route);
    extraBack.push({ key: "route", label: "Route", value: route, attributedValue: `<a href="${maps}">${route}</a>` });
  }
  out.eventTicket = {
    headerFields: type ? [{ key: "type", label: "TICKET", value: type }] : [{ key: "brand", label: " ", value: "pasr" }],
    primaryFields: [{ key: "event", label: (brand || "Evenement").toUpperCase(), value: title }],
    secondaryFields: secondary,
    auxiliaryFields: auxiliary,
    backFields: [...extraBack, ...back],
  };
  out.groupingIdentifier = ticketGroup(card);
  out.description = `${title}${type ? " – " + type : ""} (Pasr)`;
  if (!card.logo) out.logoText = brand || title;

  const bg = hexOk(card.colorHex);
  const text = hexOk(card.textHex), label = hexOk(card.labelHex);
  if (bg) out.backgroundColor = rgb(bg);
  if (text) out.foregroundColor = rgb(text);
  if (label) out.labelColor = rgb(label);
  else if (text) out.labelColor = rgb(text);

  const a = ymd(card.date);
  if (a) {
    const pad = (n: number) => String(n).padStart(2, "0");
    out.relevantDate = `${a.y}-${pad(a.mo)}-${pad(a.d)}T${doors ?? "09:00"}:00${amsterdamOffset(a.y, a.mo, a.d)}`;
    // na afloop (de dag na de laatste dag) grijs in Wallet
    const last = ymd(card.endDate) ?? a;
    const after = new Date(Date.UTC(last.y, last.mo - 1, last.d + 1));
    out.expirationDate = `${after.getUTCFullYear()}-${pad(after.getUTCMonth() + 1)}-${pad(after.getUTCDate())}T06:00:00${amsterdamOffset(after.getUTCFullYear(), after.getUTCMonth() + 1, after.getUTCDate())}`;
  }
  return out;
}
