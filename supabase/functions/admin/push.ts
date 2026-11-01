// Pushmeldingen van de app PasrBeheer: registratie van apparaten (admin_push_devices), de meldingen zelf en APNs.
// Pure hulpjes zonder netwerk of database, getest in push_test.ts. Nooit tokens, sleutels of apparaat-id's loggen.

/** Platforms van de app PasrBeheer (macos = native Mac-app). */
export const PLATFORMS = ["ios", "ipados", "macos"] as const;
export type Platform = typeof PLATFORMS[number];
/** Soorten meldingen die je per apparaat aan of uit zet. */
export const PREF_KEYS = ["signups", "confirmed", "deleted", "bots"] as const;
export type PrefKey = typeof PREF_KEYS[number];
export type Prefs = Record<PrefKey, boolean>;
export const DEFAULT_PREFS: Prefs = { signups: true, confirmed: false, deleted: true, bots: true };
/** Bundle-id van PasrBeheer = APNs-topic (function-secret PASR_APNS_TOPIC mag hem vervangen). */
export const DEFAULT_TOPIC = "nl.lrvdlinden.pasr.beheer";

export type RegisterInput = {
  device_id: string; apns_token: string; platform: Platform; sandbox: boolean; app_build: number | null; prefs: Prefs;
};

type J = Record<string, unknown>;
const obj = (v: unknown): J => (v && typeof v === "object" && !Array.isArray(v) ? v as J : {});

export function cleanDeviceId(v: unknown): string | null {
  return typeof v === "string" && /^[A-Za-z0-9_-]{8,80}$/.test(v) ? v : null;
}
export function cleanApnsToken(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const s = v.trim();
  return /^[0-9a-fA-F]{64,200}$/.test(s) && s.length % 2 === 0 ? s.toLowerCase() : null;
}
/** Precies de schakelaars als booleans; ontbrekende krijgen de standaard, onbekende sleutels = ongeldig. */
export function cleanPrefs(v: unknown): Prefs | null {
  if (v === undefined || v === null) return { ...DEFAULT_PREFS };
  if (typeof v !== "object" || Array.isArray(v)) return null;
  const o = v as J;
  if (Object.keys(o).some((k) => !(PREF_KEYS as readonly string[]).includes(k))) return null;
  const out = { ...DEFAULT_PREFS };
  for (const k of PREF_KEYS) {
    if (o[k] === undefined) continue;
    if (typeof o[k] !== "boolean") return null;
    out[k] = o[k] as boolean;
  }
  return out;
}

export function cleanRegister(body: unknown): { ok: true; value: RegisterInput } | { ok: false; error: string } {
  const b = obj(body);
  const device_id = cleanDeviceId(b.device_id);
  if (!device_id) return { ok: false, error: "bad_device_id" };
  const apns_token = cleanApnsToken(b.apns_token);
  if (!apns_token) return { ok: false, error: "bad_apns_token" };
  if (!(PLATFORMS as readonly unknown[]).includes(b.platform)) return { ok: false, error: "bad_platform" };
  if (b.sandbox !== undefined && typeof b.sandbox !== "boolean") return { ok: false, error: "bad_sandbox" };
  let app_build: number | null = null;
  if (b.app_build !== undefined && b.app_build !== null) {
    if (typeof b.app_build !== "number" || !Number.isInteger(b.app_build) || b.app_build < 0 || b.app_build > 1_000_000) {
      return { ok: false, error: "bad_app_build" };
    }
    app_build = b.app_build;
  }
  const prefs = cleanPrefs(b.prefs);
  if (!prefs) return { ok: false, error: "bad_prefs" };
  return { ok: true, value: { device_id, apns_token, platform: b.platform as Platform, sandbox: b.sandbox === true, app_build, prefs } };
}

// ---- meldingen ----

/** Seintjes van de database (pasr_admin_notify). */
export const KINDS = ["signup", "confirmed", "deleted", "bot"] as const;
export type Kind = typeof KINDS[number];
export const prefFor: Record<Kind, PrefKey> = { signup: "signups", confirmed: "confirmed", deleted: "deleted", bot: "bots" };
/** Bots: hoogstens één melding per uur (de rest staat in het overzicht). */
export const BOT_QUIET_MS = 3600_000;

const REASONS: Record<string, string> = {
  honeypot: "honeypot", too_fast: "te snel ingevuld", rate_limit: "te veel vanaf één netwerk", disposable: "wegwerpadres",
};
export const reasonText = (r: unknown) => REASONS[typeof r === "string" ? r : ""] ?? "verdacht";

export type Counts = { accounts: number; confirmed: number; bots_hour: number };

/** De melding voor een seintje: {aps, kind, url}. Nooit e-mailadressen of namen in een melding. */
export function message(kind: Kind, c: Counts, reason?: unknown) {
  const n = (x: number) => new Intl.NumberFormat("nl-NL").format(Math.max(0, Math.round(x)));
  let title: string, body: string, url = "pasrbeheer://overview";
  switch (kind) {
    case "signup":
      title = "Nieuw Pasr-account";
      body = `Er is een account aangemaakt. Nu ${n(c.accounts)} ${c.accounts === 1 ? "account" : "accounts"}.`;
      url = "pasrbeheer://accounts";
      break;
    case "confirmed":
      title = "Account bevestigd";
      body = `Een nieuw account is bevestigd. ${n(c.confirmed)} van de ${n(c.accounts)} zijn bevestigd.`;
      url = "pasrbeheer://accounts";
      break;
    case "deleted":
      title = "Account verwijderd";
      body = `Iemand heeft zijn account verwijderd. Nog ${n(c.accounts)} ${c.accounts === 1 ? "account" : "accounts"}.`;
      break;
    case "bot":
      title = "Bot tegengehouden";
      body = c.bots_hour > 1
        ? `${n(c.bots_hour)} aanmeldingen tegengehouden in het afgelopen uur (laatste: ${reasonText(reason)}).`
        : `Een aanmelding is tegengehouden (${reasonText(reason)}).`;
      break;
  }
  return { aps: { alert: { title, body }, sound: "default", "thread-id": kind }, kind, url };
}

export function testPayload() {
  return {
    aps: { alert: { title: "Testmelding", body: "Pushmeldingen van PasrBeheer werken op dit apparaat." }, sound: "default", "thread-id": "test" },
    kind: "test",
    url: "pasrbeheer://settings",
  };
}

/** Wil dit apparaat deze soort? (prefs uit de database, ontbrekend = standaard). */
export function wants(prefs: unknown, kind: Kind): boolean {
  const p = cleanPrefs(prefs) ?? DEFAULT_PREFS;
  return p[prefFor[kind]];
}

// ---- APNs ----

const te = new TextEncoder();
export function b64u(bytes: Uint8Array | ArrayBuffer): string {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
/** PEM (PKCS#8, inhoud van het .p8-bestand) naar DER; ook met letterlijke "\n" of zonder kop. */
export function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = String(pem ?? "").replace(/\\n/g, "\n").replace(/-----(BEGIN|END)[^-]+-----/g, "").replace(/\s+/g, "");
  if (!body) throw new Error("empty_key");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}
export function importApnsKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}
/** APNs provider token (JWT ES256), 60 minuten geldig bij Apple. */
export async function apnsJwt(key: CryptoKey, keyId: string, teamId: string, nowS = Math.floor(Date.now() / 1000)): Promise<string> {
  const input = `${b64u(te.encode(JSON.stringify({ alg: "ES256", kid: keyId })))}.${b64u(te.encode(JSON.stringify({ iss: teamId, iat: nowS })))}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, te.encode(input));
  return `${input}.${b64u(sig)}`;
}
export const apnsHost = (sandbox: boolean) => sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";

export function apnsResult(status: number, reason: string): { ok: true } | { ok: false; invalid: boolean; error: string } {
  if (status === 200) return { ok: true };
  const r = /^[A-Za-z]{1,40}$/.test(reason) ? reason : "";
  const invalid = status === 410 || ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic", "ExpiredToken"].includes(r);
  return { ok: false, invalid, error: `apns_${r || status}` };
}
