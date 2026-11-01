// deno test supabase/functions/admin/auth_test.ts   (de sleutels hieronder zijn testwaarden)
import { bearer, FailureLog, hashIp, lockRetryAfter, readToken, sameSecret, signToken, TOKEN_TTL_S } from "./auth.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const S = "fedcba9876543210".repeat(4);
const NOW = Date.parse("2026-10-16T12:00:00Z"); // 1792152000 s

Deno.test("token: vorm uit het contract, gelijk aan python hmac", async () => {
  const { token, e } = await signToken(S, 3, NOW);
  ok(e === 1792152000 + TOKEN_TTL_S, `e ${e}`);
  // python3: payload = urlsafe_b64encode(json.dumps({"v":3,"e":…,"s":"admin"}, separators=(",",":"))).rstrip("=")
  ok(token === "eyJ2IjozLCJlIjoxNzkyMTk1MjAwLCJzIjoiYWRtaW4ifQ.mscvom231tIeu6kyb4YeM_B6rr2R6kK0gPIU-DprAoc", token);
  const p = await readToken(S, token, NOW);
  ok(p?.v === 3 && p.e === e, "terug te lezen");
});

Deno.test("token: verlopen, andere sleutel, geknoeid of rommel = null", async () => {
  const { token } = await signToken(S, 1, NOW);
  ok(await readToken(S, token, NOW + TOKEN_TTL_S * 1000) === null, "verlopen");
  ok(await readToken(S.replace("f", "e"), token, NOW) === null, "andere sleutel");
  ok(await readToken("", token, NOW) === null, "geen sleutel");
  const [p, s] = token.split(".");
  const other = btoa(JSON.stringify({ v: 99, e: 1892152000, s: "admin" })).replace(/=+$/, "");
  ok(await readToken(S, `${other}.${s}`, NOW) === null, "payload vervangen");
  ok(await readToken(S, `${p}.${s.slice(0, -1)}A`, NOW) === null, "handtekening aangepast");
  for (const t of [null, 1, "", "a.b", "x".repeat(500), `${p}.${s}.x`]) ok(await readToken(S, t, NOW) === null, `rommel ${String(t).slice(0, 20)}`);
});

Deno.test("token: alleen scope admin met gehele v en e", async () => {
  const sign = async (o: unknown) => {
    const pl = btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(S), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(pl)));
    return `${pl}.${btoa(String.fromCharCode(...sig)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")}`;
  };
  ok(await readToken(S, await sign({ v: 1, e: 1892152000, s: "admin" }), NOW) !== null, "goed");
  ok(await readToken(S, await sign({ v: 1, e: 1892152000, s: "widget" }), NOW) === null, "andere scope");
  ok(await readToken(S, await sign({ v: 1, e: 1892152000 }), NOW) === null, "zonder scope");
  ok(await readToken(S, await sign({ v: "1", e: 1892152000, s: "admin" }), NOW) === null, "v als tekst");
  ok(await readToken(S, await sign({ v: 1, e: 1892152000.5, s: "admin" }), NOW) === null, "e geen geheel getal");
});

Deno.test("bearer uit de kopregel", () => {
  ok(bearer(new Headers({ authorization: "Bearer abc.def" })) === "abc.def", "bearer");
  ok(bearer(new Headers({ authorization: "bearer   abc" })) === "abc", "hoofdletterongevoelig");
  ok(bearer(new Headers({ authorization: "Basic abc" })) === null && bearer(new Headers()) === null, "geen bearer");
});

Deno.test("inloggegevens constant-time vergelijken", async () => {
  ok(await sameSecret("geheim-wachtwoord", "geheim-wachtwoord", S), "gelijk");
  ok(!(await sameSecret("geheim-wachtwoorD", "geheim-wachtwoord", S)), "anders");
  ok(!(await sameSecret("", "", S)), "leeg nooit goed");
  ok(!(await sameSecret(undefined, "x", S)) && !(await sameSecret(5, "5", S)), "geen tekst");
});

Deno.test("ip-hash: vast per sleutel, geen IP zichtbaar", async () => {
  const a = await hashIp("203.0.113.9", S), b = await hashIp("203.0.113.9", S), c = await hashIp("203.0.113.9", "andere-sleutel");
  ok(a === b && a !== c && /^[0-9a-f]{24}$/.test(a) && !a.includes("203"), a);
});

Deno.test("blokkade: 5 fouten in 15 min = tot 15 min na de oudste van die 5", () => {
  const m = 60_000;
  ok(lockRetryAfter([NOW - 4 * m, NOW - 3 * m, NOW - 2 * m, NOW - m], NOW) === 0, "4 fouten: nog niet");
  const five = [NOW - 5 * m, NOW - 4 * m, NOW - 3 * m, NOW - 2 * m, NOW - m];
  ok(lockRetryAfter(five, NOW) === 10 * 60, `5 fouten: ${lockRetryAfter(five, NOW)}`);
  ok(lockRetryAfter(five.reverse(), NOW) === 10 * 60, "volgorde maakt niet uit");
  ok(lockRetryAfter([NOW - 20 * m, NOW - 4 * m, NOW - 3 * m, NOW - 2 * m, NOW - m], NOW) === 0, "oude fout telt niet");
  ok(lockRetryAfter(five, NOW + 10 * m) === 0, "na afloop weer vrij");
  ok(lockRetryAfter(Array(5).fill(NOW), NOW) === 15 * 60, "vijf tegelijk: 15 min");
});

Deno.test("fouten in het geheugen", () => {
  const f = new FailureLog();
  for (let i = 0; i < 7; i++) f.add("x", NOW + i);
  ok(f.get("x").length === 7 && lockRetryAfter(f.get("x"), NOW + 10) > 0, "geteld");
  f.clear("x");
  ok(f.get("x").length === 0, "gewist na inloggen");
});
