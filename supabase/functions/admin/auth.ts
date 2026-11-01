// Functie admin: tokens, inlogcontrole en blokkade. Pure hulpjes zonder netwerk of database, getest in auth_test.ts.
//
// Token = base64url(JSON {v, e, s:"admin"}) "." base64url(HMAC-SHA256(PASR_TOKEN_SECRET, payload))   (docs/CONTRACT.md)
//   v = tokenversie (admin_token_state.v; "overal uitloggen" verhoogt hem), e = verloop in unix-seconden (12 uur).
// Het token bevat geen inlognaam of andere gegevens. Vergelijken gebeurt altijd constant-time.

export const TOKEN_TTL_S = 12 * 3600;
export const MAX_TOKEN = 400;
export const SCOPE = "admin";
/** Blokkade: na 5 mislukte pogingen per IP binnen 15 minuten, 15 minuten dicht. */
export const LOCK_MAX = 5;
export const LOCK_WINDOW_S = 15 * 60;
/** Noodrem: meer dan 60 mislukte pogingen per uur van alle IP's samen = 15 minuten alles dicht. */
export const GLOBAL_MAX = 60;

const enc = new TextEncoder();
export const b64u = (b: Uint8Array) => {
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
export const unb64u = (s: string) =>
  Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));

export function sameBytes(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}
export async function hmac(key: string, data: string): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(data)));
}

/** Maakt een beheer-token. `now` in milliseconden. Geeft token en verloop (unix-seconden). */
export async function signToken(secret: string, v: number, now = Date.now(), ttlS = TOKEN_TTL_S) {
  if (!secret) throw new Error("token_secret_missing");
  const e = Math.floor(now / 1000) + ttlS;
  const payload = b64u(enc.encode(JSON.stringify({ v, e, s: SCOPE })));
  return { token: `${payload}.${b64u(await hmac(secret, payload))}`, e };
}

/** Controleert handtekening, scope en verloop (geen database). Geeft {v, e} of null; v vergelijkt de aanroeper. */
export async function readToken(secret: string, token: unknown, now = Date.now()): Promise<{ v: number; e: number } | null> {
  if (!secret || typeof token !== "string" || token.length > MAX_TOKEN) return null;
  const m = /^([A-Za-z0-9_-]{8,300})\.([A-Za-z0-9_-]{43})$/.exec(token);
  if (!m) return null;
  let p: Record<string, unknown>;
  try {
    if (!sameBytes(unb64u(m[2]), await hmac(secret, m[1]))) return null;
    p = JSON.parse(new TextDecoder().decode(unb64u(m[1])));
  } catch { return null; }
  if (!p || typeof p !== "object" || Array.isArray(p)) return null;
  if (p.s !== SCOPE || !Number.isInteger(p.v) || !Number.isInteger(p.e)) return null;
  if ((p.e as number) <= Math.floor(now / 1000)) return null;
  return { v: p.v as number, e: p.e as number };
}

/** Token uit de kopregel Authorization: Bearer <token>. */
export function bearer(h: Headers): string | null {
  const m = /^Bearer\s+(\S+)$/i.exec((h.get("authorization") ?? "").trim());
  return m ? m[1] : null;
}

/**
 * Constant-time vergelijken van twee teksten (gebruikersnaam/wachtwoord): beide eerst door HMAC met de geheime sleutel,
 * zodat lengte en inhoud niets verraden. Lege verwachte waarde is nooit goed.
 */
export async function sameSecret(given: unknown, expected: string, key: string): Promise<boolean> {
  if (typeof given !== "string" || !expected || given.length > 1000) return false;
  const [a, b] = await Promise.all([hmac(key, `cmp|${given}`), hmac(key, `cmp|${expected}`)]);
  return sameBytes(a, b);
}

/** Gehasht IP voor het logboek en de blokkade (nooit het IP zelf opslaan). */
export async function hashIp(ip: string, key: string): Promise<string> {
  const h = await hmac(key || "pasr", `ip|${ip}`);
  return Array.from(h.subarray(0, 12), (x) => x.toString(16).padStart(2, "0")).join("");
}

/**
 * Blokkade: `failures` = tijdstippen (ms) van mislukte pogingen van dit IP (volgorde maakt niet uit). Geeft het aantal
 * seconden tot er weer mag worden ingelogd, of 0. Tijdens de blokkade wordt niet meer geprobeerd (en dus niet geteld).
 */
export function lockRetryAfter(failures: number[], now = Date.now(), max = LOCK_MAX, windowS = LOCK_WINDOW_S): number {
  const recent = failures.filter((t) => Number.isFinite(t) && t > now - windowS * 1000 && t <= now + 5000).sort((a, b) => b - a);
  if (recent.length < max) return 0;
  // de oudste van de laatste `max` pogingen bepaalt wanneer het venster weer onder de grens zakt
  const until = recent[max - 1] + windowS * 1000;
  return Math.max(1, Math.ceil((until - now) / 1000));
}

/** Mislukte pogingen in het geheugen (aanvulling op admin_audit, ook als de database even niet werkt). */
export class FailureLog {
  private m = new Map<string, number[]>();
  add(key: string, now = Date.now()) {
    const a = (this.m.get(key) ?? []).filter((t) => t > now - LOCK_WINDOW_S * 1000);
    a.push(now);
    this.m.set(key, a.slice(-LOCK_MAX * 2));
    if (this.m.size > 10000) this.m.clear();
  }
  get(key: string): number[] { return this.m.get(key) ?? []; }
  clear(key: string) { this.m.delete(key); }
}
