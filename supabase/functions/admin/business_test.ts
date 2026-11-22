import { cleanBusinessDetail, cleanBusinessSettings } from "./business.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const ID = "8f1d3c3e-5a7b-4c2d-9e1f-0a1b2c3d4e5f";

Deno.test("zaak-detail", () => {
  const d = cleanBusinessDetail({ id: ID });
  ok(d.ok && d.limit === 200 && d.days === 30, "standaard");
  ok(!cleanBusinessDetail({ id: "x" }).ok, "id");
  ok(!cleanBusinessDetail({ id: ID, limit: 0 }).ok && !cleanBusinessDetail({ id: ID, limit: 5000 }).ok, "limit");
  ok(!cleanBusinessDetail({ id: ID, days: 400 }).ok && !cleanBusinessDetail({ id: ID, days: 1.5 }).ok, "days");
  const e = cleanBusinessDetail({ id: ID, limit: "50", days: 7 });
  ok(e.ok && e.limit === 50 && e.days === 7, "tekst als getal");
});

Deno.test("instellingen: afkoeltijd en max per scan", () => {
  const s = cleanBusinessSettings({ id: ID, cooldown_minutes: 0, max_per_scan: 30 });
  ok(s.ok && s.settings.cooldown_minutes === 0 && s.settings.max_per_scan === 30, "grenzen mogen");
  ok(!cleanBusinessSettings({ id: ID, cooldown_minutes: 1441 }).ok, "afkoeltijd te hoog");
  ok(!cleanBusinessSettings({ id: ID, cooldown_minutes: -1 }).ok, "afkoeltijd negatief");
  ok(!cleanBusinessSettings({ id: ID, max_per_scan: 0 }).ok && !cleanBusinessSettings({ id: ID, max_per_scan: 31 }).ok, "max per scan");
  ok(!cleanBusinessSettings({ id: ID, max_per_scan: "drie" }).ok, "geen getal");
  ok(!cleanBusinessSettings({ id: ID }).ok, "niets om op te slaan");
  const one = cleanBusinessSettings({ id: ID, cooldown_minutes: 15 });
  ok(one.ok && !("max_per_scan" in one.settings), "alleen wat meegegeven is");
});
