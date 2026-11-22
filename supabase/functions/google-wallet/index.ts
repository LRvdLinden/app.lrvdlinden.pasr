// Pasr → Google Wallet. Maakt voor één kaart een "Opslaan in Google Wallet"-link en werkt die pas later bij.
//
// De app (Pasr voor Android) stuurt de kaart; deze functie maakt of wijzigt het genericObject bij Google (Wallet
// Objects API, met het service-account) en geeft een link https://pay.google.com/gp/v/save/<JWT> terug. Daarin staat
// alleen de verwijzing naar het object, dus de link blijft klein. Bij elke wijziging stuurt de app dezelfde kaart met
// dezelfde sleutel (key) opnieuw: dan wordt het object bijgewerkt en ziet de gebruiker de nieuwe stand in Google Wallet.
// Een zakelijke stempelkaart werkt vanzelf bij: na elke stempel stuurt de database (trigger pasr_gwallet_business)
// {action:"business", code} met de kop x-pasr-hook.
//
// Acties (POST, kop apikey = publishable key):
//   {action:"status"}                       → {available}
//   {action:"save", card:{…}, key?}         → {url, object_id, key}
//   {action:"remove", id, key}              → {ok}   (kaart verwijderd: pas wordt inactief)
//   {action:"business", code} + x-pasr-hook → {updated}
//   GET ?logo=<object_id>                   → het logo (PNG/JPEG) voor Google
//
// Function secrets (zet Léon zelf, zie README):
//   GOOGLE_WALLET_ISSUER_ID   het issuer-id uit de Google Pay & Wallet Console (cijfers)
//   GOOGLE_WALLET_SA_JSON     de JSON-sleutel van het service-account (met rechten in de console)
//   PASR_PUBLISHABLE_KEY      (bestaat al, van wallet-pass) alleen de Pasr-apps mogen passen maken
import {
  cleanLogo, type GCard, genericObject, imageType, importPrivateKey, isKey, isUuid, objectId, sameText, saveClaims,
  sha256hex, signJwt,
} from "./gwallet.ts";

const API = "https://walletobjects.googleapis.com/walletobjects/v1";
const FALLBACK_LOGO = "https://pasr.nl/assets/icon-512.png";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const hits = new Map<string, number[]>();

type SA = { client_email: string; private_key: string };
let sa: SA | null = null;
let saKey: CryptoKey | null = null;
let token: { value: string; until: number } | null = null;
let classReady = false;
let hookSecret: string | null = null;
let hookUntil = 0;

function issuer(): string | null {
  const v = (Deno.env.get("GOOGLE_WALLET_ISSUER_ID") ?? "").trim();
  return /^\d{5,30}$/.test(v) ? v : null;
}

function account(): SA | null {
  if (sa) return sa;
  try {
    const raw = Deno.env.get("GOOGLE_WALLET_SA_JSON") ?? "";
    const text = raw.trim().startsWith("{") ? raw : atob(raw.trim());
    const j = JSON.parse(text);
    if (typeof j.client_email === "string" && typeof j.private_key === "string") sa = { client_email: j.client_email, private_key: j.private_key };
  } catch {
    sa = null;
  }
  return sa;
}

const available = () => !!(issuer() && account());

async function signer(): Promise<CryptoKey> {
  if (!saKey) saKey = await importPrivateKey(account()!.private_key);
  return saKey;
}

/** OAuth-token van het service-account (scope wallet_object.issuer), 50 minuten bewaard. */
async function accessToken(): Promise<string> {
  if (token && Date.now() < token.until) return token.value;
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt({
    iss: account()!.client_email, scope: "https://www.googleapis.com/auth/wallet_object.issuer",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }, await signer());
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`oauth ${res.status}`);
  }
  const j = await res.json();
  token = { value: String(j.access_token), until: Date.now() + 50 * 60_000 };
  return token.value;
}

async function google(method: string, path: string, body?: unknown): Promise<Response> {
  return await fetch(`${API}/${path}`, {
    method,
    headers: { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
}

/** De ene klasse voor alle Pasr-passen (genericClass bestaat met alleen een id). */
async function ensureClass() {
  if (classReady) return;
  const id = `${issuer()}.pasr_generic`;
  const get = await google("GET", `genericClass/${encodeURIComponent(id)}`);
  await get.body?.cancel();
  if (get.status === 404) {
    const made = await google("POST", "genericClass", { id });
    await made.body?.cancel();
    if (!made.ok && made.status !== 409) throw new Error(`class ${made.status}`);
  } else if (!get.ok) {
    throw new Error(`class ${get.status}`);
  }
  classReady = true;
}

/** Object maken of (bestaat het al) helemaal vervangen. */
async function upsertObject(obj: Record<string, unknown>): Promise<boolean> {
  const id = String(obj.id);
  const put = await google("PUT", `genericObject/${encodeURIComponent(id)}`, obj);
  await put.body?.cancel();
  if (put.ok) return false;
  if (put.status !== 404) throw new Error(`object ${put.status}`);
  const made = await google("POST", "genericObject", obj);
  await made.body?.cancel();
  if (!made.ok && made.status !== 409) throw new Error(`object ${made.status}`);
  return true;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const url = new URL(req.url);

  // Logo voor Google (die haalt het zelf op): alleen wat de app bij dit object meestuurde.
  if (req.method === "GET") {
    const id = url.searchParams.get("logo") ?? "";
    if (!/^[0-9A-Za-z._-]{3,200}$/.test(id) || !dbReady()) return new Response(null, { status: 404, headers: cors });
    try {
      const rows = await rest(`pasr_gwallet_objects?object_id=eq.${enc(id)}&select=logo`) as { logo: string | null }[];
      const b64 = rows[0]?.logo;
      if (!b64) return Response.redirect(FALLBACK_LOGO, 302);
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      const type = imageType(bytes);
      if (!type) return Response.redirect(FALLBACK_LOGO, 302);
      return new Response(bytes, { headers: { ...cors, "Content-Type": type, "Cache-Control": "public, max-age=3600" } });
    } catch {
      return new Response(null, { status: 404, headers: cors });
    }
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    const text = await req.text();
    if (text.length > 600_000) return json({ error: "too_large" }, 413);
    body = JSON.parse(text);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const action = typeof body?.action === "string" ? body.action : "save";

  // Seintje van de database: een zaak zette een stempel
  if (action === "business") {
    if (!(await hookOk(req.headers.get("x-pasr-hook")))) return json({ error: "forbidden" }, 403);
    const code = body.code;
    if (typeof code !== "string" || !code || code.length > 120) return json({ error: "bad_request" }, 400);
    if (!available()) return json({ updated: 0 });
    try {
      return json({ updated: await kickBusiness(code) });
    } catch (e) {
      console.error("google-wallet business:", (e as Error).message);
      return json({ error: "failed" }, 502);
    }
  }

  const pk = Deno.env.get("PASR_PUBLISHABLE_KEY");
  if (pk && req.headers.get("apikey") !== pk) return json({ error: "forbidden" }, 403);

  if (action === "status") return json({ available: available() });
  if (!available()) return json({ error: "not_configured", available: false }, 503);

  // Rem per IP: 30 per 10 minuten
  const ip = (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",").pop() ?? "?").trim();
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 600_000);
  if (recent.length >= 30) return json({ error: "rate_limited" }, 429);
  hits.set(ip, [...recent, now]);

  try {
    if (action === "remove") {
      if (!isUuid(body.id) || !isKey(body.key)) return json({ error: "bad_request" }, 400);
      const id = objectId(issuer()!, body.id);
      const row = await objectRow(id);
      if (!row) return json({ ok: true });
      if (!sameText(row.key_hash, await sha256hex(String(body.key).toLowerCase()))) return json({ error: "forbidden" }, 403);
      const res = await google("PATCH", `genericObject/${encodeURIComponent(id)}`, { state: "INACTIVE" });
      await res.body?.cancel();
      await rest(`pasr_gwallet_objects?object_id=eq.${enc(id)}`, { method: "DELETE", headers: { Prefer: "return=minimal" } });
      return json({ ok: true });
    }
    if (action !== "save") return json({ error: "bad_request" }, 400);

    const card = body.card as GCard;
    if (!card || !isUuid(card.id) || typeof card.name !== "string" || !card.name.trim()) return json({ error: "bad_request" }, 400);
    if (String(card.number ?? "").length > 200) return json({ error: "bad_request" }, 400);
    const iss = issuer()!;
    const id = objectId(iss, card.id);
    const row = await objectRow(id);
    let key = isKey(body.key) ? String(body.key).toLowerCase() : null;
    if (row) {
      if (!key || !sameText(row.key_hash, await sha256hex(key))) return json({ error: "forbidden" }, 403);
    } else {
      key = key ?? Array.from(crypto.getRandomValues(new Uint8Array(24)), (b) => b.toString(16).padStart(2, "0")).join("");
    }
    const d = card.details ?? {};
    const member = card.kind === "stamps" && d.issuer === "business" && typeof d.memberCode === "string" ? d.memberCode.slice(0, 120) : null;
    const server = member ? await memberStand(member) : null;
    const logo = cleanLogo(card.logo);
    const logoUri = logo ? `${selfUrl()}?logo=${encodeURIComponent(id)}` : FALLBACK_LOGO;

    // eerst de rij (met logo), zodat Google het logo kan ophalen zodra het object er is
    await rest("pasr_gwallet_objects?on_conflict=object_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        object_id: id, key_hash: await sha256hex(key), kind: cleanKind(card.kind), member_code: member, logo,
        updated_at: new Date().toISOString(),
      }),
    });
    await ensureClass();
    const created = await upsertObject(genericObject(iss, card, logoUri, server));
    if (created || !row) count();
    const jwt = await signJwt(saveClaims(account()!.client_email, id), await signer());
    return json({ url: `https://pay.google.com/gp/v/save/${jwt}`, object_id: id, key });
  } catch (e) {
    console.error("google-wallet:", (e as Error).message);
    return json({ error: "failed" }, 502);
  }
});

const cleanKind = (k: unknown) =>
  typeof k === "string" && ["loyalty", "voucher", "code", "ticket", "subscription", "stamps"].includes(k) ? k : "loyalty";

function selfUrl(): string {
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  return `${base}/functions/v1/google-wallet`;
}

async function objectRow(id: string): Promise<{ key_hash: string } | null> {
  const rows = await rest(`pasr_gwallet_objects?object_id=eq.${enc(id)}&select=key_hash`) as { key_hash: string }[];
  return rows[0] ?? null;
}

async function memberStand(code: string): Promise<{ total?: number; count?: number; reward?: string } | null> {
  try {
    const j = await rest("rpc/pasr_business_member", { method: "POST", body: JSON.stringify({ p_code: code }) }) as Record<string, unknown>;
    if (!j || j.status !== "ok") return null;
    const n = (v: unknown) => (typeof v === "number" ? v : undefined);
    return { total: n(j.stamps_total), count: n(j.stamps_count), reward: typeof j.reward === "string" ? j.reward : undefined };
  } catch {
    return null;
  }
}

/** Alle Google-passen van deze klantcode: header en regels opnieuw zetten. */
async function kickBusiness(code: string): Promise<number> {
  if (!dbReady()) return 0;
  const rows = await rest(`pasr_gwallet_objects?member_code=eq.${enc(code)}&select=object_id`) as { object_id: string }[];
  if (!rows.length) return 0;
  const s = await memberStand(code);
  if (!s) return 0;
  let n = 0;
  for (const row of rows) {
    const res = await google("GET", `genericObject/${encodeURIComponent(row.object_id)}`);
    if (!res.ok) { await res.body?.cancel(); continue; }
    const obj = await res.json() as Record<string, unknown>;
    const title = (obj.cardTitle as { defaultValue?: { value?: string } } | undefined)?.defaultValue?.value ?? "Stempelkaart";
    const card: GCard = { id: "00000000-0000-4000-8000-000000000000", name: title, kind: "stamps",
      details: { stampsTotal: s.total, stampsCount: s.count, reward: s.reward, issuer: "business", memberCode: code } };
    const fresh = genericObject(issuer()!, card, "", s);
    const patch = await google("PATCH", `genericObject/${encodeURIComponent(row.object_id)}`, {
      header: fresh.header, textModulesData: fresh.textModulesData,
    });
    await patch.body?.cancel();
    if (patch.ok) {
      n++;
      await rest(`pasr_gwallet_objects?object_id=eq.${enc(row.object_id)}`, {
        method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ updated_at: new Date().toISOString() }),
      });
    }
  }
  return n;
}

function dbReady(): boolean {
  return !!(Deno.env.get("SUPABASE_URL") && Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
}

async function hookOk(given: string | null): Promise<boolean> {
  if (!given || given.length > 200 || !dbReady()) return false;
  if (!hookSecret || Date.now() > hookUntil) {
    try {
      const rows = await rest("pasr_secret?id=eq.1&select=hook_secret") as { hook_secret: string | null }[];
      if (!rows[0]?.hook_secret) return false;
      hookSecret = String(rows[0].hook_secret);
      hookUntil = Date.now() + 300_000;
    } catch {
      return false;
    }
  }
  return sameText(given, hookSecret);
}

const enc = (s: string) => encodeURIComponent(s);

async function rest(path: string, init: RequestInit = {}): Promise<unknown> {
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("db not configured");
  const res = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", ...(init.headers ?? {}) },
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`db ${res.status}`);
  }
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

function count() {
  rest("rpc/pasr_count_gwallet", { method: "POST", body: "{}" }).catch(() => {});
}

function json(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
