// Mail met de eigenaarsuitnodiging (zakelijk 1.1): het beheer maakte een zaak aan voor iemand zonder Pasr-account.
// Getest in owner_mail_test.ts. Verstuurd via de SMTP-secrets PASR_SMTP_* (dezelfde als group-invite).

export const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

/** Alleen een link naar pasr.nl/zakelijk/uitnodiging/#<20 tekens>. */
export const okLink = (link: unknown) => typeof link === "string" && /^https:\/\/pasr\.nl\/zakelijk\/uitnodiging\/#[A-HJ-NP-Z2-9]{20}$/.test(link);

const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

export function ownerMail(business: string, city: string | null, link: string, expires: string | null) {
  const b = business.replace(/[\r\n]+/g, " ").slice(0, 60), place = (city ?? "").replace(/[\r\n]+/g, " ").slice(0, 60);
  const until = expires ? new Date(expires).toLocaleDateString("nl-NL", { day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Amsterdam" }) : "";
  const where = place ? `${b} in ${place}` : b;
  const subject = `Je zaak ${b} staat klaar in Pasr`;
  const text = `Hallo,\n\nPasr heeft ${where} voor je klaargezet als zaak in Pasr voor ondernemers: digitale stempelkaarten die je ` +
    `klanten in de app Pasr of in de browser bewaren.\n\nOpen deze link en log in met je Pasr-account (of maak er gratis een ` +
    `met dit e-mailadres). Daarna ben je eigenaar van de zaak en beheer je je kaarten, medewerkers en instellingen.\n\n${link}\n\n` +
    (until ? `De link werkt tot ${until} en één keer.\n\n` : "") +
    `Verwachtte je deze mail niet? Dan kun je hem negeren.\n\nPasr · https://pasr.nl/zakelijk/`;
  const html = `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
    `<title>${esc(subject)}</title></head><body style="margin:0;padding:0;background:#0A0B10">` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0A0B10"><tr><td align="center" style="padding:32px 16px">` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#15171F;border-radius:20px">` +
    `<tr><td style="padding:32px 28px;font-family:${FONT};color:#E9EAF0">` +
    `<div style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#6A5CFF;font-weight:700">Pasr voor ondernemers</div>` +
    `<h1 style="font-size:24px;line-height:1.25;margin:8px 0 14px;color:#ffffff">${esc(b)} staat klaar</h1>` +
    `<p style="font-size:16px;line-height:1.55;margin:0 0 14px">Pasr heeft <b style="color:#ffffff">${esc(where)}</b> voor je klaargezet: ` +
    `digitale stempelkaarten die je klanten bewaren in de app Pasr of in de browser.</p>` +
    `<p style="font-size:16px;line-height:1.55;margin:0 0 22px">Log in met je Pasr-account (of maak er gratis een met dit e-mailadres). ` +
    `Daarna ben je eigenaar en beheer je je kaarten, medewerkers en instellingen.</p>` +
    `<p style="margin:0 0 22px"><a href="${esc(link)}" style="display:inline-block;background:#6A5CFF;color:#ffffff;text-decoration:none;` +
    `font-weight:700;font-size:16px;padding:14px 22px;border-radius:12px">Zaak overnemen</a></p>` +
    `<p style="font-size:13px;line-height:1.5;margin:0;color:#9A9DAB">${until ? `De link werkt tot ${esc(until)} en één keer. ` : ""}` +
    `Verwachtte je deze mail niet? Dan kun je hem negeren.</p>` +
    `</td></tr></table></td></tr></table></body></html>`;
  return { subject, text, html };
}
