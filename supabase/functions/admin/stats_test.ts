// deno test supabase/functions/admin/stats_test.ts
import { isUuid, parseRange, parseUsers } from "./stats.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("periode", () => {
  ok(JSON.stringify(parseRange(undefined, undefined)) === '{"days":30,"offset":0}', "standaard");
  ok(parseRange(7, 3)?.offset === 3, "week terug");
  ok(parseRange(14, 0) === null, "geen 14");
  ok(parseRange(365, 4) === null, "te ver terug");
  ok(parseRange(30, 1.5) === null, "geen breuk");
});

Deno.test("accounts zoeken", () => {
  ok(parseUsers({})?.limit === 50, "standaard");
  ok(parseUsers({ search: "  anna ", filter: "cards" })?.search === "anna", "trim");
  ok(parseUsers({ filter: "admins" }) === null, "filter");
  ok(parseUsers({ limit: 500 }) === null, "limiet");
  ok(parseUsers({ search: "x".repeat(200) }) === null, "lang");
});

Deno.test("uuid", () => {
  ok(isUuid("c0e43231-6c4a-4c5c-b112-3ef9d05ffccf"), "geldig");
  ok(!isUuid("c0e43231'; drop table x"), "ongeldig");
});
