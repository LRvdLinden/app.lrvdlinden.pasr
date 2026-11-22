// Huisstijl van een zaak van zijn eigen website (Pasr Zakelijk en pasr.nl/zakelijk/dashboard): naam, logo en kleur.
// Pure hulpjes (zonder netwerk), getest in brand_test.ts. Het ophalen zelf staat in index.ts.

/** Alleen http(s), geen poort behalve 80/443, geen inlog in de url, een echte hostnaam (geen IP-literal hier). */
export function cleanUrl(input: unknown): URL | null {
  if (typeof input !== "string") return null;
  let t = input.trim();
  if (!t || t.length > 300) return null;
  if (!/^https?:\/\//i.test(t)) t = "https://" + t;
  let u: URL;
  try { u = new URL(t); } catch { return null; }
  if (!/^https?:$/.test(u.protocol) || u.username || u.password) return null;
  if (u.port && u.port !== "80" && u.port !== "443") return null;
  const host = u.hostname.toLowerCase();
  if (!/^[a-z0-9.-]+\.[a-z]{2,}$/.test(host) || host.endsWith(".local") || host.endsWith(".internal") || host === "localhost") return null;
  return u;
}

/** Privé, loopback, link-local, CGNAT, multicast, gereserveerd: nooit ophalen (SSRF). */
export function isPrivateIp(ip: string): boolean {
  const v4 = ip.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (v4) {
    const [a, b] = [Number(v4[1]), Number(v4[2])];
    return a === 0 || a === 10 || a === 127 || a >= 224 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 192 && b === 0) || (a === 198 && (b === 18 || b === 19));
  }
  const x = ip.toLowerCase().replace(/^\[|\]$/g, "");
  if (!x.includes(":")) return true;   // onbekend formaat: niet vertrouwen
  if (x === "::" || x === "::1") return true;
  const mapped = x.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return isPrivateIp(mapped[1]);
  return /^(fc|fd|fe8|fe9|fea|feb|ff|64:ff9b|2001:db8|2001:0db8|100::)/.test(x) || x.startsWith("::ffff:");
}

const attr = (tag: string, name: string) => {
  const m = tag.match(new RegExp(`\\s${name}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, "i"));
  return m ? (m[2] ?? m[3] ?? m[4] ?? "").trim() : "";
};
export const hex = (v: unknown): string | null => {
  if (typeof v !== "string") return null;
  const t = v.trim();
  if (/^#[0-9a-f]{6}$/i.test(t)) return t.toUpperCase();
  if (/^#[0-9a-f]{3}$/i.test(t)) return ("#" + t.slice(1).split("").map((c) => c + c).join("")).toUpperCase();
  const rgb = t.match(/^rgba?\(\s*(\d{1,3})[ ,]+(\d{1,3})[ ,]+(\d{1,3})/i);
  if (rgb) return "#" + rgb.slice(1, 4).map((n) => Math.min(255, Number(n)).toString(16).padStart(2, "0")).join("").toUpperCase();
  return null;
};
const decode = (s: string) => s.replace(/&amp;/g, "&").replace(/&#39;|&apos;/g, "'").replace(/&quot;/g, '"').replace(/&#x27;/g, "'")
  .replace(/\s+/g, " ").trim();

export type Candidate = { href: string; size: number; rank: number };
export type Head = { name: string | null; colors: string[]; icons: Candidate[]; manifest: string; og: string };

/** Uit de HTML: naam (og:site_name, application-name, titel), theme-color, iconen (grootste eerst), manifest, og:image. */
export function parseHead(html: string, base: string): Head {
  const head = html.slice(0, 400_000);
  const metas = head.match(/<meta\b[^>]*>/gi) ?? [];
  const links = head.match(/<link\b[^>]*>/gi) ?? [];
  const meta = (key: string) => {
    for (const m of metas) {
      const k = (attr(m, "property") || attr(m, "name")).toLowerCase();
      if (k === key) return decode(attr(m, "content"));
    }
    return "";
  };
  const title = decode((head.match(/<title[^>]*>([^<]{1,160})<\/title>/i) ?? [])[1] ?? "");
  const name = cleanName(meta("og:site_name") || meta("application-name") || meta("apple-mobile-web-app-title") ||
    title.split(/\s[|–—:-]\s/)[0]);
  const colors = [meta("theme-color"), meta("msapplication-tilecolor")].map(hex).filter((c): c is string => !!c);
  const icons: Candidate[] = [];
  let manifest = "";
  const abs = (h: string) => { try { return new URL(h, base).href; } catch { return ""; } };
  for (const l of links) {
    const rel = attr(l, "rel").toLowerCase(), href = attr(l, "href");
    if (!href) continue;
    if (rel === "manifest") { manifest = abs(href); continue; }
    if (!rel.includes("icon")) continue;
    if (/\.(svg|ico)(\?|#|$)/i.test(href) || /svg|icon/.test(attr(l, "type"))) continue;   // SVG en ICO kunnen we niet rasteren
    const size = Math.max(0, ...attr(l, "sizes").split(/\s+/).map((s) => parseInt(s, 10) || 0));
    const u = abs(href);
    if (u) icons.push({ href: u, size: size || (rel.includes("apple") ? 180 : 32), rank: rel.includes("apple") ? 2 : 1 });
  }
  const og = meta("og:image");
  return { name, colors, icons, manifest, og: og ? abs(og) : "" };
}

export function cleanName(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = decode(v).replace(/[<>]/g, "").slice(0, 60).trim();
  return t.length >= 2 ? t : null;
}

/** Uit het web-manifest: naam, theme_color en iconen (geen SVG, "maskable" alleen als er niets anders is). */
export function parseManifest(json: unknown, base: string): { name: string | null; color: string | null; icons: Candidate[] } {
  const j = (json && typeof json === "object" ? json : {}) as Record<string, unknown>;
  const icons: Candidate[] = [];
  for (const i of Array.isArray(j.icons) ? j.icons : []) {
    const src = (i as Record<string, unknown>)?.src;
    if (typeof src !== "string" || /\.(svg|ico)(\?|#|$)/i.test(src) || /svg/.test(String((i as Record<string, unknown>).type ?? ""))) continue;
    const size = Math.max(0, ...String((i as Record<string, unknown>).sizes ?? "").split(/\s+/).map((s) => parseInt(s, 10) || 0));
    const maskable = /maskable/.test(String((i as Record<string, unknown>).purpose ?? ""));
    try { icons.push({ href: new URL(src, base).href, size, rank: maskable ? 1 : 3 }); } catch { /* */ }
  }
  return { name: cleanName(j.short_name ?? j.name), color: hex(j.theme_color), icons };
}

/** Volgorde: groot en vierkant eerst (manifest > apple-touch-icon > icon), og:image als laatste. Hoogstens 8. */
export function rankCandidates(head: Head, manifestIcons: Candidate[], origin: string): Candidate[] {
  const list = [...manifestIcons, ...head.icons, { href: new URL("/apple-touch-icon.png", origin).href, size: 180, rank: 0 }];
  list.sort((a, b) => (Math.min(b.size, 512) - Math.min(a.size, 512)) || (b.rank - a.rank));
  if (head.og) list.push({ href: head.og, size: 0, rank: -1 });
  const seen = new Set<string>();
  return list.filter((c) => !seen.has(c.href) && seen.add(c.href)).slice(0, 8);
}

/** Herkent PNG/JPEG/WebP/GIF aan de eerste bytes (de content-type van sites klopt niet altijd). */
export function imageType(b: Uint8Array): string | null {
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0xff && b[1] === 0xd8) return "image/jpeg";
  if (b[0] === 0x52 && b[1] === 0x49 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46) return "image/gif";
  return null;
}

// ---- kleur (zelfde idee als tools/fetch_logos.py: geen wit, zwart of grijs als merkkleur) ----
export function rgbOf(h: string): [number, number, number] {
  const n = parseInt(h.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
const toHex = (r: number, g: number, b: number) => "#" + [r, g, b].map((x) => Math.round(x).toString(16).padStart(2, "0")).join("").toUpperCase();

/** Bruikbaar als kaartkleur: niet (bijna) wit, zwart of grijs. */
export function usable(h: string): boolean {
  const [r, g, b] = rgbOf(h);
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const sat = max === 0 ? 0 : (max - min) / max;
  return max > 40 && !(min > 225) && sat > 0.18;
}

/** Dominante bruikbare kleur uit pixels (RGBA, Uint8Array): kleuren in bakjes van 24, transparant telt niet. */
export function dominant(rgba: Uint8Array): string | null {
  const bins = new Map<number, { n: number; r: number; g: number; b: number }>();
  const step = Math.max(4, Math.floor(rgba.length / 4 / 20000) * 4);
  for (let i = 0; i + 3 < rgba.length; i += step) {
    if (rgba[i + 3] < 200) continue;
    const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (!usable(toHex(r, g, b))) continue;
    const k = ((r / 24) | 0) * 10000 + ((g / 24) | 0) * 100 + ((b / 24) | 0);
    const e = bins.get(k) ?? { n: 0, r: 0, g: 0, b: 0 };
    e.n++; e.r += r; e.g += g; e.b += b;
    bins.set(k, e);
  }
  let best: { n: number; r: number; g: number; b: number } | null = null;
  for (const e of bins.values()) if (!best || e.n > best.n) best = e;
  return best && best.n >= 3 ? toHex(best.r / best.n, best.g / best.n, best.b / best.n) : null;
}

/** Kaartkleur: theme_color als die bruikbaar is, anders de dominante kleur van het logo, anders null. */
export function pickColor(themeColors: string[], logoColor: string | null): string | null {
  for (const c of themeColors) if (usable(c)) return c;
  return logoColor;
}

function lum(h: string) {
  const ch = rgbOf(h).map((x) => { const v = x / 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
  return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}
/** Leesbare tekstkleur op de kaart: wit of zwart, wat het meeste contrast geeft. */
export function textColor(bg: string): "#FFFFFF" | "#000000" {
  const l = lum(bg);
  return (1.05 / (l + 0.05)) >= ((l + 0.05) / 0.05) ? "#FFFFFF" : "#000000";
}

/** Base64 zonder stack-overflow bij grote buffers. */
export function b64(b: Uint8Array): string {
  let s = "";
  for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192));
  return btoa(s);
}

/** Hoeveel bij een uur-limiet nog mag: 20 per zaak per uur. */
export const BRAND_PER_HOUR = 20;
