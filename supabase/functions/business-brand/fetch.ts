// business-brand: ophalen met SSRF-beveiliging en de huisstijl bepalen. Zonder Supabase, zodat het los te testen is.
import { contain, decodeImage, encodePng } from "./image.ts";
import {
  b64, type Candidate, cleanUrl, dominant, imageType, isPrivateIp, parseHead, parseManifest, pickColor, rankCandidates, textColor,
} from "./brand.ts";

const MAX_BYTES = 2_000_000, TIMEOUT_MS = 8000, MAX_REDIRECTS = 3, LOGO_MAX = 512;
const UA = "Mozilla/5.0 (compatible; PasrZakelijk/1.0; +https://pasr.nl/zakelijk/)";

// ---- DNS: alle adressen moeten publiek zijn ----
async function resolve(host: string): Promise<string[]> {
  const out: string[] = [];
  try {
    for (const t of ["A", "AAAA"] as const) {
      try { out.push(...(await Deno.resolveDns(host, t)) as string[]); } catch { /* geen record van dit type */ }
    }
    if (out.length) return out;
  } catch { /* resolveDns niet beschikbaar: DNS-over-HTTPS */ }
  for (const t of ["A", "AAAA"]) {
    try {
      const r = await fetch(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(host)}&type=${t}`,
        { headers: { Accept: "application/dns-json" }, signal: AbortSignal.timeout(4000) });
      const j = await r.json();
      for (const a of j?.Answer ?? []) if ((a.type === 1 || a.type === 28) && typeof a.data === "string") out.push(a.data);
    } catch { /* volgende */ }
  }
  return out;
}

async function publicHost(u: URL): Promise<boolean> {
  const ips = await resolve(u.hostname);
  return ips.length > 0 && ips.every((ip) => !isPrivateIp(ip));
}

/** Eén bestand ophalen met alle limieten. Redirects volgen we zelf, met dezelfde controles per stap. */
export async function fetchSafe(start: string, accept: string): Promise<{ bytes: Uint8Array; url: string; type: string } | null> {
  const deadline = Date.now() + TIMEOUT_MS;
  let url = start;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const u = cleanUrl(url);
    if (!u || !(await publicHost(u))) return null;
    const left = deadline - Date.now();
    if (left <= 0) return null;
    let res: Response;
    try {
      res = await fetch(u, { headers: { "User-Agent": UA, Accept: accept }, redirect: "manual", signal: AbortSignal.timeout(left) });
    } catch { return null; }
    if (res.status >= 300 && res.status < 400) {
      const loc = res.headers.get("location");
      await res.body?.cancel().catch(() => {});
      if (!loc) return null;
      try { url = new URL(loc, u).href; } catch { return null; }
      continue;
    }
    if (!res.ok || !res.body) { await res.body?.cancel().catch(() => {}); return null; }
    const len = Number(res.headers.get("content-length") ?? 0);
    if (len > MAX_BYTES) { await res.body.cancel().catch(() => {}); return null; }
    const reader = res.body.getReader();
    const parts: Uint8Array[] = [];
    let total = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.length;
        if (total > MAX_BYTES || Date.now() > deadline) { await reader.cancel(); return null; }
        parts.push(value);
      }
    } catch { return null; }
    const bytes = new Uint8Array(total);
    let o = 0;
    for (const p of parts) { bytes.set(p, o); o += p.length; }
    return { bytes, url: u.href, type: (res.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase() };
  }
  return null;
}

/** Een kandidaat als vierkant-achtig logo: ontcijferen, maximaal 512 px, PNG. Plus de dominante kleur. */
async function logoFrom(c: Candidate): Promise<{ png: Uint8Array; color: string | null; side: number } | null> {
  const f = await fetchSafe(c.href, "image/png,image/jpeg,image/webp,image/gif;q=0.8,*/*;q=0.1");
  if (!f || !imageType(f.bytes)) return null;
  // PNG en JPEG (puur JavaScript, zie image.ts); WebP en GIF: volgende kandidaat
  let img = decodeImage(f.bytes);
  if (!img) return null;
  const ratio = img.width / img.height;
  if (ratio < 0.75 || ratio > 1.34 || Math.min(img.width, img.height) < 32) return null;
  img = contain(img, LOGO_MAX);
  const color = dominant(img.data);
  let png = encodePng(img);
  // past in een kaart (de database neemt tot ca. 210 kB base64)
  if (png.length > 150_000) png = encodePng(contain(img, 256));
  if (png.length > 150_000) return null;
  return { png, color, side: Math.min(img.width, img.height) };
}

export async function brand(site: URL) {
  let page = await fetchSafe(site.href, "text/html,application/xhtml+xml");
  if (!page && !site.hostname.startsWith("www.")) {
    const www = new URL(site.href); www.hostname = "www." + site.hostname;
    page = await fetchSafe(www.href, "text/html,application/xhtml+xml");
  }
  if (!page) return null;
  const base = page.url;
  const head = parseHead(new TextDecoder().decode(page.bytes.subarray(0, 600_000)), base);
  let manifestName: string | null = null, manifestColor: string | null = null, manifestIcons: Candidate[] = [];
  if (head.manifest) {
    const m = await fetchSafe(head.manifest, "application/manifest+json,application/json");
    try {
      const pm = parseManifest(m ? JSON.parse(new TextDecoder().decode(m.bytes)) : null, head.manifest);
      manifestName = pm.name; manifestColor = pm.color; manifestIcons = pm.icons;
    } catch { /* geen geldig manifest */ }
  }
  let logo: { png: Uint8Array; color: string | null; side: number } | null = null;
  for (const c of rankCandidates(head, manifestIcons, new URL(base).origin)) {
    const l = await logoFrom(c);
    if (l && (!logo || l.side > logo.side)) logo = l;
    if (logo && logo.side >= 128) break;
  }
  const themes = [...(manifestColor ? [manifestColor] : []), ...head.colors];
  const color = pickColor(themes, logo?.color ?? null);
  const u = new URL(base);
  return {
    name: head.name ?? manifestName,
    logo: logo ? b64(logo.png) : null,
    color,
    text_color: textColor(color ?? "#6A5CFF"),
    source_url: u.origin + "/",
    domain: u.hostname.replace(/^www\./, ""),
  };
}

