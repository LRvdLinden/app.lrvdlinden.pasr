// Pasr beheer › Mail: nieuwsbrieven en uitnodigingen naar een doelgroep (users of owners). Elke ontvanger krijgt een eigen mail
// met zijn voornaam, een persoonlijke afmeldlink (pasr.nl/afmelden/?t=…) en List-Unsubscribe(-Post) met één klik. De ronde stopt na
// een tijdsbudget; de cron gaat verder (pasr_mail_campaign_due). Wie al een mail kreeg, staat (als korte hash) in pasr_mail_campaign_sent.
// Afgemelden zijn al uit de doelgroep gehaald door de database (pasr_mail_audience). Nooit adressen loggen.
import { type Brand, fromFor, newMessageId, randomId } from "./logic.ts";
import { buildMessage, type BuiltMail, oneClickUrl, unsubPage } from "./outbound.ts";
import { replyToFor, type Rpc } from "./poll.ts";

export type CampaignDeps = {
  rpc: Rpc;
  env: (k: string) => string;
  send: (m: BuiltMail, brand: Brand) => Promise<{ ok: boolean; code?: string; permanent?: boolean }>;
  now?: () => number;
};
export type RoundResult = { claimed: boolean; sent: number; failed: number; status: string; left: number };

type Row = { email: string; first_name: string; token: string };
type Camp = { id: number; brand: Brand; audience: "users" | "owners" | "list"; subject: string; body_md: string; status: string };

/** Of de handtekening mee moet, staat in de opgeslagen tekst van de campagne (geen extra kolom): een regel aan het eind als hij uit staat. */
export const NO_SIGNATURE = "<!--pasr:geen-handtekening-->";
export const withSignatureFlag = (md: string, signature: boolean) => (signature ? md : `${md}\n\n${NO_SIGNATURE}`);
export function splitSignatureFlag(md: string): { body: string; signature: boolean } {
  const i = md.lastIndexOf(NO_SIGNATURE);
  return i >= 0 && md.slice(i + NO_SIGNATURE.length).trim() === "" ? { body: md.slice(0, i).trimEnd(), signature: false } : { body: md, signature: true };
}

async function call<T>(rpc: Rpc, name: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data as T;
}
const hashOf = (token: string) => token.slice(0, 26);
/** Elke 25 mails de voortgang wegschrijven en kijken of de campagne is afgebroken. */
export const BATCH = 25;
/** Na zoveel tijdelijke fouten achter elkaar stopt de ronde (de server of het netwerk heeft een probleem; de cron probeert later weer). */
export const MAX_TEMP_FAILS = 5;

export async function runCampaign(d: CampaignDeps, id: number, budgetMs: number): Promise<RoundResult> {
  const now = d.now ?? Date.now;
  const started = now();
  const out: RoundResult = { claimed: false, sent: 0, failed: 0, status: "unknown", left: 0 };
  if ((await call<boolean>(d.rpc, "pasr_mail_campaign_claim", { p_id: id, p_seconds: Math.ceil(budgetMs / 1000) + 60 })) !== true) return out;
  out.claimed = true;
  const camp = await call<Camp | null>(d.rpc, "pasr_mail_campaign_get", { p_id: id });
  if (!camp || camp.status !== "sending" || camp.audience === "list") {
    await d.rpc("pasr_mail_campaign_progress", { p_id: id, p_sent_hashes: [], p_failed: 0, p_done: false });
    out.status = camp?.status ?? "not_found";
    return out;
  }
  let sentHashes: string[] = [], failedHashes: string[] = [], failedCount = 0, temp = 0, aborted = false, stoppedEarly = false;
  const flush = async (done: boolean) => {
    const r = await call<{ status: string }>(d.rpc, "pasr_mail_campaign_progress", {
      p_id: id, p_sent_hashes: sentHashes, p_failed: failedCount, p_done: done, p_sent_extra: 0, p_failed_hashes: failedHashes,
    });
    out.sent += sentHashes.length; out.failed += failedCount; out.status = r.status;
    sentHashes = []; failedHashes = []; failedCount = 0;
    return r.status;
  };
  try {
    const rows = (await call<Row[] | null>(d.rpc, "pasr_mail_audience", { p_audience: camp.audience })) ?? [];
    const already = new Set(await call<string[] | null>(d.rpc, "pasr_mail_campaign_sent_hashes", { p_id: id }) ?? []);
    const todo = rows.filter((r) => !already.has(hashOf(r.token)));
    const atts = (await call<{ name: string; type: string; data_b64: string }[] | null>(d.rpc, "pasr_mail_campaign_attachments", { p_campaign: id })) ?? [];
    const attachments = atts.map((a) => ({ name: a.name, type: a.type, data: Uint8Array.from(atob(a.data_b64), (c) => c.charCodeAt(0)) }));
    const supabaseUrl = d.env("SUPABASE_URL");
    const { body: campBody, signature } = splitSignatureFlag(camp.body_md);
    let i = 0;
    for (; i < todo.length; i++) {
      if (now() - started > budgetMs) { stoppedEarly = true; break; }
      const r = todo[i];
      const m = buildMessage({
        brand: camp.brand, kind: "news", from: fromFor(camp.brand, d.env), replyTo: replyToFor(d.env, camp.brand), to: [r.email], cc: [], bcc: [],
        subject: camp.subject, markdown: campBody, signature, messageId: newMessageId(null, randomId()), attachments,
        unsub: { page: unsubPage(r.token), oneClick: oneClickUrl(supabaseUrl, r.token) }, vars: { voornaam: r.first_name },
      });
      const res = await d.send(m, camp.brand);
      if (res.ok) { sentHashes.push(hashOf(r.token)); temp = 0; }
      else if (res.permanent) { failedHashes.push(hashOf(r.token)); failedCount++; temp = 0; }
      else if (++temp >= MAX_TEMP_FAILS) { stoppedEarly = true; break; }
      if ((i + 1) % BATCH === 0) {
        const st = await flush(false);
        if (st !== "sending") { aborted = true; break; }
      }
    }
    out.left = Math.max(0, todo.length - i);
    if (!aborted) await flush(!stoppedEarly && i >= todo.length);
    else out.left = 0;
  } catch (e) {
    console.error("mail campaign", id, String((e as Error)?.message ?? e).replace(/[^\s@]+@[^\s@]+/g, "…").slice(0, 120));
    await flush(false).catch(() => {});
  }
  return out;
}

/** Alle lopende campagnes zonder ronde (cron), binnen het tijdsbudget. */
export async function continueCampaigns(d: CampaignDeps, budgetMs: number): Promise<number> {
  const now = d.now ?? Date.now;
  const started = now();
  const ids = (await call<number[] | null>(d.rpc, "pasr_mail_campaign_due", {})) ?? [];
  let n = 0;
  for (const id of ids) {
    const left = budgetMs - (now() - started);
    if (left < 5000) break;
    const r = await runCampaign(d, Number(id), left);
    if (r.claimed) n++;
  }
  return n;
}
