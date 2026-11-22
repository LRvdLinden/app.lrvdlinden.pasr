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
