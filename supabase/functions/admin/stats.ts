// Invoer van de acties stats en users controleren. Pure hulpjes, getest in stats_test.ts.

export const RANGES = [7, 30, 90, 365] as const;

/** days ∈ 7|30|90|365 (standaard 30), offset = periodes terug (0…), offset × days ≤ 1100. */
export function parseRange(days: unknown, offset: unknown): { days: number; offset: number } | null {
  const d = days === undefined || days === null ? 30 : days;
  const o = offset === undefined || offset === null ? 0 : offset;
  if (typeof d !== "number" || !(RANGES as readonly number[]).includes(d)) return null;
  if (typeof o !== "number" || !Number.isInteger(o) || o < 0 || o * d > 1100) return null;
  return { days: d, offset: o };
}

export const FILTERS = ["all", "unconfirmed", "cards", "active"] as const;

export function parseUsers(b: Record<string, unknown>):
  { search: string; filter: string; limit: number; offset: number } | null {
  const search = b.search === undefined || b.search === null ? "" : b.search;
  if (typeof search !== "string" || search.length > 120) return null;
  const filter = b.filter === undefined || b.filter === null ? "all" : b.filter;
  if (typeof filter !== "string" || !(FILTERS as readonly string[]).includes(filter)) return null;
  const limit = b.limit === undefined || b.limit === null ? 50 : b.limit;
  const offset = b.offset === undefined || b.offset === null ? 0 : b.offset;
  if (typeof limit !== "number" || !Number.isInteger(limit) || limit < 1 || limit > 100) return null;
  if (typeof offset !== "number" || !Number.isInteger(offset) || offset < 0 || offset > 1_000_000) return null;
  return { search: search.trim(), filter, limit, offset };
}

export const isUuid = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
