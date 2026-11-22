// Pasr Zakelijk: functie business-brand. Haalt van de website van een zaak de naam, het logo en de kleur, zodat een
// nieuwe stempelkaart meteen in de huisstijl staat (app Pasr Zakelijk en pasr.nl/zakelijk/dashboard).
//
// POST /functions/v1/business-brand  (Authorization: Bearer <access token van de ondernemer>, apikey: publishable key)
//   {business_id} | {business_id, url} | {url}
//   -> 200 {name, logo (base64 PNG, max 512x512) | null, color "#RRGGBB" | null, text_color, source_url, domain}
//   -> 401 not_signed_in | 403 not_owner | 400 no_website / bad_url | 429 rate_limited (+retry_after) | 422 unreachable
//
// Veiligheid (SSRF): alleen http(s) op poort 80/443, hostnaam moet naar publieke IP's wijzen (DNS gecontroleerd vóór
// elke request en elke redirect, hoogstens 3 redirects, zelf gevolgd), 8 seconden per bestand, hoogstens 2 MB per
// bestand, geen cookies of inlog mee, 20 keer per zaak per uur. Nooit tokens of e-mailadressen loggen.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { BRAND_PER_HOUR, cleanUrl } from "./brand.ts";
import { brand } from "./fetch.ts";

const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { autoRefreshToken: false, persistSession: false } });

const ORIGIN_OK = /^https:\/\/(www\.)?pasr\.nl$|^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function cors(req: Request): Record<string, string> {
  const o = req.headers.get("Origin") ?? "";
  return {
    ...(ORIGIN_OK.test(o) ? { "Access-Control-Allow-Origin": o } : {}),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

Deno.serve(async (req) => {
  const c = cors(req);
  const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), { status, headers: { ...c, ...extra, "Content-Type": "application/json", "Cache-Control": "no-store" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: c });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const origin = req.headers.get("Origin");
  if (origin && !ORIGIN_OK.test(origin)) return json({ error: "forbidden" }, 403);

  let body: Record<string, unknown>;
  try {
    const t = await req.text();
    if (t.length > 2000) return json({ error: "too_large" }, 413);
    body = JSON.parse(t || "{}");
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
  } catch { return json({ error: "bad_json" }, 400); }

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "not_signed_in" }, 401);
    const { data: who, error: ue } = await db.auth.getUser(jwt);
    if (ue || !who?.user?.id) return json({ error: "not_signed_in" }, 401);
    const uid = who.user.id;

    // de zaak: opgegeven (moet van jou zijn) of je eigen zaak
    const bid = typeof body.business_id === "string" ? body.business_id : null;
    if (bid !== null && !/^[0-9a-f-]{36}$/i.test(bid)) return json({ error: "bad_business" }, 400);
    let q = db.from("pasr_businesses").select("id, owner, website, status").eq("owner", uid);
    if (bid) q = q.eq("id", bid);
    const { data: biz, error: be } = await q.maybeSingle();
    if (be) throw new Error(be.message);
    if (!biz) return json({ error: "not_owner" }, 403);
    if (biz.status === "blocked") return json({ error: "not_owner" }, 403);

    const raw = typeof body.url === "string" && body.url.trim() ? body.url : biz.website;
    if (!raw) return json({ error: "no_website" }, 400);
    const site = cleanUrl(raw);
    if (!site) return json({ error: "bad_url" }, 400);

    const { data: wait, error: re } = await db.rpc("pasr_business_brand_hit", { p_business: biz.id, p_per_hour: BRAND_PER_HOUR });
    if (re) throw new Error(re.message);
    if (Number(wait) > 0) return json({ error: "rate_limited", retry_after: Number(wait) }, 429, { "Retry-After": String(wait) });

    const r = await brand(site);
    if (!r || (!r.logo && !r.color && !r.name)) return json({ error: "unreachable" }, 422);
    return json(r);
  } catch (e) {
    console.error("business-brand", e instanceof Error ? e.message : "?");
    return json({ error: "server_error" }, 500);
  }
});
