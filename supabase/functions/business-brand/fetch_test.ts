// Het ophalen zonder internet: DNS en fetch nagebootst. Controleert SSRF (privé-IP, redirect naar binnen), limieten en
// de keuze van logo en kleur.
import { encodePng } from "./image.ts";
import { brand, fetchSafe } from "./fetch.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

const DNS: Record<string, string[]> = {
  "bakkerij.nl": ["93.184.216.34"], "www.bakkerij.nl": ["93.184.216.34"], "cdn.bakkerij.nl": ["93.184.216.35"],
  "intern.nl": ["10.0.0.5"], "gemengd.nl": ["93.184.216.36", "127.0.0.1"], "redirect.nl": ["93.184.216.37"],
  "lus.nl": ["93.184.216.38"], "groot.nl": ["93.184.216.39"],
};
const solid = (w: number, h: number, rgba: number[]) => {
  const data = new Uint8Array(w * h * 4);
  for (let i = 0; i < data.length; i += 4) data.set(rgba, i);
  return encodePng({ width: w, height: h, data });
};
const logoPng = solid(300, 300, [0xd9, 0x16, 0x1e, 0xff]);
const widePng = solid(1200, 630, [0x12, 0x34, 0x56, 0xff]);

type R = { status?: number; body?: Uint8Array | string; headers?: Record<string, string> };
const SITES: Record<string, R> = {
  "https://bakkerij.nl/": { body: `<html><head><title>Bakkerij De Korf - Vers brood</title><meta name="theme-color" content="#ffffff">
    <link rel="manifest" href="/m.json"><link rel="apple-touch-icon" href="https://cdn.bakkerij.nl/a.png">
    <meta property="og:image" content="/og.png"></head></html>` },
  "https://bakkerij.nl/m.json": { body: JSON.stringify({ name: "De Korf", icons: [{ src: "/icon.svg" }] }) },
  "https://cdn.bakkerij.nl/a.png": { body: logoPng },
  "https://bakkerij.nl/og.png": { body: widePng },
  "https://redirect.nl/": { status: 302, headers: { location: "http://intern.nl/admin" } },
  "https://lus.nl/": { status: 301, headers: { location: "https://lus.nl/" } },
  "https://groot.nl/": { body: "x".repeat(2_100_000) },
};
const realFetch = globalThis.fetch, realDns = Deno.resolveDns;
const asked: string[] = [];
// deno-lint-ignore no-explicit-any
(Deno as any).resolveDns = (host: string, type: string) => Promise.resolve(type === "A" ? (DNS[host] ?? []) : []);
globalThis.fetch = (input: string | URL | Request) => {
  const url = String(input instanceof Request ? input.url : input);
  asked.push(url);
  const r = SITES[url];
  if (!r) return Promise.resolve(new Response("nee", { status: 404 }));
  return Promise.resolve(new Response(r.body ?? null, { status: r.status ?? 200, headers: r.headers }));
};

Deno.test("SSRF: privé-adressen en redirects naar binnen", async () => {
  ok(await fetchSafe("http://intern.nl/", "*/*") === null, "privé-IP");
  ok(await fetchSafe("https://gemengd.nl/", "*/*") === null, "één privé-adres is genoeg om te weigeren");
  ok(await fetchSafe("https://redirect.nl/", "*/*") === null, "redirect naar privé");
  ok(!asked.includes("http://intern.nl/admin"), "nooit opgevraagd");
  ok(await fetchSafe("https://lus.nl/", "*/*") === null, "hoogstens 3 redirects");
  ok(asked.filter((u) => u === "https://lus.nl/").length === 4, "4 pogingen (1 + 3 redirects)");
  ok(await fetchSafe("https://groot.nl/", "*/*") === null, "groter dan 2 MB");
  ok(await fetchSafe("http://169.254.169.254/latest/meta-data/", "*/*") === null, "metadata-IP");
});

Deno.test("huisstijl: naam, vierkant logo, kleur uit het logo", async () => {
  const r = await brand(new URL("https://bakkerij.nl/"));
  ok(r && r.name === "Bakkerij De Korf", JSON.stringify(r?.name));
  ok(r!.logo && r!.logo.length > 100, "logo");
  ok(r!.color === "#D9161E", "kleur uit het logo (theme-color wit telt niet): " + r!.color);
  ok(r!.text_color === "#FFFFFF" && r!.domain === "bakkerij.nl" && r!.source_url === "https://bakkerij.nl/", JSON.stringify(r));
  ok(!asked.includes("https://bakkerij.nl/icon.svg"), "geen svg");
});

Deno.test("opruimen", () => { globalThis.fetch = realFetch; (Deno as unknown as { resolveDns: unknown }).resolveDns = realDns; });
