// Pasr beheer › Mail: een kleine, veilige Markdown-renderer zonder npm-pakketten (getest in markdown_test.ts).
//
// Wat de beheerder typt gaat eerst naar een boom (parseMarkdown) en wordt daarna als HTML en als platte tekst uitgegeven
// (renderDoc). Er komt NOOIT ruwe HTML door: alle tekst gaat door esc(), links alleen https of mailto (zonder wachtwoord in
// de url), afbeeldingen alleen https. Ondersteund:
//   # kop, ## kop, ### kop · **vet** · *cursief* · `code` · ~~doorgestreept~~ · - lijst · 1. lijst · > citaat · --- lijn
//   [tekst](https://…) · https://… (los adres) · knop op een eigen regel: [[Knoptekst|https://…]] · ![alt](https://…)
//   een regeleinde in een alinea is een harde regelafbreking · \* maakt een teken letterlijk
//   {{voornaam}} (leeg = "daar"); {{email}} is niet toegestaan (zie markdownProblem)
import type { Brand } from "./logic.ts";

export type Inline =
  | { t: "text"; v: string } | { t: "code"; v: string } | { t: "br" } | { t: "var"; name: "voornaam" }
  | { t: "b" | "i" | "s"; c: Inline[] }
  | { t: "a"; href: string; c: Inline[] }
  | { t: "img"; alt: string; src: string };
export type Block =
  | { t: "p"; c: Inline[] }
  | { t: "h"; level: 1 | 2 | 3; c: Inline[] }
  | { t: "list"; ordered: boolean; start: number; items: Inline[][] }
  | { t: "quote"; c: Block[] }
  | { t: "hr" }
  | { t: "button"; text: string; href: string }
  | { t: "img"; alt: string; src: string };
export type Doc = Block[];

/** Kleuren van een merk; de klassen (pm-…) laten de lichte modus ze in de layout overschrijven. */
export type Theme = {
  text: string; heading: string; muted: string; link: string; accent: string; buttonBg: string; buttonFg: string;
  codeBg: string; rule: string;
};

export const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

// ---------------------------------------------------------------------------------------------------- adressen
/** https-adres (zonder gebruikersnaam of wachtwoord) of mailto: met een geldig adres; anders null. Geeft het genormaliseerde adres. */
export function safeUrl(raw: string, allow: { mailto?: boolean } = { mailto: true }): string | null {
  const s = raw.trim();
  if (!s || s.length > 2000 || /[\s\u0000-\u001f\u007f"'<>\\`]/.test(s)) return null;
  if (/^mailto:/i.test(s)) {
    if (!allow.mailto) return null;
    const addr = s.slice(7).split("?")[0];
    let dec: string;
    try { dec = decodeURIComponent(addr); } catch { return null; }
    if (!/^[^\s@<>()",;:\\[\]]{1,64}@[A-Za-z0-9.-]{1,200}\.[A-Za-z]{2,}$/.test(dec)) return null;
    return "mailto:" + s.slice(7);
  }
  let u: URL;
  try { u = new URL(s); } catch { return null; }
  if (u.protocol !== "https:" || u.username || u.password || !u.hostname.includes(".")) return null;
  return u.href;
}

// ---------------------------------------------------------------------------------------------------- inline
const PUNCT = /[\\`*_{}\[\]()#+\-.!~|<>]/;
const WS = /\s/;
const WINDOW = 3000;   // zoekvenster voor een sluitteken: houdt rommelinvoer lineair

function closeBracket(s: string, i: number): number {
  // i staat op "["; geeft de index van de bijbehorende "]" (geneste haakjes tellen), of -1
  let d = 0;
  for (let j = i; j < Math.min(s.length, i + WINDOW); j++) {
    const c = s[j];
    if (c === "\\") { j++; continue; }
    if (c === "[") d++;
    else if (c === "]" && --d === 0) return j;
    else if (c === "\n" && s[j + 1] === "\n") return -1;
  }
  return -1;
}
function closeParen(s: string, i: number): number {
  let d = 0;
  for (let j = i; j < Math.min(s.length, i + 2100); j++) {
    const c = s[j];
    if (c === "(") d++;
    else if (c === ")" && --d === 0) return j;
  }
  return -1;
}
/** "url" of "url "titel"" uit de haakjes van een link; de titel wordt genegeerd. */
const urlOf = (inner: string) => inner.trim().split(/\s+/)[0].replace(/^<|>$/g, "");

function findCloser(s: string, from: number, marker: string, lim: number): number {
  for (let j = from; j <= lim - marker.length; j++) {
    if (s[j] === "\\") { j++; continue; }
    if (s.startsWith(marker, j) && j > from && !WS.test(s[j - 1])) {
      let k = j;
      if (marker.length === 2) while (s[k + 2] === marker[0]) k++;   // ***x***: sluit met de laatste twee
      else if (s[j + 1] === marker) continue;   // een enkele * of _ sluit niet op een dubbele
      return k;
    }
  }
  return -1;
}

export function parseInline(s: string, opts: { nolink?: boolean; depth?: number } = {}): Inline[] {
  const depth = opts.depth ?? 0;
  const out: Inline[] = [];
  let buf = "";
  const flush = () => { if (buf) { out.push({ t: "text", v: buf }); buf = ""; } };
  const n = s.length;
  if (depth > 6) return [{ t: "text", v: s }];
  for (let i = 0; i < n;) {
    const c = s[i];
    if (c === "\\" && i + 1 < n) {
      if (s[i + 1] === "\n") { buf = buf.replace(/ +$/, ""); flush(); out.push({ t: "br" }); i += 2; continue; }
      if (PUNCT.test(s[i + 1])) { buf += s[i + 1]; i += 2; continue; }
    }
    if (c === "\n") { buf = buf.replace(/ +$/, ""); flush(); out.push({ t: "br" }); i++; continue; }
    if (c === "`") {
      const j = s.indexOf("`", i + 1);
      if (j > i + 1 && j - i < WINDOW) { flush(); out.push({ t: "code", v: s.slice(i + 1, j).replace(/\n/g, " ") }); i = j + 1; continue; }
    }
    if (c === "{" && s[i + 1] === "{") {
      const m = /^\{\{\s*([A-Za-z]{1,20})\s*\}\}/.exec(s.slice(i, i + 40));
      if (m && m[1].toLowerCase() === "voornaam") { flush(); out.push({ t: "var", name: "voornaam" }); i += m[0].length; continue; }
    }
    if (c === "!" && s[i + 1] === "[") {
      const j = closeBracket(s, i + 1);
      if (j > 0 && s[j + 1] === "(") {
        const k = closeParen(s, j + 1);
        const src = k > 0 ? safeUrl(urlOf(s.slice(j + 2, k)), {}) : null;
        if (src) { flush(); out.push({ t: "img", alt: s.slice(i + 2, j).replace(/[\\\n]/g, " ").slice(0, 200), src }); i = k + 1; continue; }
      }
    }
    if (c === "[" && s[i + 1] === "[") {
      const m = /^\[\[([^\]|\n]{1,80})\|([^\]\s]{1,2000})\]\]/.exec(s.slice(i, i + 2100));
      if (m) {
        const href = opts.nolink ? null : safeUrl(m[2]);
        flush();
        out.push(href ? { t: "a", href, c: [{ t: "text", v: m[1].trim() }] } : { t: "text", v: m[1].trim() });
        i += m[0].length; continue;
      }
    }
    if (c === "[") {
      const j = closeBracket(s, i);
      if (j > 0 && s[j + 1] === "(") {
        const k = closeParen(s, j + 1);
        if (k > 0) {
          const href = opts.nolink ? null : safeUrl(urlOf(s.slice(j + 2, k)));
          const kids = parseInline(s.slice(i + 1, j), { nolink: true, depth: depth + 1 });
          flush();
          if (href) out.push({ t: "a", href, c: kids }); else out.push(...kids);
          i = k + 1; continue;
        }
      }
    }
    if (c === "h" && !opts.nolink && s.startsWith("https://", i) && (i === 0 || !/[A-Za-z0-9]/.test(s[i - 1]))) {
      const m = /^https:\/\/[^\s<>"'`]+/.exec(s.slice(i, i + 2100));
      if (m) {
        const raw = m[0].replace(/[.,;:!?)\]*_~]+$/, "");
        const href = safeUrl(raw, {});
        if (href) { flush(); out.push({ t: "a", href, c: [{ t: "text", v: raw }] }); i += raw.length; continue; }
      }
    }
    if (c === "*" || c === "_" || c === "~") {
      const dbl = s[i + 1] === c;
      const marker = dbl ? c + c : c;
      const after = s[i + marker.length] ?? "";
      const intra = c === "_" && i > 0 && /[A-Za-z0-9]/.test(s[i - 1]);
      if (!(c === "~" && !dbl) && after && !WS.test(after) && !intra && !(!dbl && after === c)) {
        const lim = Math.min(n, i + WINDOW);
        const j = findCloser(s, i + marker.length, marker, lim);
        const endOk = j < 0 || c !== "_" || !/[A-Za-z0-9]/.test(s[j + (dbl && s[j + 2] === c ? 3 : marker.length)] ?? "");
        if (j > 0 && endOk) {
          flush();
          const end = j + marker.length;
          const kids = parseInline(s.slice(i + marker.length, j), { nolink: opts.nolink, depth: depth + 1 });
          out.push({ t: c === "~" ? "s" : dbl ? "b" : "i", c: kids });
          i = end; continue;
        }
      }
    }
    buf += c; i++;
  }
  flush();
  return out;
}

// ---------------------------------------------------------------------------------------------------- blokken
const HR = /^ {0,3}([-*_])(?: *\1){2,} *$/;
const HEAD = /^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$/;
const ITEM = /^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$/;
const QUOTE = /^ {0,3}>\s?(.*)$/;
const BUTTON = /^\s*\[\[([^\]|]{1,80})\|(\S{1,2000})\]\]\s*$/;
const IMAGE = /^\s*!\[([^\]]{0,200})\]\((\S+?)(?:\s+"[^"]*")?\)\s*$/;

const startsBlock = (l: string) => HR.test(l) || HEAD.test(l) || ITEM.test(l) || QUOTE.test(l) || BUTTON.test(l) || IMAGE.test(l);

export function parseBlocks(lines: string[], depth = 0): Block[] {
  const out: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    if (HR.test(l)) { out.push({ t: "hr" }); i++; continue; }
    let m = HEAD.exec(l);
    if (m) { out.push({ t: "h", level: Math.min(3, m[1].length) as 1 | 2 | 3, c: parseInline(m[2]) }); i++; continue; }
    m = BUTTON.exec(l);
    if (m) {
      const href = safeUrl(m[2]);
      if (href) { out.push({ t: "button", text: m[1].trim(), href }); i++; continue; }
    }
    m = IMAGE.exec(l);
    if (m) {
      const src = safeUrl(m[2], {});
      if (src) { out.push({ t: "img", alt: m[1].replace(/\\/g, "").slice(0, 200), src }); i++; continue; }
    }
    if (QUOTE.test(l) && depth < 4) {
      const inner: string[] = [];
      while (i < lines.length && QUOTE.test(lines[i])) { inner.push(QUOTE.exec(lines[i])![1]); i++; }
      out.push({ t: "quote", c: parseBlocks(inner, depth + 1) });
      continue;
    }
    m = ITEM.exec(l);
    if (m) {
      const ordered = /\d/.test(m[2]);
      const items: string[] = [];
      const start = ordered ? Math.min(999999, parseInt(m[2], 10)) : 1;
      while (i < lines.length) {
        const im = ITEM.exec(lines[i]);
        if (im && !HR.test(lines[i]) && /\d/.test(im[2]) === ordered) { items.push(im[3]); i++; continue; }
        if (!lines[i].trim()) {
          // een lege regel gevolgd door een item van dezelfde lijst: de lijst gaat door
          const next = lines.slice(i + 1).find((x) => x.trim());
          const nm = next ? ITEM.exec(next) : null;
          if (nm && !HR.test(next!) && /\d/.test(nm[2]) === ordered) { i++; continue; }
          break;
        }
        if (/^\s{2,}\S/.test(lines[i]) && !startsBlock(lines[i].trim()) && items.length) { items[items.length - 1] += "\n" + lines[i].trim(); i++; continue; }
        break;
      }
      out.push({ t: "list", ordered, start, items: items.map((x) => parseInline(x)) });
      continue;
    }
    const para: string[] = [];
    while (i < lines.length && lines[i].trim() && (para.length === 0 || !startsBlock(lines[i]))) { para.push(lines[i].replace(/^\s+/, "")); i++; }
    out.push({ t: "p", c: parseInline(para.join("\n")) });
  }
  return out;
}

export function parseMarkdown(md: string): Doc {
  const text = String(md ?? "").replace(/\r\n?/g, "\n").replace(/\t/g, "    ").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f​-‏‪-‮⁦-⁩﻿]/g, "");
  return parseBlocks(text.split("\n"));
}

/** Controle vooraf: {{email}} is niet toegestaan (het beheer toont geen adressen in mails). null = goed. */
export function markdownProblem(md: string): "bad_body" | null {
  return /\{\{\s*e-?mail\s*\}\}/i.test(md) ? "bad_body" : null;
}

// ---------------------------------------------------------------------------------------------------- uitvoer
export type Vars = { voornaam?: string };
const name = (v: Vars) => (v.voornaam ?? "").trim() || "daar";
const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

function inlineHtml(list: Inline[], t: Theme, v: Vars): string {
  return list.map((x): string => {
    switch (x.t) {
      case "text": return esc(x.v);
      case "var": return esc(name(v));
      case "br": return "<br>";
      case "code": return `<code class="pm-code" style="background:${t.codeBg};border-radius:5px;padding:1px 5px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px">${esc(x.v)}</code>`;
      case "b": return `<strong>${inlineHtml(x.c, t, v)}</strong>`;
      case "i": return `<em>${inlineHtml(x.c, t, v)}</em>`;
      case "s": return `<s>${inlineHtml(x.c, t, v)}</s>`;
      case "a": return `<a class="pm-a" href="${esc(x.href)}" style="color:${t.link};text-decoration:underline">${inlineHtml(x.c, t, v)}</a>`;
      case "img": return `<img src="${esc(x.src)}" alt="${esc(x.alt)}" style="max-width:100%;height:auto;border:0;border-radius:8px;vertical-align:middle">`;
    }
  }).join("");
}
function inlineText(list: Inline[], v: Vars): string {
  return list.map((x): string => {
    switch (x.t) {
      case "text": return x.v;
      case "var": return name(v);
      case "br": return "\n";
      case "code": return x.v;
      case "b": case "i": case "s": return inlineText(x.c, v);
      case "a": {
        const label = inlineText(x.c, v), shown = x.href.replace(/^mailto:/, "");
        const same = (a: string, b: string) => a.replace(/\/$/, "") === b.replace(/\/$/, "");
        return !label || same(label, x.href) || same(label, shown) ? shown : `${label} (${shown})`;
      }
      case "img": return x.alt ? `${x.alt} (${x.src})` : x.src;
    }
  }).join("");
}

export function blocksHtml(doc: Doc, t: Theme, v: Vars = {}): string {
  return doc.map((b): string => {
    switch (b.t) {
      case "p": return `<p class="pm-tx" style="margin:0 0 14px;font-size:15px;line-height:23px;color:${t.text};word-break:break-word">${inlineHtml(b.c, t, v)}</p>`;
      case "h": {
        const size = b.level === 1 ? 24 : b.level === 2 ? 20 : 17, lh = size + 6;
        return `<h${b.level + 1} class="pm-h" style="margin:6px 0 12px;font-size:${size}px;line-height:${lh}px;font-weight:800;color:${t.heading}">${inlineHtml(b.c, t, v)}</h${b.level + 1}>`;
      }
      case "list": {
        const tag = b.ordered ? "ol" : "ul";
        const start = b.ordered && b.start !== 1 ? ` start="${b.start}"` : "";
        return `<${tag}${start} class="pm-tx" style="margin:0 0 14px;padding-left:22px;font-size:15px;line-height:23px;color:${t.text}">` +
          b.items.map((it) => `<li style="margin:0 0 6px">${inlineHtml(it, t, v)}</li>`).join("") + `</${tag}>`;
      }
      case "quote": return `<blockquote class="pm-q" style="margin:0 0 14px;padding:2px 0 2px 14px;border-left:3px solid ${t.accent};color:${t.muted}">${blocksHtml(b.c, t, v)}</blockquote>`;
      case "hr": return `<div class="pm-hr" style="height:1px;background:${t.rule};margin:20px 0;font-size:0;line-height:0">&nbsp;</div>`;
      case "button":
        return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:6px 0 18px"><tr><td align="center" bgcolor="${t.buttonBg}" style="border-radius:12px;background:${t.buttonBg}">` +
          `<a href="${esc(b.href)}" style="display:inline-block;padding:14px 28px;font-family:${FONT};font-size:16px;font-weight:700;line-height:20px;color:${t.buttonFg};text-decoration:none;border-radius:12px">${esc(b.text)}</a></td></tr></table>`;
      case "img": return `<img src="${esc(b.src)}" alt="${esc(b.alt)}" style="display:block;max-width:100%;height:auto;border:0;border-radius:12px;margin:0 0 14px">`;
    }
  }).join("\n");
}

export function blocksText(doc: Doc, v: Vars = {}, prefix = ""): string {
  const lines: string[] = [];
  const pre = (s: string) => s.split("\n").map((l) => prefix + l).join("\n");
  for (const b of doc) {
    switch (b.t) {
      case "p": lines.push(pre(inlineText(b.c, v))); break;
      case "h": { const t = inlineText(b.c, v); lines.push(pre(b.level === 1 ? `${t.toUpperCase()}\n${"=".repeat(Math.min(40, t.length))}` : t)); break; }
      case "list": lines.push(pre(b.items.map((it, k) => `${b.ordered ? `${b.start + k}.` : "-"} ${inlineText(it, v).replace(/\n/g, "\n   ")}`).join("\n"))); break;
      case "quote": lines.push(blocksText(b.c, v, prefix + "> ")); break;
      case "hr": lines.push(pre("----------")); break;
      case "button": lines.push(pre(`${b.text}: ${b.href.replace(/^mailto:/, "")}`)); break;
      case "img": lines.push(pre(b.alt ? `${b.alt} (${b.src})` : b.src)); break;
    }
  }
  return lines.join("\n\n");
}

/** Platte tekst (bv. een antwoord per mail van een medewerker) veilig als Markdown: tekens met een betekenis worden letterlijk. */
export function plainToMarkdown(text: string): string {
  return String(text ?? "").replace(/\r\n?/g, "\n").split("\n").map((l) =>
    l.replace(/[\\`*_\[\]~{}<]/g, "\\$&").replace(/^(\s*)([-+#>!]|\d{1,9}[.)])(?=\s|$|#)/, (_m, sp: string, tok: string) => sp + tok.replace(/^(\d{1,9})([.)])$/, "$1\\$2").replace(/^([-+#>!])$/, "\\$1"))
  ).join("\n");
}
/** Platte tekst als veilige HTML (alinea's, regeleinden); voor het opslaan van binnengekomen mail in het ticket. */
export function textToHtml(text: string): string {
  return String(text ?? "").replace(/\r\n?/g, "\n").split(/\n{2,}/).filter((p) => p.trim()).map((p) => `<p>${esc(p).replace(/\n/g, "<br>")}</p>`).join("");
}

/** Markdown naar de inhoud van de mail (zonder kop en voet; die zet layout.ts erom). */
export function renderMarkdown(md: string, theme: Theme, vars: Vars = {}): { html: string; text: string } {
  const doc = parseMarkdown(md);
  return { html: blocksHtml(doc, theme, vars), text: blocksText(doc, vars) };
}
export type { Brand };
