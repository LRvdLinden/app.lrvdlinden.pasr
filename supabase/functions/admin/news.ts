// Gerichte pushberichten aan gebruikers van Pasr (1.0.3): alleen apparaten met de opt-in "Nieuws over mijn kaarten"
// (tabel pasr_news_devices). Pure hulpjes, getest in news_test.ts. Nooit tokens of apparaat-id's loggen.

/** Doelgroepen: iedereen met opt-in, heeft kaart X, nieuwe gebruikers (7 dagen), inactief (30 dagen niet geopend). */
export const AUDIENCES = ["all", "store", "new", "inactive"] as const;
export type Audience = typeof AUDIENCES[number];

export type NewsInput = { title: string | null; body: string; audience: Audience; store: string | null };

const text = (v: unknown, max: number) =>
  typeof v === "string" ? v.replace(/[\u0000-\u0009\u000B-\u001F\u007F]/g, "").replace(/[ \t]+/g, " ").trim().slice(0, max) : "";

/** Alleen de doelgroep (voor news_count): {audience, store?}. */
export function cleanAudience(b: Record<string, unknown>): { ok: true; audience: Audience; store: string | null } | { ok: false; error: string } {
  if (!(AUDIENCES as readonly unknown[]).includes(b.audience)) return { ok: false, error: "bad_audience" };
  const audience = b.audience as Audience;
  let store: string | null = null;
  if (audience === "store") {
    store = typeof b.store === "string" ? b.store.trim().toLowerCase() : "";
    if (!/^[a-z0-9-]{2,40}$/.test(store)) return { ok: false, error: "bad_store" };
  }
  return { ok: true, audience, store };
}

/** Bericht controleren: tekst 1 tot 240 tekens (regels mogen), titel optioneel tot 60. */
export function cleanNews(v: unknown): { ok: true; value: NewsInput } | { ok: false; error: string } {
  const b = (v && typeof v === "object" && !Array.isArray(v) ? v : {}) as Record<string, unknown>;
  const body = text(b.body, 240).replace(/\n{3,}/g, "\n\n");
  if (!body) return { ok: false, error: "bad_body" };
  const title = text(b.title, 60).replace(/\n+/g, " ") || null;
  const a = cleanAudience(b);
  if (!a.ok) return a;
  return { ok: true, value: { title, body, audience: a.audience, store: a.store } };
}

/** De melding zelf. Met store opent een tik die kaart in Pasr (als je hem hebt). */
export function newsPayload(n: NewsInput, id: string) {
  return {
    aps: { alert: { title: n.title ?? "Pasr", body: n.body }, sound: "default", "thread-id": "news" },
    kind: "news",
    id,
    ...(n.store ? { store: n.store } : {}),
  };
}

/** In stukken versturen, zodat duizenden apparaten de functie niet laten vastlopen. */
export function chunks<T>(list: T[], size = 100): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}
