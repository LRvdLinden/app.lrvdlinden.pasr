// Pasr voor ondernemers (1.0.3): goedkeuren en blokkeren vanuit het beheer. Pure hulpjes, getest in news_test.ts.
import { isUuid } from "./stats.ts";

export const BUSINESS_STATUSES = ["pending", "approved", "blocked"] as const;
export type BusinessStatus = typeof BUSINESS_STATUSES[number];

export function cleanBusinessStatus(b: Record<string, unknown>): { ok: true; id: string; status: BusinessStatus } | { ok: false; error: string } {
  if (!isUuid(b.id)) return { ok: false, error: "bad_id" };
  if (!(BUSINESS_STATUSES as readonly unknown[]).includes(b.status)) return { ok: false, error: "bad_status" };
  return { ok: true, id: b.id as string, status: b.status as BusinessStatus };
}
