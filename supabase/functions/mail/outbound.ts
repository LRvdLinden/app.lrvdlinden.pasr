// Pasr beheer › Mail: een uitgaande mail samenstellen (puur, getest in outbound_test.ts). Geeft opties voor nodemailer.
// Aan en CC komen echt in de kopregels; BCC alleen in de envelop (geen Bcc-kop, ook niet als de transport er een zou houden).
// Staat Aan leeg (alleen BCC), dan toont de To-kop de afzender zelf.
import { Buffer } from "node:buffer";
import { type Attachment, addressOf, type Brand, subjectFor } from "./logic.ts";
import { type Kind, renderMail } from "./layout.ts";

export type Outgoing = {
  brand: Brand; kind: Kind;
  /** "Naam <adres>" van het merk */
  from: string;
  /** envelop-afzender als de server het merkadres weigert (PASR_SMTP_FROM) */
  envelopeFrom?: string;
  replyTo?: string;
  to: string[]; cc: string[]; bcc: string[];
  subject: string; markdown: string;
  number?: number | null; messageId: string; inReplyTo?: string; references?: string[];
  attachments?: Attachment[];
  /** persoonlijke afmeldcode-urls (campagne/uitnodiging per ontvanger): eenklik-adres + pagina */
  unsub?: { page: string; oneClick?: string };
  vars?: { voornaam?: string };
};

export type BuiltMail = {
  from: string; to: string; cc?: string[]; replyTo?: string; subject: string; html: string; text: string;
  messageId: string; inReplyTo?: string; references?: string[];
  headers: Record<string, string>;
  envelope: { from: string; to: string[] };
  attachments: { filename: string; contentType: string; content: Buffer }[];
};

const oneLine = (s: string) => s.replace(/[\r\n]+/g, " ").trim();

export function buildMessage(o: Outgoing): BuiltMail {
  const sender = addressOf(o.from);
  const rendered = renderMail({
    brand: o.brand, kind: o.kind, subject: subjectFor(o.subject, o.number ?? undefined), markdown: o.markdown,
    unsubUrl: o.unsub?.page, vars: o.vars,
  });
  const headers: Record<string, string> = { "X-Pasr-Ticket": o.number ? String(o.number) : o.kind === "news" || o.kind === "invite" ? "campaign" : "mail" };
  if (o.unsub) {
    headers["List-Unsubscribe"] = o.unsub.oneClick ? `<${oneLine(o.unsub.oneClick)}>, <${oneLine(o.unsub.page)}>` : `<${oneLine(o.unsub.page)}>`;
    if (o.unsub.oneClick) headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click";
    headers["Precedence"] = "bulk";
  }
  const toHeader = o.to.length ? o.to.join(", ") : sender;
  const recipients = [...new Set([...o.to, ...o.cc, ...o.bcc])];
  return {
    from: o.from, to: toHeader, ...(o.cc.length ? { cc: o.cc } : {}), ...(o.replyTo ? { replyTo: o.replyTo } : {}),
    subject: rendered.subject, html: rendered.html, text: rendered.text,
    messageId: o.messageId, ...(o.inReplyTo ? { inReplyTo: o.inReplyTo } : {}), ...(o.references?.length ? { references: o.references } : {}),
    headers, envelope: { from: addressOf(o.envelopeFrom ?? o.from), to: recipients },
    attachments: (o.attachments ?? []).map((a) => ({ filename: a.name, contentType: a.type, content: Buffer.from(a.data.buffer, a.data.byteOffset, a.data.byteLength) })),
  };
}

// ---- afmeldlinks ----
export const UNSUB_PAGE = "https://pasr.nl/afmelden/";
/** Persoonlijke link naar pasr.nl/afmelden/ (k=nieuws: de pagina toont de tekst voor nieuwsbrieven). */
export const unsubPage = (token: string) => `${UNSUB_PAGE}?t=${encodeURIComponent(token)}&k=nieuws`;
/** Pagina zonder persoonlijke code (BCC-groepen): de ontvanger vult zijn e-mailadres in. s = users of owners. */
export const genericUnsubPage = (scope: "users" | "owners") => `${UNSUB_PAGE}?k=nieuws&s=${scope}`;
/** Eén klik uit het mailprogramma (RFC 8058): POST naar de functie mail zelf. */
export const oneClickUrl = (supabaseUrl: string, token: string) => `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/mail?stop=${encodeURIComponent(token)}`;
