// Pasr beheer › Mail: de huisstijl van uitgaande mails voor de merken Pasr en Pasr Zakelijk (kop, alinea, knop, citaat, afbeelding,
// voet). Zelfde kleuren, lettertype en opbouw als de accountmails (supabase/templates/build.py) en de herinneringen
// (reminder-mail): donkere kaart #15171F op #0A0B10, accentbalk en knop in het merk, tabellen met inline stijlen. Voor de lichte
// modus staat er een <style> met prefers-color-scheme (clients die dat niet kennen, tonen de donkere variant).
// Pasr: iris #6A5CFF (de app). Pasr Zakelijk: mint #2ED3A6 (de stempel in het zakelijke icoon) met eigen icoon en kop
// "Pasr voor ondernemers". Alles wat de beheerder typt komt via markdown.ts (alles ge-escaped).
import type { Brand } from "./logic.ts";
import { REPLY_MARKER } from "./mime.ts";
import { esc, renderMarkdown, type Theme, type Vars } from "./markdown.ts";

export const SITE = "https://pasr.nl";
const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
const INK = "#0A0B10", PANEL = "#15171F", MUTED = "#9A9DAB";

export { REPLY_MARKER };
export type BrandStyle = {
  name: string; eyebrow: string; icon: string; site: string; siteLabel: string; accent: string; buttonFg: string;
  link: string; lightLink: string; theme: Theme; fromName: string;
};
export const BRAND_STYLE: Record<Brand, BrandStyle> = {
  pasr: {
    name: "Pasr", eyebrow: "Bericht van Pasr", icon: `${SITE}/assets/mail-icon.png`, site: SITE, siteLabel: "pasr.nl",
    accent: "#6A5CFF", buttonFg: "#ffffff", link: "#6A5CFF", lightLink: "#4A3CE0", fromName: "Pasr",
    theme: { text: "#E9EAF0", heading: "#ffffff", muted: MUTED, link: "#8F86FF", accent: "#6A5CFF", buttonBg: "#6A5CFF", buttonFg: "#ffffff", codeBg: "#1C1F29", rule: "#262935" },
  },
  zakelijk: {
    name: "Pasr Zakelijk", eyebrow: "Pasr voor ondernemers", icon: `${SITE}/assets/mail-icon-zakelijk.png`, site: `${SITE}/zakelijk/`, siteLabel: "pasr.nl/zakelijk",
    accent: "#2ED3A6", buttonFg: "#0A0B10", link: "#2ED3A6", lightLink: "#0E7A5C", fromName: "Pasr Zakelijk",
    theme: { text: "#E9EAF0", heading: "#ffffff", muted: MUTED, link: "#2ED3A6", accent: "#2ED3A6", buttonBg: "#2ED3A6", buttonFg: "#0A0B10", codeBg: "#1C1F29", rule: "#262935" },
  },
};

export type Kind = "reply" | "mail" | "news" | "invite";
export type MailInput = {
  brand: Brand; subject: string; markdown: string; kind: Kind;
  /** afmeldlink (verplicht bij news en invite; de voet toont hem) */
  unsubUrl?: string; vars?: Vars; preheader?: string;
};
export type MailOut = { subject: string; html: string; text: string };

function lightCss(b: BrandStyle): string {
  return `<style>:root{color-scheme:light dark;supported-color-schemes:light dark}@media (prefers-color-scheme: light){` +
    `body,.pm-bg{background:#F4F3FF !important}.pm-panel{background:#ffffff !important}.pm-tx{color:#17162A !important}` +
    `.pm-h{color:#17162A !important}.pm-m,.pm-q{color:#6B6880 !important}.pm-a{color:${b.lightLink} !important}` +
    `.pm-code{background:#EEEDF8 !important}.pm-hr{background:#E3E5EC !important}.pm-wm{color:#17162A !important}}</style>`;
}

/** De hele mail (HTML en platte tekst) in de stijl van het merk. */
export function renderMail(o: MailInput): MailOut {
  const b = BRAND_STYLE[o.brand];
  const { html: inner, text: innerText } = renderMarkdown(o.markdown, b.theme, o.vars ?? {});
  const subject = o.subject.replace(/[\r\n]+/g, " ").trim();
  const pre = (o.preheader ?? innerText.replace(/\s+/g, " ").trim()).slice(0, 140);
  const wm = `<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>` +
    `<td style="width:40px;vertical-align:middle"><img src="${b.icon}" width="40" height="40" alt="${esc(b.name)}" style="display:block;width:40px;height:40px;border:0;border-radius:9px;color:#ffffff;font-size:12px"></td>` +
    `<td class="pm-wm" style="padding-left:10px;font-size:26px;font-weight:800;letter-spacing:-0.5px;color:#ffffff;font-family:${FONT}">pasr</td></tr></table>`;
  // bovenaan (vóór de kop), zodat een antwoord dat onze mail citeert vanaf deze regel wordt afgeknipt (stripReply)
  const marker = o.kind === "reply"
    ? `<tr><td class="pm-m" style="padding:0 4px 14px;font-size:11px;line-height:16px;color:${MUTED};letter-spacing:.2px">${esc(REPLY_MARKER)}</td></tr>\n` : "";
  const unsub = o.unsubUrl
    ? `<br>${o.kind === "invite" ? "Je krijgt deze mail omdat Pasr je uitnodigt om kennis te maken." : "Je krijgt deze nieuwsbrief van Pasr."} Geen mails meer? ` +
      `<a class="pm-a" href="${esc(o.unsubUrl)}" style="color:${MUTED}">Meld je hier af</a>.`
    : "";
  const html = `<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"><title>${esc(subject)}</title>${lightCss(b)}</head>
<body class="pm-bg" style="margin:0;padding:0;background:${INK}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${INK}">${esc(pre)}</div>
<table class="pm-bg" role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${INK}" style="background:${INK}"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;font-family:${FONT}">
${marker}<tr><td style="padding:0 4px 22px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="vertical-align:middle">${wm}</td>
<td class="pm-m" align="right" style="vertical-align:middle;font-size:13px;font-weight:700;color:${MUTED};letter-spacing:.3px">${esc(b.eyebrow)}</td>
</tr></table></td></tr>
<tr><td class="pm-panel" bgcolor="${PANEL}" style="background:${PANEL};border-radius:18px;padding:32px 30px 24px">
<div style="height:6px;width:64px;border-radius:3px;background:${b.accent};font-size:0;line-height:0;margin:0 0 22px">&nbsp;</div>
${inner}
</td></tr>
<tr><td class="pm-m" style="padding:22px 6px 0;font-size:12px;line-height:18px;color:${MUTED}">
<a class="pm-a" href="${b.site}" style="color:${MUTED}">${b.siteLabel}</a> · <a class="pm-a" href="${SITE}/privacy/" style="color:${MUTED}">Privacy</a> · <a class="pm-a" href="${SITE}/support/" style="color:${MUTED}">Hulp</a>${unsub}
</td></tr>
</table></td></tr></table>
</body></html>`;
  const text = [
    o.kind === "reply" ? REPLY_MARKER + "\n" : "",
    innerText, "",
    "--",
    `${b.name} · ${b.site}`,
    o.unsubUrl ? `Geen mails meer? Meld je af: ${o.unsubUrl}` : "",
  ].filter((l, i) => i > 0 || l).join("\n").replace(/\n{4,}/g, "\n\n\n").trim() + "\n";
  return { subject, html, text };
}
