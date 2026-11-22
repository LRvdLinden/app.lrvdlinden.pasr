// Pushberichten aan gebruikers van Pasr en Pasr Zakelijk. De doelgroepen all/store/new/inactive zijn alleen apparaten
// met de opt-in "Nieuws over mijn kaarten" (Pasr); "everyone" is iedereen met meldingen aan (een geldig push-token,
// ook zonder opt-in; Apple 4.5.4: alleen voor belangrijke berichten, geen reclame). Pure hulpjes, getest in
// news_test.ts. Nooit tokens of apparaat-id's loggen.

/** Doelgroepen: iedereen met opt-in, heeft kaart X, nieuwe gebruikers (7 dagen), inactief (30 dagen niet geopend),
 *  en iedereen met meldingen aan (everyone). */
export const AUDIENCES = ["all", "store", "new", "inactive", "everyone"] as const;
export type Audience = typeof AUDIENCES[number];
/** Platform: alles, alleen Apple (APNs) of alleen Android (FCM). */
export const PLATFORMS = ["all", "ios", "android"] as const;
export type Platform = typeof PLATFORMS[number];
/** App: Pasr, Pasr Zakelijk of beide. Alleen bij "everyone"; de opt-in-doelgroepen bestaan alleen in Pasr. */
export const APPS = ["pasr", "zakelijk", "both"] as const;
export type App = typeof APPS[number];

export type Target = { audience: Audience; store: string | null; platform: Platform; app: App };
export type NewsInput = Target & { title: string | null; body: string; url: string | null };

/** Link onder de melding: alleen https, hoogstens 500 tekens, geen inloggegevens, een echte hostnaam. Leeg = null. */
export function cleanLink(v: unknown): { ok: true; url: string | null } | { ok: false; error: string } {
  if (v === undefined || v === null) return { ok: true, url: null };
  if (typeof v !== "string") return { ok: false, error: "bad_url" };
  const s = v.trim();
  if (!s) return { ok: true, url: null };
  if (s.length > 500 || /[\s\u0000-\u001F\u007F]/.test(s) || !/^https:\/\//i.test(s)) return { ok: false, error: "bad_url" };
  let u: URL;
  try { u = new URL(s); } catch { return { ok: false, error: "bad_url" }; }
  if (u.protocol !== "https:" || u.username || u.password || u.port && u.port !== "443") return { ok: false, error: "bad_url" };
  const host = u.hostname.toLowerCase();
  if (!/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(host)) return { ok: false, error: "bad_url" };
  const out = u.toString();
  return out.length > 500 ? { ok: false, error: "bad_url" } : { ok: true, url: out };
}

const text = (v: unknown, max: number) =>
  typeof v === "string" ? v.replace(/[\u0000-\u0009\u000B-\u001F\u007F]/g, "").replace(/[ \t]+/g, " ").trim().slice(0, max) : "";

/** Alleen de doelgroep (voor news_count): {audience, store?, platform?, app?}. Weglaten = alles / Pasr. */
export function cleanAudience(b: Record<string, unknown>): ({ ok: true } & Target) | { ok: false; error: string } {
  if (!(AUDIENCES as readonly unknown[]).includes(b.audience)) return { ok: false, error: "bad_audience" };
  const audience = b.audience as Audience;
  let store: string | null = null;
  if (audience === "store") {
    store = typeof b.store === "string" ? b.store.trim().toLowerCase() : "";
    if (!/^[a-z0-9-]{2,40}$/.test(store)) return { ok: false, error: "bad_store" };
  }
  const platform = b.platform === undefined || b.platform === null || b.platform === "" ? "all" : b.platform;
  if (!(PLATFORMS as readonly unknown[]).includes(platform)) return { ok: false, error: "bad_platform" };
  const app = b.app === undefined || b.app === null || b.app === "" ? "pasr" : b.app;
  if (!(APPS as readonly unknown[]).includes(app)) return { ok: false, error: "bad_app" };
  // de opt-in "Nieuws over mijn kaarten" bestaat alleen in Pasr
  if (audience !== "everyone" && app !== "pasr") return { ok: false, error: "bad_app" };
  return { ok: true, audience, store, platform: platform as Platform, app: app as App };
}

/** Welke apps en platforms een doelgroep raakt (voor de SQL-functie en de tellingen). */
export const wantsIos = (t: Pick<Target, "platform">) => t.platform !== "android";
export const wantsAndroid = (t: Pick<Target, "platform">) => t.platform !== "ios";

/** Bericht controleren: tekst 1 tot 240 tekens (regels mogen), titel optioneel tot 60. */
export function cleanNews(v: unknown): { ok: true; value: NewsInput } | { ok: false; error: string } {
  const b = (v && typeof v === "object" && !Array.isArray(v) ? v : {}) as Record<string, unknown>;
  const body = text(b.body, 240).replace(/\n{3,}/g, "\n\n");
  if (!body) return { ok: false, error: "bad_body" };
  const title = text(b.title, 60).replace(/\n+/g, " ") || null;
  const a = cleanAudience(b);
  if (!a.ok) return a;
  const l = cleanLink(b.url);
  if (!l.ok) return l;
  return { ok: true, value: { title, body, audience: a.audience, store: a.store, platform: a.platform, app: a.app, url: l.url } };
}

/** Standaardtitel per app (zonder eigen titel). */
export const defaultTitle = (app: "pasr" | "zakelijk") => app === "zakelijk" ? "Pasr Zakelijk" : "Pasr";

/** De melding zelf. Met store opent een tik die kaart in Pasr (als je hem hebt); met url opent een tik die link. */
export function newsPayload(n: NewsInput, id: string, app: "pasr" | "zakelijk" = "pasr") {
  return {
    aps: { alert: { title: n.title ?? defaultTitle(app), body: n.body }, sound: "default", "thread-id": "news" },
    kind: "news",
    id,
    ...(n.store ? { store: n.store } : {}),
    ...(n.url ? { url: n.url } : {}),
  };
}

/** Vingerafdruk van een bericht: hetzelfde bericht naar dezelfde doelgroep binnen een paar minuten is dubbel. */
export function newsFingerprint(n: NewsInput): string {
  return JSON.stringify([n.title ?? "", n.body, n.audience, n.store ?? "", n.platform, n.app, n.url ?? ""]);
}
export const DUPLICATE_WINDOW_MS = 10 * 60_000;

/** Eén lijst per token: hetzelfde toestel kan in meer tabellen staan (account, opt-in, apparaatregister). */
export function uniqueTokens<T extends { token: string }>(list: T[]): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const d of list) {
    const k = d.token.toLowerCase();
    if (!d.token || seen.has(k)) continue;
    seen.add(k);
    out.push(d);
  }
  return out;
}

/** In stukken versturen, zodat duizenden apparaten de functie niet laten vastlopen. */
export function chunks<T>(list: T[], size = 100): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}
