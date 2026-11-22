// Pasr voor ondernemers (1.0.3, zakelijk 1.0): goedkeuren, blokkeren, medewerkers, log en instellingen vanuit het beheer.
// Pure hulpjes, getest in news_test.ts en business_test.ts.
import { isUuid } from "./stats.ts";

export const BUSINESS_STATUSES = ["pending", "approved", "blocked"] as const;
export type BusinessStatus = typeof BUSINESS_STATUSES[number];

export function cleanBusinessStatus(b: Record<string, unknown>): { ok: true; id: string; status: BusinessStatus } | { ok: false; error: string } {
  if (!isUuid(b.id)) return { ok: false, error: "bad_id" };
  if (!(BUSINESS_STATUSES as readonly unknown[]).includes(b.status)) return { ok: false, error: "bad_status" };
  return { ok: true, id: b.id as string, status: b.status as BusinessStatus };
}

const int = (v: unknown): number | null => {
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v;
  return typeof n === "number" && Number.isInteger(n) ? n : null;
};

/** Detail van een zaak: {id, limit? (1–1000, 200), days? (1–366, 30)}. */
export function cleanBusinessDetail(b: Record<string, unknown>): { ok: true; id: string; limit: number; days: number } | { ok: false; error: string } {
  if (!isUuid(b.id)) return { ok: false, error: "bad_id" };
  const limit = b.limit === undefined ? 200 : int(b.limit), days = b.days === undefined ? 30 : int(b.days);
  if (limit === null || limit < 1 || limit > 1000) return { ok: false, error: "bad_limit" };
  if (days === null || days < 1 || days > 366) return { ok: false, error: "bad_days" };
  return { ok: true, id: b.id as string, limit, days };
}

export type BusinessSettings = {
  cooldown_minutes?: number; max_per_scan?: number; listed?: boolean; address?: string | null; lat?: number | null; lng?: number | null;
};

/** Instellingen van een zaak: afkoeltijd 0–1440 minuten, max per scan 1–30, vindbaar in Pasr, adres en locatie
 *  (lat/lng samen, null = wissen). Minstens één veld. */
export function cleanBusinessSettings(b: Record<string, unknown>):
  { ok: true; id: string; settings: BusinessSettings } | { ok: false; error: string } {
  if (!isUuid(b.id)) return { ok: false, error: "bad_id" };
  const settings: BusinessSettings = {};
  if (b.cooldown_minutes !== undefined && b.cooldown_minutes !== null) {
    const v = int(b.cooldown_minutes);
    if (v === null || v < 0 || v > 1440) return { ok: false, error: "bad_cooldown" };
    settings.cooldown_minutes = v;
  }
  if (b.max_per_scan !== undefined && b.max_per_scan !== null) {
    const v = int(b.max_per_scan);
    if (v === null || v < 1 || v > 30) return { ok: false, error: "bad_max_per_scan" };
    settings.max_per_scan = v;
  }
  if (b.listed !== undefined && b.listed !== null) {
    if (typeof b.listed !== "boolean") return { ok: false, error: "bad_listed" };
    settings.listed = b.listed;
  }
  if (b.address !== undefined) {
    if (b.address !== null && (typeof b.address !== "string" || b.address.length > 200)) return { ok: false, error: "bad_address" };
    settings.address = b.address === null ? null : (b.address as string).replace(/\s+/g, " ").trim() || null;
  }
  if (b.lat !== undefined || b.lng !== undefined) {
    const la = b.lat, lo = b.lng;
    const none = (la === null || la === undefined) && (lo === null || lo === undefined);
    const ok = typeof la === "number" && typeof lo === "number" && Math.abs(la) <= 90 && Math.abs(lo) <= 180;
    if (!none && !ok) return { ok: false, error: "bad_location" };
    settings.lat = none ? null : la as number;
    settings.lng = none ? null : lo as number;
  }
  if (!Object.keys(settings).length) return { ok: false, error: "bad_settings" };
  return { ok: true, id: b.id as string, settings };
}

// ---- zakelijk 1.1: het beheer maakt zelf zaken en stempelkaarten ----

const str = (v: unknown) => (typeof v === "string" ? v.replace(/\s+/g, " ").trim() : null);
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const HEX = /^#[0-9A-Fa-f]{6}$/;
const B64 = /^(\/9j\/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$/;

export type BusinessInput = {
  id?: string; name?: string; city?: string; address?: string | null; website?: string | null; email?: string; note?: string | null;
  listed?: boolean; cooldown_minutes?: number; max_per_scan?: number;
};

/** Zaak aanmaken (create = true: naam verplicht) of bewerken (id verplicht; weglaten = laten staan). */
export function cleanBusinessInput(body: Record<string, unknown>, create: boolean):
  { ok: true; value: BusinessInput } | { ok: false; error: string } {
  const b = body.business;
  if (!b || typeof b !== "object" || Array.isArray(b)) return { ok: false, error: "bad_business" };
  const x = b as Record<string, unknown>, v: BusinessInput = {};
  if (!create) {
    if (!isUuid(body.id)) return { ok: false, error: "bad_id" };
    v.id = body.id as string;
  }
  if (create || x.name !== undefined) {
    const n = str(x.name);
    if (!n || n.length < 2 || n.length > 60) return { ok: false, error: "bad_name" };
    v.name = n;
  }
  if (x.city !== undefined && x.city !== null) {
    const c = str(x.city);
    if (c === null || c.length > 60) return { ok: false, error: "bad_city" };
    v.city = c;
  }
  if (x.address !== undefined) {
    const a = x.address === null ? "" : str(x.address);
    if (a === null || a.length > 200) return { ok: false, error: "bad_address" };
    v.address = a || null;
  }
  if (x.website !== undefined) {
    const w = x.website === null ? "" : str(x.website);
    if (w === null || w.length > 200) return { ok: false, error: "bad_url" };
    if (w) {
      let u: URL;
      try { u = new URL(/^https?:\/\//i.test(w) ? w : "https://" + w); } catch { return { ok: false, error: "bad_url" }; }
      if (!/^https?:$/.test(u.protocol) || !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname) || u.username || u.password) return { ok: false, error: "bad_url" };
      v.website = u.href.replace(/\/$/, "");
    } else v.website = null;
  }
  if (x.email !== undefined && x.email !== null) {
    const e = str(x.email)?.toLowerCase() ?? null;
    if (e === null || e.length > 200 || (e && !EMAIL.test(e))) return { ok: false, error: "bad_email" };
    v.email = e;
  }
  if (x.note !== undefined) {
    const n = x.note === null ? "" : typeof x.note === "string" ? x.note.trim() : null;
    if (n === null || n.length > 300) return { ok: false, error: "bad_note" };
    v.note = n || null;
  }
  if (x.listed !== undefined && x.listed !== null) {
    if (typeof x.listed !== "boolean") return { ok: false, error: "bad_listed" };
    v.listed = x.listed;
  }
  if (x.cooldown_minutes !== undefined && x.cooldown_minutes !== null) {
    const c = int(x.cooldown_minutes);
    if (c === null || c < 0 || c > 1440) return { ok: false, error: "bad_cooldown" };
    v.cooldown_minutes = c;
  }
  if (x.max_per_scan !== undefined && x.max_per_scan !== null) {
    const m = int(x.max_per_scan);
    if (m === null || m < 1 || m > 30) return { ok: false, error: "bad_max_per_scan" };
    v.max_per_scan = m;
  }
  if (!create && Object.keys(v).length === 1) return { ok: false, error: "bad_business" };
  return { ok: true, value: v };
}

export type CardInput = {
  id?: string; name: string; reward: string; stamps_total: number; color: string; text_color?: string | null;
  logo?: string | null; published?: boolean;
};

/** Stempelkaart van het beheer: naam 1–40, beloning 1–80, 2–30 stempels, kleur #RRGGBB, tekstkleur (#RRGGBB, leeg =
 *  automatisch, weglaten = laten staan), logo (base64 PNG/JPEG tot ~150 kB, null = weg, weglaten = laten staan). */
export function cleanCardInput(body: Record<string, unknown>):
  { ok: true; business: string; card: CardInput } | { ok: false; error: string } {
  if (!isUuid(body.business_id)) return { ok: false, error: "bad_id" };
  const c = body.card;
  if (!c || typeof c !== "object" || Array.isArray(c)) return { ok: false, error: "bad_card" };
  const x = c as Record<string, unknown>;
  if (x.id !== undefined && x.id !== null && x.id !== "" && !isUuid(x.id)) return { ok: false, error: "bad_id" };
  const name = str(x.name), reward = str(x.reward), total = int(x.stamps_total ?? 10);
  if (!name || name.length > 40) return { ok: false, error: "bad_name" };
  if (!reward || reward.length > 80) return { ok: false, error: "bad_reward" };
  if (total === null || total < 2 || total > 30) return { ok: false, error: "bad_total" };
  const color = typeof x.color === "string" ? x.color.toUpperCase() : "#6A5CFF";
  if (!HEX.test(color)) return { ok: false, error: "bad_color" };
  const card: CardInput = { name, reward, stamps_total: total, color };
  if (typeof x.id === "string" && x.id) card.id = x.id;
  if (x.text_color !== undefined) {
    if (x.text_color === null || x.text_color === "") card.text_color = "";
    else if (typeof x.text_color === "string" && HEX.test(x.text_color)) card.text_color = x.text_color.toUpperCase();
    else return { ok: false, error: "bad_color" };
  }
  if (x.logo !== undefined) {
    if (x.logo === null || x.logo === "") card.logo = null;
    else {
      const l = typeof x.logo === "string" ? x.logo.replace(/^data:image\/[a-z]+;base64,/, "") : "";
      if (!B64.test(l)) return { ok: false, error: "bad_logo" };
      if (l.length > 210_000) return { ok: false, error: "logo_too_large" };
      card.logo = l;
    }
  }
  if (x.published !== undefined && x.published !== null) {
    if (typeof x.published !== "boolean") return { ok: false, error: "bad_card" };
    card.published = x.published;
  }
  return { ok: true, business: body.business_id as string, card };
}

/** Bekende fouten uit de database (message of hint) naar een code en HTTP-status; anders null (= serverfout). */
const DB_ERRORS: Record<string, number> = {
  not_found: 404, owner_taken: 409, has_owner: 409, not_approved: 409, card_limit: 409, test_limit: 409,
  bad_name: 400, bad_email: 400, bad_url: 400, bad_reward: 400, bad_color: 400, bad_total: 400, bad_logo: 400, bad_card: 400,
  bad_business: 400, bad_settings: 400, bad_status: 400,
};
export function dbError(e: { message?: string; hint?: string | null } | null): { error: string; status: number } | null {
  if (!e) return null;
  for (const k of [e.message ?? "", e.hint ?? ""]) if (k in DB_ERRORS) return { error: k, status: DB_ERRORS[k] };
  return null;
}
