// Winkels aanvragen en toevoegen zonder app-update: de website van een winkel opzoeken (naam, logo, merkkleuren)
// en de invoer van het beheer controleren. Pure hulpjes plus één fetch-functie; getest in stores_test.ts.

export const CATEGORIES = [
  "Supermarkt", "Drogist en beauty", "Warenhuis en wonen", "Mode en schoenen", "Elektronica", "Doe-het-zelf en tuin",
  "Sport en vrije tijd", "Tanken en reizen", "Eten en drinken", "Boeken en cadeaus", "Dieren", "Cadeaukaarten", "Overig",
] as const;
export const FORMATS = ["ean13", "ean8", "upcA", "code128", "code39", "itf", "qr", "pdf417", "aztec"] as const;
export const KINDS_CARD = ["loyalty", "voucher"] as const;

type J = Record<string, unknown>;
const str = (v: unknown, max: number) => (typeof v === "string" ? v.trim().slice(0, max) : "");

/** "Kwantum Wonen" -> "kwantum-wonen" */
export function slug(text: string): string {
  return text.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "").slice(0, 40);
}

/** "https://www.kwantum.nl/acties" -> "kwantum.nl" (null als het geen domein is). */
export function domainOf(input: unknown): string | null {
  let t = str(input, 300).toLowerCase();
  if (!t) return null;
  t = t.replace(/^[a-z]+:\/\//, "").split(/[/?#]/)[0].replace(/^www\./, "").replace(/:\d+$/, "");
  if (!/^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(t)) return null;
  if (/^\d+(\.\d+){3}$/.test(t) || t.endsWith(".local") || t.endsWith(".internal") || t === "localhost") return null;
  return t;
}

export type StoreInput = {
  id: string; name: string; domain: string; category: string; card_hex: string; format: string; kind: string;
  aliases: string[]; logo: string | null;
};

/** Invoer van store_save controleren. Logo = base64 van een PNG/JPEG/WebP, hoogstens 300 kB. */
export function cleanStore(v: unknown): { ok: true; value: StoreInput } | { ok: false; error: string } {
  const b = (v && typeof v === "object" && !Array.isArray(v) ? v : {}) as J;
  const name = str(b.name, 40);
  if (!name) return { ok: false, error: "bad_name" };
  const id = slug(str(b.id, 40) || name);
  if (id.length < 2) return { ok: false, error: "bad_id" };
  const domain = b.domain ? domainOf(b.domain) : "";
  if (domain === null) return { ok: false, error: "bad_domain" };
  const category = (CATEGORIES as readonly string[]).includes(String(b.category)) ? String(b.category) : "Overig";
  const card_hex = /^#[0-9a-fA-F]{6}$/.test(String(b.card_hex)) ? String(b.card_hex).toUpperCase() : "";
  if (!card_hex) return { ok: false, error: "bad_color" };
  const format = (FORMATS as readonly string[]).includes(String(b.format)) ? String(b.format) : "code128";
  const kind = (KINDS_CARD as readonly string[]).includes(String(b.kind)) ? String(b.kind) : "loyalty";
  const aliases = (Array.isArray(b.aliases) ? b.aliases : []).map((a) => str(a, 40).toLowerCase()).filter(Boolean).slice(0, 8);
  let logo: string | null = null;
  if (b.logo !== undefined && b.logo !== null && b.logo !== "") {
    const s = String(b.logo).replace(/^data:image\/[a-z]+;base64,/, "");
    if (!/^[A-Za-z0-9+/=]+$/.test(s) || s.length > 400_000) return { ok: false, error: "bad_logo" };
    logo = s;
  }
  return { ok: true, value: { id, name, domain, category, card_hex, format, kind, aliases, logo } };
}

// ---- website opzoeken ----

export type Lookup = { domain: string; name: string | null; colors: string[]; logo: string | null; logo_type: string | null; icons: number };

const attr = (tag: string, name: string) => {
  const m = tag.match(new RegExp(`${name}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, "i"));
  return m ? (m[2] ?? m[3] ?? m[4] ?? "").trim() : "";
};
const hex = (v: string) => {
  const t = v.trim();
  if (/^#[0-9a-f]{6}$/i.test(t)) return t.toUpperCase();
  if (/^#[0-9a-f]{3}$/i.test(t)) return ("#" + t.slice(1).split("").map((c) => c + c).join("")).toUpperCase();
  return null;
};
const decode = (s: string) => s.replace(/&amp;/g, "&").replace(/&#39;|&apos;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ").trim();

/** Haalt uit HTML: naam, kleuren en icoon-kandidaten (grootste eerst). */
export function parseHead(html: string, base: string) {
  const head = html.slice(0, 300_000);
  const metas = head.match(/<meta\b[^>]*>/gi) ?? [];
  const links = head.match(/<link\b[^>]*>/gi) ?? [];
  const meta = (key: string) => {
    for (const m of metas) {
      const k = (attr(m, "property") || attr(m, "name")).toLowerCase();
      if (k === key) return decode(attr(m, "content"));
    }
    return "";
  };
  const title = decode((head.match(/<title[^>]*>([^<]{1,120})<\/title>/i) ?? [])[1] ?? "");
  const name = meta("og:site_name") || meta("application-name") || meta("apple-mobile-web-app-title") ||
    title.split(/\s[|–—-]\s/)[0] || null;
  const colors = [meta("theme-color"), meta("msapplication-tilecolor")].map(hex).filter((c): c is string => !!c);
  const icons: { href: string; size: number; rank: number }[] = [];
  let manifest = "";
  for (const l of links) {
    const rel = attr(l, "rel").toLowerCase(), href = attr(l, "href");
    if (!href) continue;
    if (rel === "manifest") { manifest = new URL(href, base).href; continue; }
    if (!rel.includes("icon")) continue;
    if (/\.svg(\?|$)/i.test(href) || attr(l, "type").includes("svg")) continue;
    const size = Math.max(0, ...attr(l, "sizes").split(/\s+/).map((s) => parseInt(s, 10) || 0));
    icons.push({ href: new URL(href, base).href, size: size || (rel.includes("apple") ? 180 : 32), rank: rel.includes("apple") ? 2 : 1 });
  }
  const og = meta("og:image");
  return { name, colors, icons, manifest, og: og ? new URL(og, base).href : "" };
}

async function fetchLimited(url: string, max: number, accept: string): Promise<{ bytes: Uint8Array; type: string } | null> {
  const u = new URL(url);
  if (!/^https?:$/.test(u.protocol) || !domainOf(u.hostname)) return null;
  const res = await fetch(u, {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; PasrBeheer/1.0; +https://pasr.nl)", Accept: accept },
    redirect: "follow", signal: AbortSignal.timeout(8000),
  }).catch(() => null);
  if (!res || !res.ok || !res.body) return null;
  const reader = res.body.getReader();
  const parts: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) { await reader.cancel(); return null; }
    parts.push(value);
  }
  const bytes = new Uint8Array(total);
  let o = 0;
  for (const p of parts) { bytes.set(p, o); o += p.length; }
  return { bytes, type: (res.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase() };
}

const b64 = (b: Uint8Array) => {
  let s = "";
  for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192));
  return btoa(s);
};
/** Herkent PNG/JPEG/WebP aan de eerste bytes (de content-type van sites klopt niet altijd). */
export function imageType(b: Uint8Array): string | null {
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0xff && b[1] === 0xd8) return "image/jpeg";
  if (b[0] === 0x52 && b[1] === 0x49 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  return null;
}

/** De website van een winkel opzoeken: naam, merkkleuren en het beste logo (groot, geen SVG). */
export async function lookupSite(input: unknown): Promise<Lookup | null> {
  const domain = domainOf(input);
  if (!domain) return null;
  let base = `https://${domain}/`, head = { name: null as string | null, colors: [] as string[], icons: [] as { href: string; size: number; rank: number }[], manifest: "", og: "" };
  for (const host of [domain, `www.${domain}`]) {
    const page = await fetchLimited(`https://${host}/`, 1_500_000, "text/html");
    if (page) {
      base = `https://${host}/`;
      head = parseHead(new TextDecoder().decode(page.bytes), base);
      break;
    }
  }
  const candidates = [...head.icons];
  if (head.manifest) {
    const m = await fetchLimited(head.manifest, 200_000, "application/json");
    try {
      const j = m ? JSON.parse(new TextDecoder().decode(m.bytes)) : null;
      if (j) {
        for (const c of [j.theme_color, j.background_color]) { const h = typeof c === "string" ? hex(c) : null; if (h) head.colors.push(h); }
        if (!head.name && typeof (j.short_name ?? j.name) === "string") head.name = String(j.short_name ?? j.name).slice(0, 40);
        for (const i of Array.isArray(j.icons) ? j.icons : []) {
          if (typeof i?.src !== "string" || /\.svg/i.test(i.src)) continue;
          const size = Math.max(0, ...String(i.sizes ?? "").split(/\s+/).map((s: string) => parseInt(s, 10) || 0));
          candidates.push({ href: new URL(i.src, head.manifest).href, size, rank: 3 });
        }
      }
    } catch { /* geen geldig manifest */ }
  }
  candidates.push({ href: new URL("/apple-touch-icon.png", base).href, size: 180, rank: 0 });
  candidates.sort((a, b) => (b.size - a.size) || (b.rank - a.rank));
  let logo: string | null = null, logo_type: string | null = null;
  for (const c of candidates.slice(0, 6)) {
    const img = await fetchLimited(c.href, 300_000, "image/*");
    const type = img ? imageType(img.bytes) : null;
    if (img && type) { logo = b64(img.bytes); logo_type = type; break; }
  }
  return { domain, name: head.name, colors: [...new Set(head.colors)].filter((c) => c !== "#FFFFFF" && c !== "#000000").slice(0, 5),
           logo, logo_type, icons: candidates.length };
}

// ---- pushmelding naar de gebruikers van Pasr ----

/** Bundle-id van de app Pasr (APNs-topic voor meldingen aan gebruikers). */
export const USER_TOPIC = "nl.lrvdlinden.pasr";

export function newStorePayload(name: string, id: string) {
  return {
    aps: { alert: { title: "Nieuwe winkel in Pasr", body: `${name} staat nu in Pasr. Tik om je kaart toe te voegen.` },
           sound: "default", "thread-id": "stores" },
    kind: "store",
    store: id,
  };
}

// ---- saldo-pagina's ----

/** Saldo-pagina van een winkel: een https-adres, hoogstens 300 tekens, geen interne adressen. */
export function cleanBalancePage(v: unknown): { ok: true; value: { store_id: string; url: string } } | { ok: false; error: string } {
  const b = (v && typeof v === "object" && !Array.isArray(v) ? v : {}) as Record<string, unknown>;
  const store_id = String(b.store_id ?? "").trim().toLowerCase();
  if (!/^[a-z0-9-]{2,40}$/.test(store_id)) return { ok: false, error: "bad_id" };
  let url: URL;
  try {
    url = new URL(String(b.url ?? "").trim());
  } catch {
    return { ok: false, error: "bad_url" };
  }
  if (url.protocol !== "https:" || !domainOf(url.hostname) || url.href.length > 300 || url.username || url.password) {
    return { ok: false, error: "bad_url" };
  }
  return { ok: true, value: { store_id, url: url.href } };
}
