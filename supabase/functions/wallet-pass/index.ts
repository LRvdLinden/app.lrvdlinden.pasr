// Pasr → Apple Wallet. Builds a signed .pkpass for one card, on request of the app.
//
// The app sends the card (store, number, code type, colour, logo, nearby branches); this function turns it into
// a Wallet pass, signs it with Pasr's pass certificate and sends it straight back. A counter of passes per day goes
// up (pasr_daily.wallet, for Pasr Beheer).
//
// Sinds 1.0.3 werkt een pas ook vanzelf bij (Apple PassKit-webservice): de app stuurt een token mee; dat komt als
// authenticationToken in de pas, met webServiceURL = deze functie. De kaartgegevens worden dan bewaard in
// pasr_wallet_passes, versleuteld met een sleutel uit dat token (alleen het apparaat met de pas kent het). Wallet
// meldt zich aan (registrations), en als de kaart verandert (de app stuurt action "update" of push: true, of een
// zaak zet een stempel: action "business" vanuit de database) krijgt elk apparaat een lege push van Apple (APNs, met
// het pass-certificaat) en haalt Wallet de nieuwe pas op. Zonder token (oudere Pasr): zoals vroeger, niets bewaard.
//
// Function secrets (set by the workflow Backend from the GitHub secrets):
//   PASS_TYPE_ID         e.g. pass.nl.lrvdlinden.pasr
//   PASS_TEAM_ID         EU3UY476T6
//   PASS_CERT_P12        the pass certificate + private key as .p12, base64
//   PASS_CERT_PASSWORD   password of that .p12
//   PASR_PUBLISHABLE_KEY the app's publishable key (only the Pasr app may ask for passes)
import forge from "npm:node-forge@1.3.1";
import { zipSync, strToU8 } from "npm:fflate@0.8.2";
import { ICONS } from "./icons.ts";
import {
  applePassToken, businessStand, type Card, isSerial, isToken, open, route, type Route, sameText, seal, stampFields,
  stored, tagFor, ticketPass, tokenHash,
} from "./passkit.ts";

const WWDR_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer";
let wwdr: forge.pki.Certificate | null = null;
let signer: { cert: forge.pki.Certificate; key: forge.pki.PrivateKey } | null = null;
const hits = new Map<string, number[]>();

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};


Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  // PassKit-webservice: Wallet zelf, met "Authorization: ApplePass <token>" (geen apikey)
  const r = route(req.method, new URL(req.url).pathname);
  if (r) {
    try {
      return await webService(req, r);
    } catch (e) {
      console.error("wallet-pass ws:", (e as Error).message);
      return new Response(null, { status: 500 });
    }
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let card: Card;
  try {
    const text = await req.text();
    if (text.length > 1_000_000) return json({ error: "too_large" }, 413);
    card = JSON.parse(text);
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  // Seintje van de database: een zaak zette een stempel (trigger op pasr_business_members)
  if (card?.action === "business") {
    if (!(await hookOk(req.headers.get("x-pasr-hook")))) return json({ error: "forbidden" }, 403);
    const code = (card as unknown as { code?: unknown }).code;
    if (typeof code !== "string" || !code || code.length > 120) return json({ error: "bad_request" }, 400);
    return json({ pushed: await kickBusiness(code) });
  }

  const key = Deno.env.get("PASR_PUBLISHABLE_KEY");
  if (key && req.headers.get("apikey") !== key) return json({ error: "forbidden" }, 403);

  // Light rate limit per IP: 30 passes per 10 minutes (bijwerken telt half zo zwaar)
  const ip = (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",").pop() ?? "?").trim();
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 600_000);
  if (recent.length >= (card?.action === "update" ? 60 : 30)) return json({ error: "rate_limited" }, 429);
  hits.set(ip, [...recent, now]);

  const stampCard = card?.kind === "stamps";
  if (!card?.id || !isSerial(card.id) || !card?.name || (!card?.number && !stampCard) || String(card.number ?? "").length > 200) {
    return json({ error: "bad_request" }, 400);
  }
  card.number = String(card.number ?? "");
  const token = isToken(card.token) ? card.token.toLowerCase() : null;

  try {
    // Alleen bijwerken (de pas staat op een ander apparaat): bewaren en inseinen, geen pas terug.
    if (card.action === "update") {
      if (!token || !dbReady()) return json({ error: "bad_request" }, 400);
      const row = await passRow(card.id);
      if (!row) return json({ error: "unknown_pass" }, 404);
      if (!sameText(row.token_hash, await tokenHash(token))) return json({ error: "forbidden" }, 403);
      await savePass(card, token);
      return json({ ok: true, pushed: await pushSerial(card.id) });
    }

    const ws = token && dbReady() ? { url: webServiceURL(), token } : null;
    const pkpass = await buildPass(card, ws);
    if (ws) {
      try {
        await savePass(card, token!);
        if (card.push) pushSerial(card.id).catch(() => {});
      } catch (e) {
        // bewaren mislukt: de pas werkt gewoon, alleen bijwerken vanaf de server niet
        console.error("wallet-pass save:", (e as Error).message);
      }
    }
    countPass();
    return new Response(pkpass as unknown as BodyInit, {
      headers: {
        ...cors,
        "Content-Type": "application/vnd.apple.pkpass",
        "Content-Disposition": `attachment; filename="pasr.pkpass"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    console.error("wallet-pass:", (e as Error).message);
    return json({ error: "unavailable" }, 503);
  }
});

// ---- PassKit-webservice ---------------------------------------------------------------------------------------

const passTypeId = () => Deno.env.get("PASS_TYPE_ID") ?? "pass.nl.lrvdlinden.pasr";
const webServiceURL = () =>
  Deno.env.get("PASR_WALLET_URL") ?? `${(Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "")}/functions/v1/wallet-pass`;
const dbReady = () => !!(Deno.env.get("SUPABASE_URL") && Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

async function webService(req: Request, r: Route): Promise<Response> {
  if (r.kind === "log") {
    // Wallet meldt fouten: kort en zonder tokens in het logboek
    try {
      const body = await req.json();
      const logs = Array.isArray(body?.logs) ? body.logs : [];
      for (const l of logs.slice(0, 5)) {
        console.warn("wallet log:", String(l).replace(/[0-9a-f]{32,}/gi, "…").slice(0, 300));
      }
    } catch { /* niets */ }
    return new Response(null, { status: 200 });
  }
  if (r.passType !== passTypeId() || !dbReady()) return new Response(null, { status: 404 });

  if (r.kind === "serials") {
    const since = Number(new URL(req.url).searchParams.get("passesUpdatedSince") ?? "0") || 0;
    const regs = await rest(`pasr_wallet_registrations?device=eq.${enc(r.device)}&select=serial`);
    const serials = (regs as { serial: string }[]).map((x) => x.serial);
    if (!serials.length) return new Response(null, { status: 204 });
    const rows = await rest(`pasr_wallet_passes?serial=in.(${serials.map(enc).join(",")})&select=serial,updated_at`) as
      { serial: string; updated_at: string }[];
    const changed = rows.filter((x) => Number(tagFor(x.updated_at)) > since);
    if (!changed.length) return new Response(null, { status: 204 });
    const last = Math.max(...rows.map((x) => Number(tagFor(x.updated_at))));
    return new Response(JSON.stringify({ serialNumbers: changed.map((x) => x.serial), lastUpdated: String(last) }),
      { headers: { "Content-Type": "application/json" } });
  }

  // De andere verzoeken gaan over één pas en hebben het token nodig.
  const token = applePassToken(req.headers.get("Authorization"));
  if (!token || !isSerial(r.serial)) return new Response(null, { status: 401 });
  const row = await passRow(r.serial);
  if (!row || !sameText(row.token_hash, await tokenHash(token.toLowerCase()))) return new Response(null, { status: 401 });

  if (r.kind === "register") {
    let pushToken = "";
    try { pushToken = String((await req.json())?.pushToken ?? ""); } catch { /* leeg */ }
    if (!/^[0-9a-fA-F]{16,200}$/.test(pushToken)) return new Response(null, { status: 400 });
    const existing = await rest(`pasr_wallet_registrations?device=eq.${enc(r.device)}&serial=eq.${enc(r.serial)}&select=serial`) as unknown[];
    await rest("pasr_wallet_registrations", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({ device: r.device, serial: r.serial, push_token: pushToken.toLowerCase() }),
    });
    return new Response(null, { status: existing.length ? 200 : 201 });
  }
  if (r.kind === "unregister") {
    await rest(`pasr_wallet_registrations?device=eq.${enc(r.device)}&serial=eq.${enc(r.serial)}`, { method: "DELETE" });
    return new Response(null, { status: 200 });
  }

  // De nieuwste pas
  const since = Date.parse(req.headers.get("If-Modified-Since") ?? "");
  const updated = Date.parse(row.updated_at);
  if (since && updated && Math.floor(updated / 1000) <= Math.floor(since / 1000)) return new Response(null, { status: 304 });
  const card = await open<Card>(row.data, token.toLowerCase());
  if (card.kind === "stamps" && card.issuer === "business" && card.memberCode) {
    const stand = await memberStand(card.memberCode);
    if (stand) {
      if (stand.total !== undefined) card.stampsTotal = stand.total;
      if (stand.count !== undefined) card.stampsCount = stand.count;
      if (stand.reward !== undefined) card.reward = stand.reward;
    }
  }
  const pkpass = await buildPass(card, { url: webServiceURL(), token: token.toLowerCase() });
  return new Response(pkpass as unknown as BodyInit, {
    headers: {
      "Content-Type": "application/vnd.apple.pkpass",
      "Last-Modified": new Date(updated || Date.now()).toUTCString(),
      "Cache-Control": "no-store",
    },
  });
}

type PassRow = { serial: string; token_hash: string; data: string; member_code: string | null; updated_at: string };

async function passRow(serial: string): Promise<PassRow | null> {
  const rows = await rest(`pasr_wallet_passes?serial=eq.${enc(serial)}&select=serial,token_hash,data,member_code,updated_at`) as PassRow[];
  return rows[0] ?? null;
}

/** De kaart (zonder token) versleuteld bewaren; updated_at = nu, zodat Wallet hem als gewijzigd ziet. */
async function savePass(card: Card, token: string) {
  const member = card.kind === "stamps" && card.issuer === "business" && typeof card.memberCode === "string"
    ? card.memberCode.slice(0, 120) : null;
  await rest("pasr_wallet_passes", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      serial: card.id, token_hash: await tokenHash(token), data: await seal(stored(card), token),
      member_code: member, updated_at: new Date().toISOString(),
    }),
  });
}

/** Een zaak zette een stempel: de passen met die klantcode als gewijzigd markeren en inseinen. */
async function kickBusiness(code: string): Promise<number> {
  if (!dbReady()) return 0;
  const rows = await rest(`pasr_wallet_passes?member_code=eq.${enc(code)}&select=serial`) as { serial: string }[];
  let n = 0;
  for (const row of rows) {
    await rest(`pasr_wallet_passes?serial=eq.${enc(row.serial)}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ updated_at: new Date().toISOString() }),
    });
    n += await pushSerial(row.serial);
  }
  return n;
}

async function memberStand(code: string) {
  try {
    return businessStand(await rest("rpc/pasr_business_member", { method: "POST", body: JSON.stringify({ p_code: code }) }));
  } catch {
    return null;   // geen stand: de pas houdt de laatst bekende
  }
}

/** Alle apparaten met deze pas een lege push sturen; Wallet haalt dan de nieuwe pas op. */
async function pushSerial(serial: string): Promise<number> {
  const regs = await rest(`pasr_wallet_registrations?serial=eq.${enc(serial)}&select=device,push_token`) as
    { device: string; push_token: string }[];
  if (!regs.length) return 0;
  const tokens = [...new Set(regs.map((x) => x.push_token))];
  let ok = 0;
  for (const t of tokens) {
    const status = await apnsPush(t);
    if (status === 200) ok++;
    else if (status === 410 || status === 400) {
      // dit apparaat heeft de pas niet meer (of het token klopt niet): registratie weg
      await rest(`pasr_wallet_registrations?push_token=eq.${enc(t)}&serial=eq.${enc(serial)}`, { method: "DELETE" }).catch(() => {});
    } else if (status) {
      console.error("wallet-pass apns:", status);
    }
  }
  return ok;
}

// APNs voor passen werkt alleen met het pass-certificaat (TLS-clientcertificaat), altijd productie.
let apnsClient: unknown = null;
let apnsMode: "deno" | "node" | "none" | null = null;

async function apnsPush(pushToken: string): Promise<number> {
  const { cert, key } = signerPem();
  const path = `/3/device/${pushToken}`;
  const headers = { "apns-topic": passTypeId(), "apns-priority": "10", "content-type": "application/json" };
  if (apnsMode === null || apnsMode === "deno") {
    try {
      // deno-lint-ignore no-explicit-any
      const D = Deno as any;
      if (!apnsClient) apnsClient = D.createHttpClient({ cert, key, certChain: cert, privateKey: key, http2: true, http1: false });
      const res = await fetch(`https://api.push.apple.com${path}`, {
        method: "POST", headers, body: "{}", signal: AbortSignal.timeout(15000),
        // deno-lint-ignore no-explicit-any
        client: apnsClient as any,
      } as RequestInit);
      await res.body?.cancel();
      apnsMode = "deno";
      return res.status;
    } catch (e) {
      if (apnsMode === "deno") { console.error("wallet-pass apns:", (e as Error).message); return 0; }
      apnsMode = "node";   // geen Deno.createHttpClient met certificaat in deze omgeving: node:http2
    }
  }
  if (apnsMode === "none") return 0;
  try {
    const http2 = await import("node:http2");
    return await new Promise<number>((resolve) => {
      const session = http2.connect("https://api.push.apple.com", { cert, key });
      const done = (code: number) => { try { session.close(); } catch { /* al dicht */ } resolve(code); };
      session.on("error", () => done(0));
      const stream = session.request({ ":method": "POST", ":path": path, ...headers });
      let status = 0;
      stream.on("response", (h: Record<string, unknown>) => { status = Number(h[":status"] ?? 0); });
      stream.on("data", () => {});
      stream.on("end", () => done(status));
      stream.on("error", () => done(status));
      stream.setTimeout?.(15000, () => { try { stream.close(); } catch { /* niets */ } done(status); });
      stream.end("{}");
    });
  } catch (e) {
    apnsMode = "none";
    console.error("wallet-pass apns unavailable:", (e as Error).message);
    return 0;
  }
}

function signerPem() {
  loadSigner();
  return { cert: forge.pki.certificateToPem(signer!.cert), key: forge.pki.privateKeyToPem(signer!.key) };
}

let hookSecret: string | null = null;
let hookUntil = 0;
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

/** PostgREST met de service-sleutel (alleen in deze functie). */
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

/** +1 op de teller van vandaag (pasr_daily.wallet) voor het beheer. Alleen een aantal; gaat nooit mis voor de gebruiker. */
function countPass() {
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return;
  fetch(`${url}/rest/v1/rpc/pasr_count_wallet`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: "{}",
    signal: AbortSignal.timeout(5000),
  }).then((r) => r.body?.cancel()).catch(() => {});
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// ---------------------------------------------------------------------------------------------------------------

/** Hoogstens 8 regels van 120 tekens, zonder vreemde tekens. */
export function history(card: Card): string[] {
  return (Array.isArray(card.history) ? card.history : [])
    .filter((l) => typeof l === "string")
    .map((l) => l.replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, 120))
    .filter(Boolean)
    .slice(0, 8);
}

/** Velden voor ticket en abonnement (sinds Pasr 1.0.2). */
function extraFields(card: Card, kind: string, text: (s: unknown, n?: number) => string,
                     validDate: (s?: string) => string | undefined): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  if (kind === "ticket") {
    if (validDate(card.eventDate)) {
      out.push({ key: "event", label: "DATUM", value: card.eventDate, dateStyle: "PKDateStyleMedium", timeStyle: "PKDateStyleShort" });
    }
    if (card.venue) out.push({ key: "venue", label: "LOCATIE", value: text(card.venue) });
    if (card.seat) out.push({ key: "seat", label: "PLAATS", value: text(card.seat, 40) });
  } else if (kind === "subscription") {
    if (typeof card.cost === "number" && isFinite(card.cost)) {
      out.push({ key: "cost", label: ({ week: "PER WEEK", quarter: "PER KWARTAAL", year: "PER JAAR" } as Record<string, string>)[card.period ?? ""] ?? "PER MAAND",
                 value: card.cost, currencyCode: card.currency ?? "EUR" });
    }
    if (validDate(card.renewsAt)) out.push({ key: "renews", label: "VERLENGT OP", value: card.renewsAt, dateStyle: "PKDateStyleMedium" });
  }
  return out;
}

async function buildPass(card: Card, ws: { url: string; token: string } | null = null): Promise<Uint8Array> {
  const passTypeIdentifier = Deno.env.get("PASS_TYPE_ID") ?? "pass.nl.lrvdlinden.pasr";
  const teamIdentifier = Deno.env.get("PASS_TEAM_ID") ?? "EU3UY476T6";
  const bg = hexToRgb(card.colorHex);
  const light = luminance(bg) > 0.55;
  const fg = light ? "rgb(17, 17, 17)" : "rgb(255, 255, 255)";
  const label = light ? "rgb(90, 90, 90)" : "rgba(255, 255, 255, 0.75)";
  const grouped = groupNumber(card.number);
  const voucher = card.kind === "voucher";
  const kind = card.kind ?? "loyalty";
  const numberLabel = ({ voucher: "KAARTNUMMER", code: "CODE", ticket: "TICKET", subscription: "LIDNUMMER", stamps: "KAARTNUMMER" } as Record<string, string>)[kind] ?? "NUMMER";
  const stampsCard = kind === "stamps";
  const st = stampsCard ? stampFields(card) : null;
  const hasCode = !!card.number;
  // zakelijke stempelkaart: het nummer is de klantcode die de zaak scant
  const businessCode = stampsCard && card.issuer === "business";
  const text = (s: unknown, n = 80) => String(s ?? "").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, n);
  const validDate = (s?: string) => (s && !isNaN(Date.parse(s)) ? s : undefined);
  const extra = extraFields(card, kind, text, validDate);

  const pass: Record<string, unknown> = {
    formatVersion: 1,
    passTypeIdentifier,
    teamIdentifier,
    serialNumber: card.id,
    organizationName: "Pasr",
    description: `${card.name} (Pasr)`,
    backgroundColor: `rgb(${bg.join(", ")})`,
    foregroundColor: fg,
    labelColor: label,
    // kortingscode als tekst: geen barcode op de pas, de code staat bij de velden
    ...(ws ? { webServiceURL: ws.url, authenticationToken: ws.token } : {}),
    ...(card.codeAsText || !hasCode ? {} : { barcodes: [{
      format: walletFormat(card.format),
      message: card.number,
      messageEncoding: "iso-8859-1",
      altText: grouped,
    }] }),
    storeCard: {
      // Rechtsboven: het tegoed van een cadeaukaart en altijd het merk Pasr (Wallet staat daar alleen tekst toe).
      headerFields: [
        ...(voucher && card.balance != null
          ? [{ key: "balance", label: "TEGOED", value: card.balance, currencyCode: card.currency ?? "EUR",
               changeMessage: "Tegoed nu %@" }]
          : []),
        ...(st ? [st.header] : []),
        { key: "brand", label: " ", value: "pasr" },
      ],
      ...(st && st.primary.length ? { primaryFields: st.primary } : {}),
      secondaryFields: hasCode
        ? [{ key: "number", label: businessCode ? "KLANTCODE" : numberLabel, value: card.codeAsText ? card.number : grouped }]
        : [],
      auxiliaryFields: st
        ? st.auxiliary
        : (voucher || kind === "code") && card.expiresAt
        ? [{ key: "expires", label: "GELDIG TOT", value: card.expiresAt, dateStyle: "PKDateStyleMedium" }, ...extra]
        : extra,
      backFields: [
        ...(card.note ? [{ key: "note", label: "Notitie", value: card.note }] : []),
        ...(st && card.reward ? [{ key: "reward", label: "Beloning", value: text(card.reward, 60) }] : []),
        ...(businessCode ? [{ key: "business", label: "Stempelkaart van de zaak", value: "De zaak zet de stempels; deze pas werkt vanzelf bij." }] : []),
        ...(history(card).length ? [{ key: "history", label: voucher ? "Laatste uitgaven" : "Laatst gebruikt", value: history(card).join("\n") }] : []),
        { key: "pasr", label: "Pasr", value: "Deze pas komt uit Pasr, de gratis app voor je klantenkaarten. pasr.nl" },
      ],
    },
  };
  if (!card.logo) pass.logoText = card.name;
  if ((voucher || kind === "code") && card.expiresAt) pass.expirationDate = card.expiresAt;
  if (kind === "ticket" && validDate(card.eventDate)) pass.relevantDate = card.eventDate;
  const locations = (card.locations ?? []).filter((l) => isFinite(l.latitude) && isFinite(l.longitude)).slice(0, 10);
  if (locations.length) {
    pass.locations = locations.map((l) => ({
      latitude: l.latitude,
      longitude: l.longitude,
      relevantText: `Je ${card.name}-kaart`,
    }));
  }

  // ticket: een echte eventTicket-pas (merkkleur, logo, evenementvelden, gegroepeerd per evenement)
  const final = kind === "ticket" ? ticketPass(pass, card) : pass;
  const files: Record<string, Uint8Array> = {
    "pass.json": strToU8(JSON.stringify(final)),
    "icon.png": await asset("icon.png"),
    "icon@2x.png": await asset("icon@2x.png"),
    "icon@3x.png": await asset("icon@3x.png"),
  };
  if (card.logo) {
    const logo = Uint8Array.from(atob(card.logo), (c) => c.charCodeAt(0));
    if (logo.length > 600_000) throw new Error("logo too large");
    files["logo.png"] = logo;
    files["logo@2x.png"] = logo;
    files["logo@3x.png"] = logo;
  }

  const manifest: Record<string, string> = {};
  for (const [name, data] of Object.entries(files)) manifest[name] = await sha1(data);
  const manifestBytes = strToU8(JSON.stringify(manifest));
  files["manifest.json"] = manifestBytes;
  files["signature"] = await sign(manifestBytes);
  return zipSync(files, { level: 6 });
}

async function asset(name: string) {
  return Uint8Array.from(atob(ICONS[name]), (c) => c.charCodeAt(0));
}

async function sha1(data: Uint8Array) {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-1", data as BufferSource));
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Detached PKCS#7 signature of manifest.json with the pass certificate, Apple WWDR G4 in the chain. */
async function sign(manifest: Uint8Array): Promise<Uint8Array> {
  loadSigner();
  if (!wwdr) {
    const der = new Uint8Array(await (await fetch(WWDR_URL)).arrayBuffer());
    wwdr = forge.pki.certificateFromAsn1(forge.asn1.fromDer(forge.util.binary.raw.encode(der)));
  }
  return signWith(manifest);
}

/** Het pass-certificaat en de sleutel uit PASS_CERT_P12 (ook voor APNs). */
function loadSigner() {
  if (!signer) {
    const p12b64 = Deno.env.get("PASS_CERT_P12");
    if (!p12b64) throw new Error("PASS_CERT_P12 missing");
    const p12 = forge.pkcs12.pkcs12FromAsn1(forge.asn1.fromDer(forge.util.decode64(p12b64.replace(/\s+/g, ""))),
      Deno.env.get("PASS_CERT_PASSWORD") ?? "");
    const cert = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag]?.[0]?.cert;
    const key = (p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag]?.[0]
      ?? p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag]?.[0])?.key;
    if (!cert || !key) throw new Error("certificate or key not found in PASS_CERT_P12");
    signer = { cert, key };
  }
}

function signWith(manifest: Uint8Array): Uint8Array {
  if (!signer || !wwdr) throw new Error("signer not loaded");
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(forge.util.binary.raw.encode(manifest));
  p7.addCertificate(signer.cert);
  p7.addCertificate(wwdr);
  p7.addSigner({
    key: signer.key,
    certificate: signer.cert,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
    ],
  });
  p7.sign({ detached: true });
  const der = forge.asn1.toDer(p7.toAsn1()).getBytes();
  return Uint8Array.from(der, (c: string) => c.charCodeAt(0));
}

// Wallet knows QR, PDF417, Aztec and Code 128. EAN/UPC/Code 39/ITF become Code 128 with the same number,
// which checkout scanners read just the same.
function walletFormat(format: string) {
  switch (format) {
    case "qr": return "PKBarcodeFormatQR";
    case "pdf417": return "PKBarcodeFormatPDF417";
    case "aztec": return "PKBarcodeFormatAztec";
    default: return "PKBarcodeFormatCode128";
  }
}

function groupNumber(n: string) {
  const c = n.replace(/\s+/g, "");
  return c.length > 8 && /^\d+$/.test(c) ? c.match(/.{1,4}/g)!.join(" ") : n;
}

function hexToRgb(hex: string): [number, number, number] {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex ?? "");
  const v = m ? parseInt(m[1], 16) : 0x2b2f3a;
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

function luminance([r, g, b]: [number, number, number]) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}
