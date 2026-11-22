import { chunks, cleanAudience, cleanNews, newsPayload } from "./news.ts";
import { cleanBusinessStatus } from "./business.ts";
import { message } from "./push.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("bericht controleren", () => {
  const r = cleanNews({ title: "  Nieuw  ", body: " Hallo\n\n\n\nwereld ", audience: "all" });
  ok(r.ok && r.value.title === "Nieuw" && r.value.body === "Hallo\n\nwereld" && r.value.store === null, JSON.stringify(r));
  ok(!cleanNews({ body: "", audience: "all" }).ok, "tekst verplicht");
  ok(!cleanNews({ body: "x", audience: "iedereen" }).ok, "doelgroep");
  ok(!cleanNews({ body: "x", audience: "store" }).ok, "winkel verplicht bij store");
  ok(!cleanNews({ body: "x", audience: "store", store: "AH; drop" }).ok, "winkel-id");
  const s = cleanNews({ body: "x".repeat(500), audience: "store", store: "AH" });
  ok(s.ok && s.value.body.length === 240 && s.value.store === "ah", "afkappen en kleine letters");
  const t = cleanNews({ body: "a", title: "", audience: "inactive" });
  ok(t.ok && t.value.title === null, "lege titel = null");
  ok(cleanAudience({ audience: "new" }).ok, "nieuw");
});

Deno.test("melding nieuws", () => {
  const p = newsPayload({ title: null, body: "Hoi", audience: "store", store: "ah" }, "id-1");
  ok(p.aps.alert.title === "Pasr" && p.kind === "news" && p.store === "ah" && p.id === "id-1", JSON.stringify(p));
  const q = newsPayload({ title: "T", body: "B", audience: "all", store: null }, "id-2");
  ok(!("store" in q) && q.aps["thread-id"] === "news", "zonder winkel");
  ok(chunks([1, 2, 3, 4, 5], 2).length === 3 && chunks([], 2).length === 0, "stukken");
});

Deno.test("ondernemers", () => {
  ok(cleanBusinessStatus({ id: "8f1d3c3e-5a7b-4c2d-9e1f-0a1b2c3d4e5f", status: "approved" }).ok, "goedkeuren");
  ok(!cleanBusinessStatus({ id: "x", status: "approved" }).ok, "id");
  ok(!cleanBusinessStatus({ id: "8f1d3c3e-5a7b-4c2d-9e1f-0a1b2c3d4e5f", status: "deleted" }).ok, "status");
  const m = message("business", { accounts: 1, confirmed: 1, bots_hour: 0 }, "Bakkerij\nDe Korf");
  ok(m.aps.alert.title === "Nieuwe ondernemer" && m.aps.alert.body.startsWith("Bakkerij De Korf ") && m.url === "pasrbeheer://businesses", m.aps.alert.body);
});
