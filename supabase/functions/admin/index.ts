// Pasr Beheer: functie admin (verify_jwt = false, eigen tokens). Voor beheer.pasr.nl en de app Pasr Beheer.
// Geheimen alleen als function-secrets: PASR_ADMIN_USER, PASR_ADMIN_PASSWORD, PASR_TOKEN_SECRET (gemaakt door de workflow
// Backend), APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID (optioneel, voor pushmeldingen). Afspraken: beheer/CONTRACT.md.
//
// POST /functions/v1/admin  {action, ...}; na inloggen Authorization: Bearer <token>
//   login            {user, password}               -> {token, expires}         (5 fouten per IP = 15 min dicht: 429)
//   logout_all       {}                             -> {ok, v}                  (alle tokens vervallen, pushapparaten weg)
//   stats            {days?: 30, offset?: 0}        -> zie pasr_admin_stats + {push_ready}
//   users            {search?, filter?, limit?, offset?} -> {total, users:[…]}
//   user_delete      {id}                           -> {ok}                     (account + kaarten op de server)
//   user_resend      {id}                           -> {ok}                     (bevestigingsmail opnieuw)
//   push_register    {device_id, apns_token, platform, sandbox, app_build, prefs} -> {ok}
//   push_unregister  {device_id}                    -> {ok}
//   push_prefs       {device_id, prefs}             -> {ok} | 404 not_registered
//   push_test        {device_id}                    -> {ok} | 503 apns_not_configured | 404 not_registered
//   notify           {kind, reason?|name?}  + kop x-pasr-hook (alleen de database, via pg_net) -> {sent}
//   store_requests   {status?: open|added|rejected} -> {groups:[{key,name,website,kind,count,vouchers,ids,notes,first,last}]}
//   store_lookup     {url}                          -> {domain,name,colors,logo,logo_type} | 404 not_found
//   stores           {}                             -> {stores:[…]} (toegevoegde winkels, met logo)
//   store_save       {store:{id?,name,domain,category,card_hex,format,kind,aliases,logo}} -> {store}
//   store_publish    {id, request_ids?, push?}      -> {ok, sent, closed}  (aanvragen dicht als "toegevoegd")
//   store_unpublish  {id}                           -> {ok}
//   store_reject     {request_ids}                  -> {ok, closed}
// Nooit loggen: wachtwoorden, tokens, sleutels, e-mailadressen, APNs-tokens.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { bearer, FailureLog, GLOBAL_MAX, hashIp, LOCK_MAX, LOCK_WINDOW_S, lockRetryAfter, readToken, sameBytes, sameSecret, signToken } from "./auth.ts";
import { apnsHost, apnsJwt, apnsResult, BOT_QUIET_MS, cleanDeviceId, cleanPrefs, cleanRegister, type Counts, DEFAULT_TOPIC, importApnsKey, type Kind, KINDS, message, testPayload, wants } from "./push.ts";
import { isUuid, parseRange, parseUsers } from "./stats.ts";
import { cleanStore, domainOf, lookupSite, newStorePayload, USER_TOPIC } from "./stores.ts";
import { alreadyExists, cleanReview } from "./review.ts";

const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { autoRefreshToken: false, persistSession: false },
});
const tokenSecret = () => env("PASR_TOKEN_SECRET");
const configured = () => !!(env("PASR_ADMIN_USER") && Deno.env.get("PASR_ADMIN_PASSWORD") && tokenSecret().length >= 32);

// ---- CORS: alleen het dashboard op https://beheer.pasr.nl (en localhost om te testen); de app stuurt geen Origin ----
const ORIGIN_OK = /^https:\/\/beheer\.pasr\.nl$|^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;
function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  return {
    ...(ORIGIN_OK.test(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}
function clientIp(req: Request) {
  const h = (k: string) => (req.headers.get(k) ?? "").trim();
  const xff = h("x-forwarded-for").split(",").map((s) => s.trim()).filter(Boolean);
  return (h("cf-connecting-ip") || h("x-real-ip") || xff[xff.length - 1] || "?").slice(0, 64);
}

// ---- logboek en limieten ----
async function audit(action: string, ipHash: string, detail = "") {
  try {
    const { error } = await db.from("admin_audit").insert({ action, ip_hash: ipHash, detail: detail.slice(0, 300) });
    if (error) console.error("admin", "audit", action, error.message);
  } catch (e) { console.error("admin", "audit", action, e instanceof Error ? e.name : "?"); }
}
const memFailures = new FailureLog();
let memGlobal: number[] = [];
async function lockedFor(ipHash: string): Promise<number> {
  const now = Date.now();
  let times = memFailures.get(ipHash);
  let global = memGlobal.filter((t) => t > now - 3600_000).length;
  try {
    const since = new Date(now - LOCK_WINDOW_S * 1000).toISOString();
    const { data, error } = await db.from("admin_audit").select("at").eq("action", "login_failed").eq("ip_hash", ipHash)
      .gt("at", since).order("at", { ascending: false }).limit(LOCK_MAX);
    if (error) throw new Error(error.message);
    times = times.concat((data ?? []).map((r) => Date.parse(r.at)));
    const { count, error: ge } = await db.from("admin_audit").select("id", { count: "exact", head: true })
      .eq("action", "login_failed").gt("at", new Date(now - 3600_000).toISOString());
    if (!ge && typeof count === "number") global = Math.max(global, count);
  } catch (e) { console.error("admin", "lock", e instanceof Error ? e.message : "?"); }
  const own = lockRetryAfter(times, now);
  return global > GLOBAL_MAX ? Math.max(own, LOCK_WINDOW_S) : own;
}
const authedHits = new Map<string, { start: number; n: number }>();
function authedOk(ipHash: string): boolean {
  const now = Date.now(), h = authedHits.get(ipHash);
  if (!h || now - h.start > 60_000) {
    if (authedHits.size > 5000) authedHits.clear();
    authedHits.set(ipHash, { start: now, n: 1 });
    return true;
  }
  return ++h.n <= 300;
}

// ---- tokens ----
async function tokenVersion(): Promise<number> {
  const { data, error } = await db.from("admin_token_state").select("v").eq("id", 1).maybeSingle();
  if (error) throw new Error(`token_version: ${error.message}`);
  return Number(data?.v ?? 1);
}
async function validToken(token: string | null): Promise<boolean> {
  const p = await readToken(tokenSecret(), token);
  return p !== null && p.v === await tokenVersion();
}

// ---- seintjes van de database (pg_net): geheim uit pasr_secret, 5 minuten in het geheugen ----
let hookSecret: string | null = null, hookUntil = 0;
async function hookOk(given: string | null): Promise<boolean> {
  if (!given || given.length > 200) return false;
  if (!hookSecret || Date.now() > hookUntil) {
    const { data, error } = await db.from("pasr_secret").select("hook_secret").eq("id", 1).maybeSingle();
    if (error || !data?.hook_secret) return false;
    hookSecret = String(data.hook_secret);
    hookUntil = Date.now() + 300_000;
  }
  const te = new TextEncoder();
  return sameBytes(te.encode(given), te.encode(hookSecret));
}

// ---- APNs ----
const apnsConfigured = () => !!(env("APNS_KEY_P8") && env("APNS_KEY_ID"));
let apnsAuth: { jwt: string; at: number; kid: string } | null = null;
async function apnsBearer(): Promise<string> {
  const now = Date.now(), kid = env("APNS_KEY_ID");
  if (apnsAuth && apnsAuth.kid === kid && now - apnsAuth.at < 50 * 60_000) return apnsAuth.jwt;
  const iat = Math.floor(now / 1000);
  const jwt = await apnsJwt(await importApnsKey(env("APNS_KEY_P8")), kid, env("APNS_TEAM_ID") || "EU3UY476T6", iat);
  apnsAuth = { jwt, at: iat * 1000, kid };
  return jwt;
}
async function apnsSend(token: string, sandbox: boolean, payload: unknown, topic = env("PASR_APNS_TOPIC") || DEFAULT_TOPIC) {
  let auth: string;
  try { auth = await apnsBearer(); } catch (e) {
    console.error("admin", "apns_key", e instanceof Error ? e.name : "?");
    return { ok: false as const, invalid: false, error: "apns_bad_key" };
  }
  let res: Response;
  try {
    res = await fetch(`${apnsHost(sandbox)}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${auth}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    return { ok: false as const, invalid: false, error: "apns_unreachable" };
  }
  let reason = "";
  try { reason = String((await res.json())?.reason ?? ""); } catch { /* leeg antwoord bij 200 */ }
  const r = apnsResult(res.status, reason);
  if (!r.ok && /^(Expired|Invalid)ProviderToken$/.test(reason)) apnsAuth = null;
  return r;
}

/** Melding naar alle apparaten die deze soort willen; ongeldige tokens gaan weg. */
async function pushAll(kind: Kind, payload: unknown): Promise<number> {
  if (!apnsConfigured()) return 0;
  const { data, error } = await db.from("admin_push_devices").select("device_id, token, sandbox, prefs");
  if (error) throw new Error(error.message);
  const targets = (data ?? []).filter((d) => wants(d.prefs, kind));
  const results = await Promise.all(targets.map(async (d) => ({ d, r: await apnsSend(d.token, d.sandbox, payload) })));
  const invalid = results.filter((x) => !x.r.ok && x.r.invalid).map((x) => x.d.device_id);
  if (invalid.length) await db.from("admin_push_devices").delete().in("device_id", invalid);
  const failed = results.filter((x) => !x.r.ok && !x.r.invalid);
  if (failed.length) console.error("admin", "push", kind, (failed[0].r as { error: string }).error, failed.length);
  return results.filter((x) => x.r.ok).length;
}

async function counts(): Promise<Counts> {
  const { data, error } = await db.rpc("pasr_admin_counts");
  if (error) throw new Error(error.message);
  const o = (data ?? {}) as Record<string, unknown>;
  return { accounts: Number(o.accounts ?? 0), confirmed: Number(o.confirmed ?? 0), bots_hour: Number(o.bots_hour ?? 0) };
}

async function notify(kind: Kind, reason: unknown): Promise<number> {
  if (kind === "bot") {
    const { data } = await db.from("admin_push_state").select("last_at").eq("kind", "bot").maybeSingle();
    if (data?.last_at && Date.now() - Date.parse(data.last_at) < BOT_QUIET_MS) return 0;
    await db.from("admin_push_state").upsert({ kind: "bot", last_at: new Date().toISOString() });
  }
  return pushAll(kind, message(kind, await counts(), reason));
}

/** Melding aan gebruikers van Pasr over een nieuwe winkel: wie hem aanvroeg plus wie "Nieuwe winkels" aan heeft. */
async function pushNewStore(id: string, name: string, requesters: string[]): Promise<number> {
  if (!apnsConfigured()) return 0;
  const { data, error } = await db.from("pasr_user_push").select("device_id, token, sandbox, user_id, new_stores");
  if (error) throw new Error(error.message);
  const want = new Set(requesters);
  const targets = (data ?? []).filter((d) => d.new_stores || want.has(d.user_id));
  const payload = newStorePayload(name, id);
  const results = await Promise.all(targets.map(async (d) => ({ d, r: await apnsSend(d.token, d.sandbox, payload, USER_TOPIC) })));
  const invalid = results.filter((x) => !x.r.ok && x.r.invalid).map((x) => x.d.device_id);
  if (invalid.length) await db.from("pasr_user_push").delete().in("device_id", invalid);
  return results.filter((x) => x.r.ok).length;
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, ...extra, "Content-Type": "application/json", "Cache-Control": "no-store" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const origin = req.headers.get("Origin");
  if (origin && !ORIGIN_OK.test(origin)) return json({ error: "forbidden" }, 403);

  let body: Record<string, unknown>;
  try {
    const text = await req.text();
    // een winkel met logo mag groter zijn
    if (text.length > 450_000) return json({ error: "too_large" }, 413);
    const b = JSON.parse(text || "{}");
    if (!b || typeof b !== "object" || Array.isArray(b)) return json({ error: "bad_json" }, 400);
    if (text.length > 8192 && b.action !== "store_save") return json({ error: "too_large" }, 413);
    body = b;
  } catch { return json({ error: "bad_json" }, 400); }
  const action = typeof body.action === "string" ? body.action : "";

  try {
    // Seintje van de database: eigen geheim, geen beheer-token.
    if (action === "notify") {
      if (!(await hookOk(req.headers.get("x-pasr-hook")))) return json({ error: "forbidden" }, 403);
      if (!(KINDS as readonly unknown[]).includes(body.kind)) return json({ error: "bad_kind" }, 400);
      return json({ sent: await notify(body.kind as Kind, body.kind === "store_request" ? body.name : body.reason) });
    }

    if (!configured()) return json({ error: "not_configured" }, 503);
    const ipHash = await hashIp(clientIp(req), tokenSecret());

    if (action === "login") {
      const wait = await lockedFor(ipHash);
      if (wait > 0) {
        await audit("login_locked", ipHash, `retry_after=${wait}`);
        return json({ error: "locked", retry_after: wait }, 429, { "Retry-After": String(wait) });
      }
      const key = tokenSecret();
      const [u, p] = await Promise.all([
        // gebruikersnaam zonder verschil tussen hoofdletters en kleine letters
        sameSecret(typeof body.user === "string" ? body.user.trim().toLowerCase() : body.user, env("PASR_ADMIN_USER").toLowerCase(), key),
        // regeleinden aan het eind van een geplakt secret tellen niet mee
        sameSecret(typeof body.password === "string" ? body.password.replace(/[\r\n]+$/, "") : body.password,
          (Deno.env.get("PASR_ADMIN_PASSWORD") ?? "").replace(/[\r\n]+$/, ""), key),
      ]);
      if (!(u && p)) {
        memFailures.add(ipHash);
        memGlobal = memGlobal.filter((t) => t > Date.now() - 3600_000).concat(Date.now()).slice(-500);
        await audit("login_failed", ipHash);
        return json({ error: "invalid_credentials" }, 401);
      }
      memFailures.clear(ipHash);
      const { token, e } = await signToken(key, await tokenVersion());
      await audit("login", ipHash);
      return json({ token, expires: new Date(e * 1000).toISOString() });
    }

    if (!(await validToken(bearer(req.headers)))) return json({ error: "unauthorized" }, 401);
    if (!authedOk(ipHash)) return json({ error: "rate_limited", retry_after: 60 }, 429, { "Retry-After": "60" });

    switch (action) {
      case "logout_all": {
        const { data, error } = await db.rpc("pasr_admin_logout_all");
        if (error) throw new Error(error.message);
        await db.from("admin_push_devices").delete().neq("device_id", "");
        await audit("logout_all", ipHash, `v=${data}`);
        return json({ ok: true, v: Number(data) });
      }
      case "stats": {
        const q = parseRange(body.days, body.offset);
        if (!q) return json({ error: "bad_range" }, 400);
        const { data, error } = await db.rpc("pasr_admin_stats", { p_days: q.days, p_offset: q.offset });
        if (error) throw new Error(error.message);
        return json({ ...(data as Record<string, unknown>), push_ready: apnsConfigured() });
      }
      case "users": {
        const q = parseUsers(body);
        if (!q) return json({ error: "bad_request" }, 400);
        const { data, error } = await db.rpc("pasr_admin_users",
          { p_search: q.search, p_filter: q.filter, p_limit: q.limit, p_offset: q.offset });
        if (error) throw new Error(error.message);
        return json(data);
      }
      case "user_delete": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { error } = await db.auth.admin.deleteUser(body.id);
        if (error) return json({ error: /not.?found/i.test(error.message) ? "not_found" : "delete_failed" }, error.status === 404 ? 404 : 502);
        await audit("user_delete", ipHash);
        return json({ ok: true });
      }
      case "user_resend": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { data, error } = await db.auth.admin.getUserById(body.id);
        if (error || !data?.user?.email) return json({ error: "not_found" }, 404);
        if (data.user.email_confirmed_at) return json({ error: "already_confirmed" }, 409);
        const res = await fetch(`${env("SUPABASE_URL")}/auth/v1/resend`, {
          method: "POST",
          headers: { apikey: env("SUPABASE_ANON_KEY") || env("SUPABASE_SERVICE_ROLE_KEY"), "Content-Type": "application/json" },
          body: JSON.stringify({ type: "signup", email: data.user.email, options: { emailRedirectTo: "https://pasr.nl/bevestigen/" } }),
          signal: AbortSignal.timeout(15000),
        });
        await res.body?.cancel().catch(() => {});
        if (!res.ok) return json({ error: res.status === 429 ? "rate_limited" : "resend_failed" }, res.status === 429 ? 429 : 502);
        await audit("user_resend", ipHash);
        return json({ ok: true });
      }
      case "push_register": {
        const v = cleanRegister(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const r = v.value;
        // één rij per token: een apparaat dat opnieuw is geïnstalleerd, krijgt een nieuwe id
        await db.from("admin_push_devices").delete().eq("token", r.apns_token).neq("device_id", r.device_id);
        const { error } = await db.from("admin_push_devices").upsert({
          device_id: r.device_id, token: r.apns_token, platform: r.platform, sandbox: r.sandbox, app_build: r.app_build,
          prefs: r.prefs, updated_at: new Date().toISOString(),
        });
        if (error) throw new Error(error.message);
        await audit("push_register", ipHash, r.platform);
        return json({ ok: true, push_ready: apnsConfigured() });
      }
      case "push_unregister": {
        const id = cleanDeviceId(body.device_id);
        if (!id) return json({ error: "bad_device_id" }, 400);
        await db.from("admin_push_devices").delete().eq("device_id", id);
        return json({ ok: true });
      }
      case "push_prefs": {
        const id = cleanDeviceId(body.device_id), prefs = cleanPrefs(body.prefs);
        if (!id) return json({ error: "bad_device_id" }, 400);
        if (!prefs) return json({ error: "bad_prefs" }, 400);
        const { data, error } = await db.from("admin_push_devices").update({ prefs, updated_at: new Date().toISOString() })
          .eq("device_id", id).select("device_id");
        if (error) throw new Error(error.message);
        if (!data?.length) return json({ error: "not_registered" }, 404);
        return json({ ok: true });
      }
      case "push_test": {
        const id = cleanDeviceId(body.device_id);
        if (!id) return json({ error: "bad_device_id" }, 400);
        if (!apnsConfigured()) return json({ error: "apns_not_configured" }, 503);
        const { data } = await db.from("admin_push_devices").select("token, sandbox").eq("device_id", id).maybeSingle();
        if (!data) return json({ error: "not_registered" }, 404);
        const r = await apnsSend(data.token, data.sandbox, testPayload());
        if (!r.ok) {
          if (r.invalid) await db.from("admin_push_devices").delete().eq("device_id", id);
          return json({ error: r.invalid ? "apns_invalid" : r.error }, r.invalid ? 410 : 502);
        }
        return json({ ok: true });
      }
      case "store_requests": {
        const status = ["open", "added", "rejected"].includes(String(body.status)) ? String(body.status) : "open";
        const { data, error } = await db.from("pasr_store_requests").select("id, name, website, note, kind, status, store_id, created_at, closed_at")
          .eq("status", status).order("created_at", { ascending: false }).limit(500);
        if (error) throw new Error(error.message);
        // zelfde winkel (op website, anders op naam) = één regel met het aantal aanvragen
        const groups = new Map<string, { key: string; name: string; website: string | null; kind: string; count: number; vouchers: number; ids: string[]; notes: string[]; first: string; last: string; store_id: string | null }>();
        for (const r of data ?? []) {
          const key = domainOf(r.website) ?? r.name.toLowerCase().replace(/\s+/g, " ").trim();
          const g = groups.get(key) ?? { key, name: r.name, website: domainOf(r.website), kind: "loyalty", count: 0, vouchers: 0, ids: [], notes: [], first: r.created_at, last: r.created_at, store_id: r.store_id };
          g.count++; g.ids.push(r.id); if (r.note) g.notes.push(r.note);
          if (r.kind === "voucher") g.vouchers++;
          g.kind = g.vouchers * 2 > g.count ? "voucher" : "loyalty";   // wat de meeste aanvragers bedoelen
          if (r.created_at < g.first) g.first = r.created_at;
          if (!g.website && domainOf(r.website)) g.website = domainOf(r.website);
          groups.set(key, g);
        }
        return json({ groups: [...groups.values()].sort((a, b) => b.count - a.count || b.last.localeCompare(a.last)) });
      }
      case "store_lookup": {
        const r = await lookupSite(body.url);
        if (!r) return json({ error: "not_found" }, 404);
        await audit("store_lookup", ipHash, r.domain);
        return json(r);
      }
      case "stores": {
        const { data, error } = await db.from("pasr_stores").select("*").order("updated_at", { ascending: false }).limit(500);
        if (error) throw new Error(error.message);
        return json({ stores: data ?? [] });
      }
      case "store_save": {
        const v = cleanStore(body.store);
        if (!v.ok) return json({ error: v.error }, 400);
        const { data, error } = await db.from("pasr_stores").upsert({ ...v.value, updated_at: new Date().toISOString() }).select("*").single();
        if (error) throw new Error(error.message);
        await audit("store_save", ipHash, v.value.id);
        return json({ store: data });
      }
      case "store_publish": {
        const id = typeof body.id === "string" ? body.id : "";
        const { data: store } = await db.from("pasr_stores").select("id, name").eq("id", id).maybeSingle();
        if (!store) return json({ error: "not_found" }, 404);
        const now = new Date().toISOString();
        const { error } = await db.from("pasr_stores").update({ published: true, published_at: now, updated_at: now }).eq("id", id);
        if (error) throw new Error(error.message);
        const ids = (Array.isArray(body.request_ids) ? body.request_ids : []).filter(isUuid).slice(0, 500);
        let requesters: string[] = [];
        if (ids.length) {
          const { data: closed, error: ce } = await db.from("pasr_store_requests")
            .update({ status: "added", store_id: id, closed_at: now }).in("id", ids).select("user_id");
          if (ce) throw new Error(ce.message);
          requesters = [...new Set((closed ?? []).map((r) => r.user_id).filter(Boolean))];
        }
        const sent = body.push === false ? 0 : await pushNewStore(id, store.name, requesters);
        await audit("store_publish", ipHash, `${id} closed=${ids.length} sent=${sent}`);
        return json({ ok: true, sent, closed: ids.length, push_ready: apnsConfigured() });
      }
      case "store_unpublish": {
        const id = typeof body.id === "string" ? body.id : "";
        const { error } = await db.from("pasr_stores").update({ published: false, updated_at: new Date().toISOString() }).eq("id", id);
        if (error) throw new Error(error.message);
        await audit("store_unpublish", ipHash, id);
        return json({ ok: true });
      }
      case "store_reject": {
        const ids = (Array.isArray(body.request_ids) ? body.request_ids : []).filter(isUuid).slice(0, 500);
        if (!ids.length) return json({ error: "bad_request" }, 400);
        const { error } = await db.from("pasr_store_requests").update({ status: "rejected", closed_at: new Date().toISOString() }).in("id", ids);
        if (error) throw new Error(error.message);
        await audit("store_reject", ipHash, String(ids.length));
        return json({ ok: true, closed: ids.length });
      }
      case "review_account": {
        // Account voor Apple App Review met voorbeeldkaarten en een gedeelde Pasr. Het wachtwoord kiest de beheerder;
        // het gaat alleen naar de auth admin API en komt niet in logboek, audit of antwoord.
        const v = cleanReview(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const { email, password, firstName, reset } = v.value;
        let userId = "";
        let created = false;
        const { data: made, error: ce } = await db.auth.admin.createUser({
          email, password, email_confirm: true, user_metadata: { first_name: firstName, app: "review" },
        });
        if (made?.user?.id) {
          userId = made.user.id;
          created = true;
        } else if (ce && alreadyExists(ce.message, ce.status)) {
          if (!reset) return json({ error: "exists" }, 409);
          const { data: id } = await db.rpc("pasr_admin_user_id", { p_email: email });
          if (typeof id !== "string") return json({ error: "not_found" }, 404);
          const { error: ue } = await db.auth.admin.updateUserById(id, { password, email_confirm: true });
          if (ue) return json({ error: /password/i.test(ue.message) ? "weak_password" : "update_failed" }, 400);
          userId = id;
        } else {
          return json({ error: ce && /password/i.test(ce.message) ? "weak_password" : "create_failed" }, ce?.status === 429 ? 429 : 400);
        }
        const { data: seed, error: se } = await db.rpc("pasr_admin_review_seed", { p_user: userId });
        if (se) return json({ error: /group_limit/.test(se.message) ? "group_limit" : "seed_failed", created }, 500);
        await audit("review_account", ipHash, created ? "created" : "reset");
        return json({ ok: true, created, email, ...(seed as Record<string, unknown>) });
      }
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    console.error("admin", action || "?", e instanceof Error ? e.message : "?");
    return json({ error: "server_error" }, 500);
  }
});
