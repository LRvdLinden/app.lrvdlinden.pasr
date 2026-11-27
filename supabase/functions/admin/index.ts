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
//   user_confirm     {id}                           -> {ok}                     (e-mailadres bevestigen; nooit wachtwoorden)
//   push_register    {device_id, apns_token, platform, sandbox, app_build, prefs} -> {ok}
//   push_unregister  {device_id}                    -> {ok}
//   push_prefs       {device_id, prefs}             -> {ok} | 404 not_registered
//   push_test        {device_id}                    -> {ok} | 503 apns_not_configured | 404 not_registered
//   notify           {kind, reason?|name?}  + kop x-pasr-hook (alleen de database, via pg_net) -> {sent}
//   store_requests   {status?: open|added|rejected} -> {groups:[{key,name,website,kind,count,vouchers,ids,notes,first,last}]}
//   store_lookup     {url}                          -> {domain,name,colors,logo,logo_type} | 404 not_found
//   stores           {}                             -> {stores:[…]} (toegevoegde winkels, met logo)
//   store_save       {store:{id?,name,domain,category,card_hex,format,kind,aliases,logo,guide?,cover?}} -> {store}
//                    (cover: base64 JPEG/PNG van het kaartontwerp, null = verwijderen; weglaten = laten staan)
//   store_publish    {id, request_ids?, push?}      -> {ok, sent, closed}  (aanvragen dicht als "toegevoegd")
//   store_unpublish  {id}                           -> {ok}
//   store_reject     {request_ids}                  -> {ok, closed}
//   news_overview    {}                             -> {all, new, inactive, everyone:{pasr:{ios,android},zakelijk:{…}},
//                                                       stores:[{id,count}], history:[…, platform, app, url], push_ready}
//   news_count       {audience, store?, platform?, app?} -> {count, ios, android, pasr, zakelijk}
//   news_send        {title?, body, audience, store?, platform?, app?, url?} -> {id, recipients, sent, failed, ios, android}
//                    audience: all | store | new | inactive (opt-in "Nieuws over mijn kaarten", alleen Pasr) of
//                    everyone (iedereen met meldingen aan); platform: all | ios | android; app: pasr | zakelijk | both
//                    (alleen bij everyone); url: https, max 500, opent bij een tik. 409 duplicate = zelfde bericht net verstuurd.
//   businesses       {}                             -> {businesses:[…zaak, cards, staff_count, last_event_at]}
//   business_status  {id, status}                   -> {business}            (blocked = kaarten offline)
//   business_detail  {id, limit?, days?}            -> {business, staff, log, stats}
//   business_settings {id, cooldown_minutes?, max_per_scan?} -> {business}
//   business_staff_revoke {id}                      -> {ok}                   (medewerker intrekken)
//   (zakelijk 1.1: het beheer maakt zelf zaken en kaarten; alles in de log van de zaak met actor "beheer")
//   business_create  {business:{name, city?, address?, website?, email?, note?, listed?, cooldown_minutes?, max_per_scan?}, send?}
//                    -> {business, owner: account|invite|none, invite, mailed}  (meteen goedgekeurd; 409 owner_taken)
//   business_update  {id, business:{…zelfde, weglaten = laten staan}, send?} -> {business, owner, invite, mailed}
//   business_owner_invite {id, email?, send?}       -> {business, owner, invite, mailed} (nieuwe link; 409 has_owner)
//   business_owner_confirm {id}                     -> {business, owner, invite} (onbevestigd account met het adres van
//                    de zaak bevestigen en eigenaar maken; 404 not_found, 409 already_confirmed/has_owner/owner_taken)
//   business_card_save {business_id, card:{id?, name, reward, stamps_total, color, text_color?, logo?, published?}} -> {card}
//   business_card_publish {id, published}           -> {card}                 (409 not_approved)
//   business_card_delete {id}                       -> {ok, members}
//   business_test_member {card_id}                -> {member:{id, member_code, label, stamps_count, …}} (Testklant (App Review))
//   business_test_member_reset {id} / business_test_member_delete {id} -> {ok}  (alleen leden met een label)
//   business_brand   {business_id?, url?}           -> {name, logo, color, text_color, source_url, domain} (zelfde als business-brand)
// Nooit loggen: wachtwoorden, tokens, sleutels, e-mailadressen, APNs-tokens.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { bearer, FailureLog, GLOBAL_MAX, hashIp, LOCK_MAX, LOCK_WINDOW_S, lockRetryAfter, readToken, sameBytes, sameSecret, signToken } from "./auth.ts";
import { cleanFcmToken, fcmMessage, fcmResult, fcmUrl, importRsaKey, memberPayload, oauthAssertion, parseServiceAccount, type ServiceAccount } from "./fcm.ts";
import { apnsHost, apnsJwt, apnsResult, BOT_QUIET_MS, cleanDeviceId, cleanPrefs, cleanRegister, type Counts, DEFAULT_TOPIC, importApnsKey, type Kind, KINDS, message, testPayload, topicOrder, wants } from "./push.ts";
import { isUuid, parseRange, parseUsers } from "./stats.ts";
import { cleanBalancePage, requestMatches, cleanStore, domainOf, lookupSite, newStorePayload, USER_TOPIC } from "./stores.ts";
import { alreadyExists, cleanReview } from "./review.ts";
import { chunks, cleanAudience, cleanNews, DUPLICATE_WINDOW_MS, newsFingerprint, newsPayload, type Target, uniqueTokens, wantsAndroid, wantsIos } from "./news.ts";
import { cleanBusinessDetail, cleanBusinessInput, cleanBusinessSettings, cleanBusinessStatus, cleanCardInput, dbError } from "./business.ts";
import { okLink, ownerMail } from "./owner_mail.ts";
// huisstijl: dezelfde code als de functie business-brand (SSRF-beveiligd ophalen, logo en kleur)
import { cleanUrl } from "../business-brand/brand.ts";
import { brand } from "../business-brand/fetch.ts";
import nodemailer from "npm:nodemailer@6.9.16";

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

// ---- FCM (Android) ----
// Function secret FIREBASE_SERVICE_ACCOUNT_JSON (zet de workflow Backend). Zonder secret: alleen APNs, zoals vroeger.
let fcmSa: ServiceAccount | null | undefined;
let fcmAuth: { token: string; until: number } | null = null;
const fcmAccount = () => (fcmSa === undefined ? (fcmSa = parseServiceAccount(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON"))) : fcmSa);
const fcmConfigured = () => !!fcmAccount();
const pushConfigured = () => apnsConfigured() || fcmConfigured();
async function fcmBearer(): Promise<string> {
  if (fcmAuth && Date.now() < fcmAuth.until) return fcmAuth.token;
  const sa = fcmAccount()!;
  const assertion = await oauthAssertion(sa, await importRsaKey(sa.private_key));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) { await res.body?.cancel(); throw new Error(`fcm_oauth_${res.status}`); }
  const j = await res.json();
  fcmAuth = { token: String(j.access_token), until: Date.now() + 50 * 60_000 };
  return fcmAuth.token;
}
async function fcmSend(token: string, payload: unknown, channel = "news") {
  const sa = fcmAccount();
  if (!sa) return { ok: false as const, invalid: false, error: "fcm_not_configured" };
  let auth: string;
  try { auth = await fcmBearer(); } catch (e) {
    console.error("admin", "fcm_auth", e instanceof Error ? e.message.slice(0, 40) : "?");
    return { ok: false as const, invalid: false, error: "fcm_auth" };
  }
  let res: Response;
  try {
    res = await fetch(fcmUrl(sa.project_id), {
      method: "POST", headers: { authorization: `Bearer ${auth}`, "content-type": "application/json" },
      body: JSON.stringify(fcmMessage(token, payload, channel)), signal: AbortSignal.timeout(10000),
    });
  } catch {
    return { ok: false as const, invalid: false, error: "fcm_unreachable" };
  }
  let b: unknown = null;
  try { b = await res.json(); } catch { /* leeg */ }
  if (res.status === 401) fcmAuth = null;
  return fcmResult(res.status, b);
}
/** Naar een lijst Android-toestellen (pasr_devices); ongeldige tokens gaan weg. Geeft {sent, failed}. */
async function fcmToDevices(list: { device_id: string; token: string }[], payload: unknown, channel: string) {
  let sent = 0, failed = 0;
  const invalid: string[] = [];
  for (const part of chunks(list, 100)) {
    const res = await Promise.all(part.map(async (d) => ({ d, r: await fcmSend(d.token, payload, channel) })));
    for (const x of res) {
      if (x.r.ok) sent++;
      else { failed++; if (x.r.invalid) invalid.push(x.d.device_id); }
    }
  }
  if (invalid.length) await db.rpc("pasr_admin_push_forget", { p_devices: invalid });
  return { sent, failed };
}

/** Melding naar alle apparaten die deze soort willen; ongeldige tokens gaan weg. */
/** Naar een beheer-apparaat: met het topic van die app. Weet de server nog niet welke app het is (oudere versies,
 *  of het topic klopt niet: DeviceTokenNotForTopic), dan probeert hij de andere beheer-app en onthoudt het. */
async function adminSend(d: { device_id: string; token: string; sandbox: boolean; topic?: string | null; provider?: string | null }, payload: unknown) {
  if (d.provider === "fcm") return await fcmSend(d.token, payload, "admin");
  let last: Awaited<ReturnType<typeof apnsSend>> = { ok: false as const, invalid: true, error: "apns_none" };
  for (const topic of topicOrder(d.topic)) {
    const r = await apnsSend(d.token, d.sandbox, payload, topic);
    if (r.ok) {
      if (topic !== d.topic) await db.from("admin_push_devices").update({ topic }).eq("device_id", d.device_id);
      return r;
    }
    last = r;
    if (r.error !== "apns_DeviceTokenNotForTopic" && r.error !== "apns_BadDeviceToken") return r;
  }
  return last;
}

/** Melding naar alle apparaten die deze soort willen; ongeldige tokens gaan weg. */
async function pushAll(kind: Kind, payload: unknown): Promise<number> {
  if (!pushConfigured()) return 0;
  const { data, error } = await db.from("admin_push_devices").select("device_id, token, sandbox, prefs, topic, provider");
  if (error) throw new Error(error.message);
  const targets = (data ?? []).filter((d) => wants(d.prefs, kind));
  const results = await Promise.all(targets.map(async (d) => ({ d, r: await adminSend(d, payload) })));
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

/** Naar een Pasr-gebruiker. Klopt de omgeving niet (een ontwikkelversie meldt zich als productie of andersom:
 *  BadDeviceToken), dan de andere omgeving proberen en dat onthouden. */
async function userSend(d: { device_id: string; token: string; sandbox: boolean }, payload: unknown) {
  const r = await apnsSend(d.token, d.sandbox, payload, USER_TOPIC);
  if (r.ok || r.error !== "apns_BadDeviceToken") return r;
  const other = await apnsSend(d.token, !d.sandbox, payload, USER_TOPIC);
  if (other.ok) await db.from("pasr_user_push").update({ sandbox: !d.sandbox }).eq("device_id", d.device_id);
  return other.ok ? other : r;
}

/** Persoonlijke terugkomherinneringen: opt-in per stempelkaart, nooit een massamailing.
 * De database biedt maximaal vijftig geclaimde ontvangers per run aan en markeert
 * alleen na een geslaagde verzending de laatst bezochte stempelcyclus. */
async function pushRetention(): Promise<number> {
  if (!pushConfigured()) return 0;
  const { data, error } = await db.rpc("pasr_business_retention_due", { p_limit: 50 });
  if (error) throw new Error(error.message);
  const due = (Array.isArray(data) ? data : []) as {
    member_id: string; user_id: string; stamp_at: string; business: string; card: string; days: number
  }[];
  let sent = 0;
  for (const group of chunks(due, 5)) {
    await Promise.all(group.map(async item => {
      if (!isUuid(item.member_id) || !isUuid(item.user_id)) return;
      const business = String(item.business || "de winkel").replace(/[\r\n]/g, " ").slice(0, 60);
      const payload = {
        aps: { alert: { title: `Je wordt gemist bij ${business}`,
          body: "Kom weer langs en spaar verder met je Pasr-stempelkaart." },
          sound: "default", "thread-id": "stamps" },
        kind: "retention"
      };
      const [ios, android] = await Promise.all([
        apnsConfigured()
          ? db.from("pasr_user_push").select("device_id, token, sandbox").eq("user_id", item.user_id)
          : Promise.resolve({ data: [], error: null }),
        fcmConfigured()
          ? db.from("pasr_devices").select("device_id,push_token")
              .eq("app", "pasr").eq("push_provider", "fcm").eq("user_id", item.user_id)
              .not("push_token", "is", null)
          : Promise.resolve({ data: [], error: null }),
      ]);
      if (ios.error || android.error) return;
      const apple = (ios.data ?? []) as { device_id: string; token: string; sandbox: boolean }[];
      const google = (android.data ?? []) as { device_id: string; push_token: string }[];
      const appleResults = await Promise.all(apple.slice(0, 10).map(d => userSend(d, payload)));
      const deliveredApple = appleResults.filter(x => x.ok).length;
      const deliveredAndroid = fcmConfigured()
        ? (await fcmToDevices(google.slice(0, 10).map(x => ({ device_id:x.device_id, token:x.push_token })), payload, "stamps")).sent
        : 0;
      if (deliveredApple + deliveredAndroid > 0) {
        const ack = await db.rpc("pasr_business_retention_sent", {
          p_member: item.member_id, p_stamp: item.stamp_at
        });
        if (!ack.error && ack.data === true) sent += deliveredApple + deliveredAndroid;
      }
    }));
  }
  return sent;
}

// ---- Bericht sturen (news): doelgroep, versturen, ongeldige tokens opruimen ----
type NewsTarget = { device_id: string; token: string; sandbox: boolean; app: "pasr" | "zakelijk"; src: "device" | "user" | "news" };
/** Bundle-id van Pasr Zakelijk (APNs-topic). */
const ZAKELIJK_TOPIC = "app.lrvdlinden.pasrzakelijk";

/** De toestellen van een doelgroep, apart voor iOS (APNs) en Android (FCM), al gefilterd op platform en app. */
async function newsTargets(t: Target): Promise<{ ios: NewsTarget[]; android: NewsTarget[] }> {
  if (t.audience === "everyone") {
    const { data, error } = await db.rpc("pasr_admin_push_everyone", { p_app: t.app, p_platform: t.platform });
    if (error) throw new Error(error.message);
    const rows = (data ?? []) as (NewsTarget & { provider: string })[];
    const pick = (p: string) => uniqueTokens(rows.filter((r) => r.provider === p)).map(({ provider: _, ...r }) => ({ ...r, sandbox: !!r.sandbox }));
    return { ios: wantsIos(t) ? pick("apns") : [], android: wantsAndroid(t) ? pick("fcm") : [] };
  }
  const [{ data, error }, { data: fcm, error: fe }] = await Promise.all([
    wantsIos(t) ? db.rpc("pasr_admin_news_targets", { p_audience: t.audience, p_store: t.store }) : Promise.resolve({ data: [], error: null }),
    wantsAndroid(t) ? db.rpc("pasr_admin_news_targets_fcm", { p_audience: t.audience, p_store: t.store }) : Promise.resolve({ data: [], error: null }),
  ]);
  if (error) throw new Error(error.message);
  const ios = ((data ?? []) as { device_id: string; token: string; sandbox: boolean }[])
    .map((d) => ({ ...d, app: "pasr" as const, src: "news" as const }));
  const android = (fe ? [] : (fcm ?? []) as { device_id: string; token: string }[])
    .map((d) => ({ ...d, sandbox: false, app: "pasr" as const, src: "device" as const }));
  return { ios: uniqueTokens(ios), android: uniqueTokens(android) };
}

/** Naar één iOS-toestel met het topic van de app. Klopt de omgeving niet (BadDeviceToken), dan de andere proberen en
 *  dat onthouden in de tabel waar het token vandaan kwam. */
async function newsIosSend(d: NewsTarget, payload: unknown) {
  const topic = d.app === "zakelijk" ? ZAKELIJK_TOPIC : USER_TOPIC;
  const r = await apnsSend(d.token, d.sandbox, payload, topic);
  if (r.ok || r.error !== "apns_BadDeviceToken") return r;
  const other = await apnsSend(d.token, !d.sandbox, payload, topic);
  if (other.ok) {
    if (d.src === "user") await db.from("pasr_user_push").update({ sandbox: !d.sandbox }).eq("device_id", d.device_id);
    else if (d.src === "news") await db.from("pasr_news_devices").update({ sandbox: !d.sandbox }).eq("device_id", d.device_id);
    else await db.from("pasr_devices").update({ push_sandbox: !d.sandbox }).eq("device_id", d.device_id);
  }
  return other.ok ? other : r;
}

/** Ongeldige tokens weg, elk uit zijn eigen tabel. */
async function forgetTargets(list: NewsTarget[]) {
  const ids = (src: NewsTarget["src"]) => list.filter((d) => d.src === src).map((d) => d.device_id);
  if (ids("news").length) await db.from("pasr_news_devices").delete().in("device_id", ids("news"));
  if (ids("user").length) await db.from("pasr_user_push").delete().in("device_id", ids("user"));
  if (ids("device").length) await db.rpc("pasr_admin_push_forget", { p_devices: ids("device") });
}

/** Melding aan gebruikers van Pasr over een nieuwe winkel: wie hem aanvroeg plus wie "Nieuwe winkels" aan heeft. */
async function pushNewStore(id: string, name: string, requesters: string[]): Promise<number> {
  if (!apnsConfigured()) return 0;
  const { data, error } = await db.from("pasr_user_push").select("device_id, token, sandbox, user_id, new_stores");
  if (error) throw new Error(error.message);
  const want = new Set(requesters);
  const targets = (data ?? []).filter((d) => d.new_stores || want.has(d.user_id));
  const payload = newStorePayload(name, id);
  const results = await Promise.all(targets.map(async (d) => ({ d, r: await userSend(d, payload) })));
  const invalid = results.filter((x) => !x.r.ok && x.r.invalid).map((x) => x.d.device_id);
  if (invalid.length) await db.from("pasr_user_push").delete().in("device_id", invalid);
  const failed = results.filter((x) => !x.r.ok && !x.r.invalid);
  if (failed.length) console.error("admin", "user_push", (failed[0].r as { error: string }).error, failed.length);
  // Android: wie de winkel aanvroeg (ingelogd op een Android-toestel met push)
  let android = 0;
  if (fcmConfigured() && requesters.length) {
    const { data: devs } = await db.from("pasr_devices").select("device_id, push_token").eq("app", "pasr").eq("push_provider", "fcm")
      .not("push_token", "is", null).in("user_id", requesters.slice(0, 500));
    android = (await fcmToDevices(((devs ?? []) as { device_id: string; push_token: string }[]).map((d) => ({ device_id: d.device_id, token: d.push_token })), payload, "news")).sent;
  }
  return results.filter((x) => x.r.ok).length + android;
}

/** Stempel gezet of kaart vol (seintje van de database): FCM naar Android-toestellen met deze klantcode. */
async function pushMember(code: string, before: number, after: number): Promise<number> {
  if (!fcmConfigured()) return 0;
  const { data: devs, error } = await db.rpc("pasr_admin_member_devices", { p_code: code });
  if (error) throw new Error(error.message);
  const list = (devs ?? []) as { device_id: string; token: string }[];
  if (!list.length) return 0;
  const { data: m } = await db.rpc("pasr_business_member", { p_code: code });
  const info = (m ?? {}) as Record<string, unknown>;
  const card = (info.card ?? {}) as Record<string, unknown>;
  const payload = memberPayload({ name: (info.name ?? card.name) as string, business: (info.business ?? card.business) as string,
    reward: (info.reward ?? card.reward) as string, stamps_total: Number(info.stamps_total ?? card.stamps_total) || null }, code, before, after);
  return (await fcmToDevices(list, payload, "stamps")).sent;
}

// ---- zakelijk 1.1: eigenaarsuitnodiging mailen (SMTP-secrets van group-invite; zonder SMTP: alleen de link) ----
async function mailOwnerInvite(to: unknown, business: { name?: string; city?: string | null }, invite: { link?: string; expires_at?: string | null } | null) {
  const host = env("PASR_SMTP_HOST"), user = env("PASR_SMTP_USER"), pass = Deno.env.get("PASR_SMTP_PASSWORD") ?? "", from = env("PASR_SMTP_FROM");
  if (!host || !user || !pass || !from || typeof to !== "string" || !invite || !okLink(invite.link)) return false;
  try {
    const port = Number(env("PASR_SMTP_PORT") || 465);
    const t = nodemailer.createTransport({ host, port, secure: port === 465, auth: { user, pass } });
    const m = ownerMail(String(business.name ?? "Je zaak"), business.city ?? null, invite.link as string, invite.expires_at ?? null);
    await t.sendMail({ from: `Pasr <${from}>`, to, subject: m.subject, html: m.html, text: m.text });
    return true;
  } catch (e) {
    console.error("admin", "owner_mail", e instanceof Error ? e.name : "?");
    return false;
  }
}

/** Antwoord van pasr_admin_business_save / _owner_invite, met mailed als er een uitnodiging is gemaakt en mailen mag. */
async function withMail(data: Record<string, unknown>, send: boolean) {
  const invite = data.invite as { email?: string; link?: string; expires_at?: string } | null;
  const business = (data.business ?? {}) as { name?: string; city?: string };
  const mailed = send && data.owner === "invite" && invite ? await mailOwnerInvite(invite.email, business, invite) : false;
  return { ...data, mailed, mail_ready: !!(env("PASR_SMTP_HOST") && env("PASR_SMTP_USER") && env("PASR_SMTP_FROM")) };
}

// huisstijl ophalen zonder zaak (nieuw formulier): hoogstens 60 per uur per beheer-instantie
let brandHits: number[] = [];

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
    // een winkel met logo (en kaartontwerp) mag groter zijn
    if (text.length > 700_000) return json({ error: "too_large" }, 413);
    const b = JSON.parse(text || "{}");
    if (!b || typeof b !== "object" || Array.isArray(b)) return json({ error: "bad_json" }, 400);
    if (text.length > 8192 && b.action !== "store_save" && b.action !== "business_card_save") return json({ error: "too_large" }, 413);
    body = b;
  } catch { return json({ error: "bad_json" }, 400); }
  const action = typeof body.action === "string" ? body.action : "";

  try {
    // Seintje van de database: eigen geheim, geen beheer-token.
    if (action === "notify") {
      if (!(await hookOk(req.headers.get("x-pasr-hook")))) return json({ error: "forbidden" }, 403);
      if (body.kind === "retention") {
        return json({ sent: await pushRetention() });
      }
      if (body.kind === "member") {
        const code = typeof body.code === "string" && /^PZ[A-Z0-9]{10,40}$/i.test(body.code) ? body.code.toUpperCase() : null;
        if (!code) return json({ error: "bad_code" }, 400);
        return json({ sent: await pushMember(code, Number(body.before) || 0, Number(body.after) || 0) });
      }
      if (!(KINDS as readonly unknown[]).includes(body.kind)) return json({ error: "bad_kind" }, 400);
      return json({ sent: await notify(body.kind as Kind, body.kind === "store_request" || body.kind === "business" ? body.name : body.reason) });
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
        const [stats, businesses] = await Promise.all([
          db.rpc("pasr_admin_stats", { p_days: q.days, p_offset: q.offset }),
          db.from("pasr_businesses").select("id", { count: "exact", head: true }),
        ]);
        if (stats.error) throw new Error(stats.error.message);
        if (businesses.error) throw new Error(businesses.error.message);
        return json({
          ...(stats.data as Record<string, unknown>),
          business_accounts: businesses.count,
          push_ready: apnsConfigured(),
        });
      }
      case "platforms": {
        // Inzichten iOS/Android (apparaten, versies, accounts per platform, Apple en Google Wallet)
        const q = parseRange(body.days, 0);
        if (!q) return json({ error: "bad_range" }, 400);
        const { data, error } = await db.rpc("pasr_admin_platforms", { p_days: q.days });
        if (error) throw new Error(error.message);
        const { data: push } = await db.rpc("pasr_admin_push_platforms");
        return json({ ...(data as Record<string, unknown>), push: push ?? null, fcm_ready: fcmConfigured(), gwallet_ready: !!(Deno.env.get("GOOGLE_WALLET_ISSUER_ID") && Deno.env.get("GOOGLE_WALLET_SA_JSON")) });
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
      case "user_confirm": {
        // E-mailadres bevestigen (bijv. een review-adres dat geen mail kan ontvangen). Alleen email_confirm, nooit wachtwoorden.
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { data, error } = await db.auth.admin.getUserById(body.id);
        if (error || !data?.user) return json({ error: "not_found" }, 404);
        if (data.user.email_confirmed_at) return json({ error: "already_confirmed" }, 409);
        const { error: ue } = await db.auth.admin.updateUserById(body.id, { email_confirm: true });
        if (ue) return json({ error: "update_failed" }, 502);
        await audit("user_confirm", ipHash, String(body.id));
        return json({ ok: true });
      }
      case "push_register": {
        // beheer-app op Android (FCM): {device_id, fcm_token, prefs}
        if (body.fcm_token !== undefined) {
          const id = cleanDeviceId(body.device_id), tok = cleanFcmToken(body.fcm_token), prefs = cleanPrefs(body.prefs);
          if (!id) return json({ error: "bad_device_id" }, 400);
          if (!tok) return json({ error: "bad_fcm_token" }, 400);
          if (!prefs) return json({ error: "bad_prefs" }, 400);
          await db.from("admin_push_devices").delete().eq("token", tok).neq("device_id", id);
          const { error } = await db.from("admin_push_devices").upsert({ device_id: id, token: tok, platform: "android", sandbox: false,
            provider: "fcm", prefs, updated_at: new Date().toISOString() });
          if (error) throw new Error(error.message);
          await audit("push_register", ipHash, "android");
          return json({ ok: true, push_ready: fcmConfigured() });
        }
        const v = cleanRegister(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const r = v.value;
        // één rij per token: een apparaat dat opnieuw is geïnstalleerd, krijgt een nieuwe id
        await db.from("admin_push_devices").delete().eq("token", r.apns_token).neq("device_id", r.device_id);
        const { error } = await db.from("admin_push_devices").upsert({
          device_id: r.device_id, token: r.apns_token, platform: r.platform, sandbox: r.sandbox, app_build: r.app_build,
          prefs: r.prefs, updated_at: new Date().toISOString(), ...(r.topic ? { topic: r.topic } : {}),
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
        const { data } = await db.from("admin_push_devices").select("device_id, token, sandbox, topic, provider").eq("device_id", id).maybeSingle();
        if (!data) return json({ error: "not_registered" }, 404);
        if (data.provider === "fcm" ? !fcmConfigured() : !apnsConfigured()) return json({ error: data.provider === "fcm" ? "fcm_not_configured" : "apns_not_configured" }, 503);
        if (!data) return json({ error: "not_registered" }, 404);
        const r = await adminSend(data, testPayload());
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
        const { data, error } = await db.from("pasr_stores").select("*").order("updated_at", { ascending: false }).limit(2000);
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
        const { data: store } = await db.from("pasr_stores").select("id, name, domain, aliases").eq("id", id).maybeSingle();
        if (!store) return json({ error: "not_found" }, 404);
        const now = new Date().toISOString();
        const { error } = await db.from("pasr_stores").update({ published: true, published_at: now, updated_at: now }).eq("id", id);
        if (error) throw new Error(error.message);
        const given = (Array.isArray(body.request_ids) ? body.request_ids : []).filter(isUuid).slice(0, 500);
        // ook open aanvragen voor deze winkel die niet zijn meegegeven (zelfde website of naam): die vragers horen het ook
        const { data: open } = await db.from("pasr_store_requests").select("id, name, website").eq("status", "open").limit(1000);
        const matched = (open ?? []).filter((r) => requestMatches(store, r)).map((r) => r.id as string);
        const ids = [...new Set([...given, ...matched])].slice(0, 500);
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
      case "balance_pages": {
        const { data, error } = await db.from("pasr_balance_pages").select("store_id, url, updated_at").order("store_id");
        if (error) throw new Error(error.message);
        return json({ pages: data ?? [] });
      }
      case "balance_page_save": {
        const v = cleanBalancePage(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const { error } = await db.from("pasr_balance_pages").upsert({ ...v.value, updated_at: new Date().toISOString() });
        if (error) throw new Error(error.message);
        await audit("balance_page_save", ipHash, v.value.store_id);
        return json({ ok: true, ...v.value });
      }
      case "balance_page_delete": {
        const id = typeof body.store_id === "string" ? body.store_id : "";
        const { error } = await db.from("pasr_balance_pages").delete().eq("store_id", id);
        if (error) throw new Error(error.message);
        await audit("balance_page_delete", ipHash, id);
        return json({ ok: true });
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
      case "news_overview": {
        const [{ data, error }, { data: everyone, error: ee }] = await Promise.all([
          db.rpc("pasr_admin_news_overview"),
          db.rpc("pasr_admin_push_everyone_counts"),
        ]);
        if (error) throw new Error(error.message);
        const { data: history, error: he } = await db.from("pasr_news_campaigns")
          .select("id, title, body, audience, store_id, platform, app, url, recipients, sent, failed, created_at")
          .order("created_at", { ascending: false }).limit(20);
        if (he) throw new Error(he.message);
        return json({ ...(data as Record<string, unknown>), everyone: ee ? null : everyone, history: history ?? [],
          push_ready: pushConfigured(), apns_ready: apnsConfigured(), fcm_ready: fcmConfigured() });
      }
      case "news_count": {
        const a = cleanAudience(body);
        if (!a.ok) return json({ error: a.error }, 400);
        const t = await newsTargets(a);
        return json({ count: t.ios.length + t.android.length, ios: t.ios.length, android: t.android.length,
          pasr: t.ios.filter((d) => d.app === "pasr").length + t.android.filter((d) => d.app === "pasr").length,
          zakelijk: t.ios.filter((d) => d.app === "zakelijk").length + t.android.filter((d) => d.app === "zakelijk").length,
          apns_ready: apnsConfigured(), fcm_ready: fcmConfigured() });
      }
      case "news_send": {
        const v = cleanNews(body);
        if (!v.ok) return json({ error: v.error }, 400);
        if (!pushConfigured()) return json({ error: "apns_not_configured" }, 503);
        const n = v.value;
        // dubbel versturen voorkomen: hetzelfde bericht naar dezelfde doelgroep kort na elkaar (dubbele tik, twee tabbladen)
        const fingerprint = newsFingerprint(n);
        const { data: dup } = await db.from("pasr_news_campaigns").select("id").eq("fingerprint", fingerprint)
          .gte("created_at", new Date(Date.now() - DUPLICATE_WINDOW_MS).toISOString()).limit(1);
        if ((dup ?? []).length) return json({ error: "duplicate" }, 409);
        const t = await newsTargets(n);
        const list = apnsConfigured() ? t.ios : [];
        const androidList = fcmConfigured() ? t.android : [];
        const { data: camp, error: ce } = await db.from("pasr_news_campaigns")
          .insert({ title: n.title, body: n.body, audience: n.audience, store_id: n.store, platform: n.platform, app: n.app,
            url: n.url, fingerprint, recipients: list.length + androidList.length }).select("id").single();
        if (ce) throw new Error(ce.message);
        let sent = 0, failed = 0;
        const invalid: NewsTarget[] = [];
        for (const part of chunks(list, 100)) {
          const res = await Promise.all(part.map(async (d) => ({ d, r: await newsIosSend(d, newsPayload(n, camp.id, d.app)) })));
          for (const x of res) {
            if (x.r.ok) sent++;
            else { failed++; if (x.r.invalid) invalid.push(x.d); }
          }
        }
        await forgetTargets(invalid);
        const iosSent = sent;
        let androidSent = 0;
        for (const app of ["pasr", "zakelijk"] as const) {
          const part = androidList.filter((d) => d.app === app);
          if (!part.length) continue;
          const a = await fcmToDevices(part, newsPayload(n, camp.id, app), app === "zakelijk" ? "zakelijk" : "news");
          androidSent += a.sent; sent += a.sent; failed += a.failed;
        }
        await db.from("pasr_news_campaigns").update({ sent, failed }).eq("id", camp.id);
        await audit("news_send", ipHash, `${n.audience}${n.store ? ":" + n.store : ""} ${n.app}/${n.platform}${n.url ? " +url" : ""} ${sent}/${list.length + androidList.length}`);
        return json({ id: camp.id, recipients: list.length + androidList.length, sent, failed,
          ios: { recipients: list.length, sent: iosSent }, android: { recipients: androidList.length, sent: androidSent } });
      }
      case "businesses": {
        const { data, error } = await db.rpc("pasr_admin_businesses");
        if (error) throw new Error(error.message);
        return json({ businesses: data ?? [] });
      }
      case "business_status": {
        const v = cleanBusinessStatus(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const { data, error } = await db.rpc("pasr_admin_business_status", { p_business: v.id, p_status: v.status });
        if (error) return json({ error: /not_found/.test(error.message) ? "not_found" : "server_error" }, /not_found/.test(error.message) ? 404 : 500);
        await audit("business_status", ipHash, `${v.id} ${v.status}`);
        return json({ business: data });
      }
      case "business_detail": {
        const v = cleanBusinessDetail(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const { data, error } = await db.rpc("pasr_admin_business_detail", { p_business: v.id, p_limit: v.limit, p_days: v.days });
        if (error) throw new Error(error.message);
        if (!data) return json({ error: "not_found" }, 404);
        return json(data);
      }
      case "business_offers": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { data, error } = await db.rpc("pasr_admin_business_offers", { p_business: body.id });
        if (error) throw new Error(error.message);
        return json(data ?? {});
      }
      case "business_offer_disable": {
        const kind = String(body.kind ?? "");
        if (!["coupon", "promo_code", "campaign"].includes(kind) || !isUuid(body.id)) return json({ error: "bad_request" }, 400);
        const { error } = await db.rpc("pasr_admin_business_offer_disable", { p_kind: kind, p_id: body.id });
        if (error) return json({ error: /not_found/.test(error.message) ? "not_found" : "server_error" }, /not_found/.test(error.message) ? 404 : 500);
        await audit("business_offer_disable", ipHash, `${kind} ${body.id}`);
        return json({ ok: true });
      }
      case "business_settings": {
        const v = cleanBusinessSettings(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const { data, error } = await db.rpc("pasr_admin_business_settings", { p_business: v.id, p_settings: v.settings });
        if (error) return json({ error: /not_found/.test(error.message) ? "not_found" : "bad_settings" }, /not_found/.test(error.message) ? 404 : 400);
        await audit("business_settings", ipHash, `${v.id} ${JSON.stringify(v.settings)}`);
        return json({ business: data });
      }
      case "business_staff_revoke": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { error } = await db.rpc("pasr_admin_business_staff_revoke", { p_staff: body.id });
        if (error) return json({ error: /not_found/.test(error.message) ? "not_found" : "server_error" }, /not_found/.test(error.message) ? 404 : 500);
        await audit("business_staff_revoke", ipHash, String(body.id));
        return json({ ok: true });
      }
      case "business_create":
      case "business_update": {
        const v = cleanBusinessInput(body, action === "business_create");
        if (!v.ok) return json({ error: v.error }, 400);
        const { data, error } = await db.rpc("pasr_admin_business_save", { p_business: v.value });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        const d = data as Record<string, unknown>;
        await audit(action, ipHash, `${(d.business as { id?: string })?.id ?? v.value.id ?? "?"} owner=${d.owner}`);
        // nieuw: standaard mailen; bewerken: alleen als er een nieuwe uitnodiging is en send niet false is
        return json(await withMail(d, body.send !== false && (action === "business_create" || d.owner === "invite")));
      }
      case "business_owner_invite": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
        if (email.length > 200 || (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))) return json({ error: "bad_email" }, 400);
        const { data, error } = await db.rpc("pasr_admin_owner_invite", { p_business: body.id, p_email: email || null });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        const d = data as Record<string, unknown>;
        await audit("business_owner_invite", ipHash, `${body.id} owner=${d.owner}`);
        return json(await withMail(d, body.send !== false));
      }
      case "business_owner_confirm": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { data: biz, error: be } = await db.from("pasr_businesses").select("id, owner, email").eq("id", body.id).maybeSingle();
        if (be) throw new Error(be.message);
        if (!biz) return json({ error: "not_found" }, 404);
        if (biz.owner) return json({ error: "has_owner" }, 409);
        const { data: uid } = await db.rpc("pasr_admin_user_id", { p_email: String(biz.email ?? "") });
        if (typeof uid !== "string") return json({ error: "not_found" }, 404);
        const { data: u, error: ge } = await db.auth.admin.getUserById(uid);
        if (ge || !u?.user) return json({ error: "not_found" }, 404);
        if (!u.user.email_confirmed_at) {
          const { error: ue } = await db.auth.admin.updateUserById(uid, { email_confirm: true });
          if (ue) return json({ error: "update_failed" }, 502);
          await audit("user_confirm", ipHash, uid);
        }
        const { data, error } = await db.rpc("pasr_admin_owner_invite", { p_business: body.id, p_email: null });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        await db.rpc("pasr_admin_event", { p_business: body.id, p_card: null, p_note: "E-mailadres van de eigenaar bevestigd door het beheer" });
        await audit("business_owner_confirm", ipHash, String(body.id));
        return json({ ...(data as Record<string, unknown>), mailed: false });
      }
      case "business_card_save": {
        const v = cleanCardInput(body);
        if (!v.ok) return json({ error: v.error }, 400);
        const { data, error } = await db.rpc("pasr_admin_card_save", { p_business: v.business, p_card: v.card });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        await audit("business_card_save", ipHash, `${v.business} ${(data as { id?: string })?.id ?? ""}`);
        return json({ card: data });
      }
      case "business_card_publish": {
        if (!isUuid(body.id) || typeof body.published !== "boolean") return json({ error: "bad_request" }, 400);
        const { data, error } = await db.rpc("pasr_admin_card_publish", { p_card: body.id, p_published: body.published });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        await audit("business_card_publish", ipHash, `${body.id} ${body.published}`);
        return json({ card: data });
      }
      case "business_card_delete": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { data, error } = await db.rpc("pasr_admin_card_delete", { p_card: body.id });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        await audit("business_card_delete", ipHash, String(body.id));
        return json(data);
      }
      case "business_test_member": {
        if (!isUuid(body.card_id)) return json({ error: "bad_id" }, 400);
        const { data, error } = await db.rpc("pasr_admin_test_member_create", { p_card: body.card_id });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        await audit("business_test_member", ipHash, String(body.card_id));
        return json({ member: data });
      }
      case "business_test_member_reset":
      case "business_test_member_delete": {
        if (!isUuid(body.id)) return json({ error: "bad_id" }, 400);
        const { data, error } = await db.rpc("pasr_admin_test_member", { p_member: body.id, p_action: action.endsWith("reset") ? "reset" : "delete" });
        if (error) { const m = dbError(error); if (m) return json({ error: m.error }, m.status); throw new Error(error.message); }
        await audit(action, ipHash, String(body.id));
        return json(data);
      }
      case "business_brand": {
        // Zelfde als de functie business-brand, maar met beheerrechten: elke zaak, of alleen een url (nieuw formulier).
        let website: string | null = null, bid: string | null = null;
        if (body.business_id !== undefined && body.business_id !== null && body.business_id !== "") {
          if (!isUuid(body.business_id)) return json({ error: "bad_id" }, 400);
          const { data: biz, error: be } = await db.from("pasr_businesses").select("id, website").eq("id", body.business_id).maybeSingle();
          if (be) throw new Error(be.message);
          if (!biz) return json({ error: "not_found" }, 404);
          bid = biz.id; website = biz.website;
        }
        const raw = typeof body.url === "string" && body.url.trim() ? body.url : website;
        if (!raw) return json({ error: "no_website" }, 400);
        const site = cleanUrl(raw);
        if (!site) return json({ error: "bad_url" }, 400);
        if (bid) {
          const { data: wait, error: re } = await db.rpc("pasr_business_brand_hit", { p_business: bid, p_per_hour: 60 });
          if (re) throw new Error(re.message);
          if (Number(wait) > 0) return json({ error: "rate_limited", retry_after: Number(wait) }, 429, { "Retry-After": String(wait) });
        } else {
          const now = Date.now();
          brandHits = brandHits.filter((t) => t > now - 3600_000);
          if (brandHits.length >= 60) return json({ error: "rate_limited", retry_after: 600 }, 429, { "Retry-After": "600" });
          brandHits.push(now);
        }
        const r = await brand(site);
        if (!r || (!r.logo && !r.color && !r.name)) return json({ error: "unreachable" }, 422);
        await audit("business_brand", ipHash, `${bid ?? "-"} ${r.domain}`);
        return json(r);
      }
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    console.error("admin", action || "?", e instanceof Error ? e.message : "?");
    return json({ error: "server_error" }, 500);
  }
});
