// Tests voor poll.ts (handleMail) met een nep-database; de IMAP-kant staat in inbox_test.ts:
//   deno test --no-check --allow-net=127.0.0.1 supabase/functions/mail/poll_test.ts
import { boxes, handleMail, ownAddresses, pickAttachments, replyToFor } from "./poll.ts";
import { parseMessage } from "./mime.ts";

function eq(a: unknown, b: unknown, msg = "") {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg} verwacht ${y}, kreeg ${x}`);
}
function ok(v: unknown, msg = "") { if (!v) throw new Error(`niet waar: ${msg}`); }

const env = (m: Record<string, string>) => (k: string) => m[k] ?? "";
const E = env({ PASR_IMAP_HOST: "imap.x.nl", PASR_IMAP_USER: "inbox@pasr.nl", PASR_IMAP_PASSWORD: "p", PASR_MAIL_AGENTS: "leon@pasr.nl" });

function mail(o: { from?: string; to?: string; subject: string; id: string; body?: string; irt?: string; extra?: string[]; att?: boolean }) {
  const h = [`From: ${o.from ?? "klant@x.nl"}`, `To: ${o.to ?? "inbox@pasr.nl"}`, `Subject: ${o.subject}`, `Message-ID: ${o.id}`, "MIME-Version: 1.0", ...(o.irt ? [`In-Reply-To: ${o.irt}`, `References: ${o.irt}`] : []), ...(o.extra ?? [])];
  if (!o.att) return parseMessage([...h, "Content-Type: text/plain; charset=utf-8", "", o.body ?? "Hallo, ik heb een vraag over mijn kaart.", ""].join("\r\n"), { keepBytes: 30_000_000 });
  return parseMessage([...h, 'Content-Type: multipart/mixed; boundary="B"', "", "--B", "Content-Type: text/plain; charset=utf-8", "", o.body ?? "Zie bijlage", "--B",
    'Content-Type: application/pdf; name="a.pdf"', 'Content-Disposition: attachment; filename="a.pdf"', "Content-Transfer-Encoding: base64", "", btoa("PDF-DATA"), "--B--", ""].join("\r\n"), { keepBytes: 30_000_000 });
}

function fake(opts: { tickets?: Record<string, unknown>[]; exists?: boolean; recent?: number } = {}) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const rpc = (name: string, args: Record<string, unknown> = {}) => {
    calls.push({ name, args });
    switch (name) {
      case "pasr_mail_message_exists": return Promise.resolve({ data: !!opts.exists, error: null });
      case "pasr_mail_threads_for": return Promise.resolve({ data: opts.tickets ?? [], error: null });
      case "pasr_mail_contact_recent": return Promise.resolve({ data: opts.recent ?? 0, error: null });
      case "pasr_mail_thread_create": return Promise.resolve({ data: 1001, error: null });
      case "pasr_mail_message_add": return Promise.resolve({ data: { id: "m1", duplicate: false }, error: null });
      case "pasr_mail_thread_meta": return Promise.resolve({ data: { subject: "Vraag", ids: ["<pasr-ticket-1001.abcdef@pasr.nl>"] }, error: null });
      default: return Promise.resolve({ data: null, error: null });
    }
  };
  return { rpc, calls };
}
const ctxOf = (f: ReturnType<typeof fake>, e = E, sent: unknown[] = []) => ({
  rpc: f.rpc, env: e, box: "pasr" as const, agents: ["leon@pasr.nl"], authserv: [],
  send: (m: unknown) => { sent.push(m); return Promise.resolve({ ok: true }); },
});

Deno.test("brievenbussen en eigen adressen", () => {
  eq(boxes(env({})), []);
  eq(boxes(E).map((b) => b.brand), ["pasr"]);
  eq(boxes(env({ PASR_IMAP_HOST: "h", PASR_IMAP_USER: "a@pasr.nl", PASR_IMAP_PASSWORD: "p", PASR_IMAP_ZAKELIJK_USER: "z@pasr.nl", PASR_IMAP_ZAKELIJK_PASSWORD: "q" })).map((b) => b.brand), ["pasr", "zakelijk"]);
  ok(ownAddresses(E).includes("inbox@pasr.nl") && ownAddresses(E).includes("support@pasr.nl") && ownAddresses(E).includes("zakelijk@pasr.nl"));
  eq(replyToFor(E, "pasr"), "inbox@pasr.nl");
  eq(replyToFor(env({}), "zakelijk"), "zakelijk@pasr.nl");
});

Deno.test("nieuwe mail van een klant wordt een ticket met de mail als eerste bericht", async () => {
  const f = fake();
  const r = await handleMail(mail({ subject: "Vraag over kaart", id: "<k1@x.nl>" }), ctxOf(f));
  eq([r.result, r.ticket, r.seen, r.move], ["new_ticket", 1001, true, true]);
  const add = f.calls.find((c) => c.name === "pasr_mail_message_add")!.args;
  eq([add.p_direction, add.p_from, add.p_status, add.p_brand], ["in", "klant@x.nl", "new", "pasr"]);
  ok(String(add.p_text).includes("vraag over mijn kaart"));
});

Deno.test("dubbele mail en te veel nieuwe tickets per uur worden niet verwerkt", async () => {
  eq((await handleMail(mail({ subject: "x", id: "<k1@x.nl>" }), ctxOf(fake({ exists: true })))).result, "duplicate");
  const r = await handleMail(mail({ subject: "Vraag", id: "<k2@x.nl>" }), ctxOf(fake({ recent: 3 })));
  eq(r.result, "rejected:rate_limited");
  eq(r.move, false);
});

Deno.test("antwoord van de klant op een ticket komt in dat ticket (nummer in het onderwerp)", async () => {
  const f = fake({ tickets: [{ number: 1001, email: "klant@x.nl", status: "pending", brand: "pasr", mids: [] }] });
  const r = await handleMail(mail({ subject: "Re: [#1001] Vraag", id: "<k3@x.nl>", body: "Dank, dat werkt." }), ctxOf(f));
  eq([r.result, r.ticket], ["imported", 1001]);
  const add = f.calls.find((c) => c.name === "pasr_mail_message_add")!.args;
  eq([add.p_number, add.p_direction, add.p_status], [1001, "in", "open"]);
  ok(!f.calls.some((c) => c.name === "pasr_mail_thread_create"), "geen nieuw ticket");
});

Deno.test("automatische mail (Auto-Submitted) wordt genegeerd", async () => {
  const f = fake();
  const r = await handleMail(mail({ subject: "Afwezig", id: "<a1@x.nl>", extra: ["Auto-Submitted: auto-replied"] }), ctxOf(f));
  ok(r.result.startsWith("ignored"), r.result);
  ok(!f.calls.some((c) => c.name === "pasr_mail_message_add"));
});

Deno.test("bijlagen van een klant worden opgeslagen", async () => {
  const f = fake();
  await handleMail(mail({ subject: "Met bijlage", id: "<k4@x.nl>", att: true }), ctxOf(f));
  const at = f.calls.find((c) => c.name === "pasr_mail_attach")!.args;
  eq([at.p_message, at.p_name, at.p_type, at.p_b64], ["m1", "a.pdf", "application/pdf", btoa("PDF-DATA")]);
});

Deno.test("bijlagen boven 20 MB in totaal verliezen hun bytes", () => {
  const m = mail({ subject: "x", id: "<z@x.nl>", att: true });
  m.attachments.push({ filename: "groot.bin", contentType: "application/octet-stream", size: 21_000_000, data: new Uint8Array(21_000_000) } as never);
  const kept = pickAttachments(m);
  eq(kept.map((a) => a.filename), ["a.pdf"]);
});

Deno.test("antwoord van een medewerker per mail gaat gebrand naar de klant (alleen als SPF/DKIM klopt)", async () => {
  const t = [{ number: 1001, email: "klant@x.nl", status: "open", brand: "pasr", mids: [] }];
  const sent: { to: string; subject: string; headers: Record<string, string> }[] = [];
  const f = fake({ tickets: t });
  const signed = mail({ from: "leon@pasr.nl", subject: "Re: [#1001] Vraag", id: "<l1@pasr.nl>", body: "Hoi, dit is opgelost.", extra: ["Authentication-Results: mx.pasr.nl; spf=pass; dkim=pass header.d=pasr.nl"] });
  const r = await handleMail(signed, { ...ctxOf(f, E, sent), authserv: ["mx.pasr.nl"] } as never);
  eq([r.result, r.ticket], ["agent", 1001]);
  eq(sent.length, 1);
  eq(sent[0].to, "klant@x.nl");
  ok(sent[0].subject.startsWith("[#1001]"));
  eq(sent[0].headers["X-Pasr-Ticket"], "1001");
  eq(f.calls.find((c) => c.name === "pasr_mail_message_add")!.args.p_direction, "out");
  // zonder bewijs van de afzender (geen Authentication-Results): geweigerd, niets verstuurd
  const sent2: unknown[] = [];
  const forged = mail({ from: "leon@pasr.nl", subject: "Re: [#1001] Vraag", id: "<l2@pasr.nl>", body: "vals" });
  const r2 = await handleMail(forged, { ...ctxOf(fake({ tickets: t }), E, sent2), authserv: ["mx.pasr.nl"] } as never);
  ok(r2.result.startsWith("rejected"), r2.result);
  eq(sent2.length, 0);
});

Deno.test("ontvangstbevestiging alleen met PASR_MAIL_AUTOREPLY=1", async () => {
  const sent: { subject: string; headers: Record<string, string> }[] = [];
  await handleMail(mail({ subject: "Vraag", id: "<k9@x.nl>" }), ctxOf(fake(), env({ PASR_IMAP_USER: "inbox@pasr.nl", PASR_MAIL_AUTOREPLY: "1" }), sent) as never);
  eq(sent.length, 1);
  eq(sent[0].headers["Auto-Submitted"], "auto-replied");
  const none: unknown[] = [];
  await handleMail(mail({ subject: "Vraag", id: "<k10@x.nl>" }), ctxOf(fake(), E, none) as never);
  eq(none.length, 0);
});

Deno.test("push: nieuw ticket en klantantwoord geven één seintje met nummer, merk en onderwerp (geen adres)", async () => {
  const f = fake({ tickets: [{ number: 1001, email: "klant@x.nl", status: "pending", brand: "zakelijk", mids: [] }] });
  const a = await handleMail(mail({ subject: "Vraag over kaart", id: "<n1@x.nl>" }), ctxOf(f));
  eq(a.notify, { number: 1001, brand: "pasr", subject: "Vraag over kaart" });
  const b = await handleMail(mail({ subject: "Re: [#1001] " + "x".repeat(100), id: "<n2@x.nl>", body: "Dank." }), ctxOf(f));
  eq([b.notify?.number, b.notify?.brand, b.notify?.subject.length], [1001, "zakelijk", 60]);
  ok(!JSON.stringify([a.notify, b.notify]).includes("@"), "geen adres");
  // dubbel, genegeerd en afgewezen: geen melding
  eq((await handleMail(mail({ subject: "x", id: "<d@x.nl>" }), ctxOf(fake({ exists: true })))).notify, undefined);
  eq((await handleMail(mail({ subject: "Afwezig", id: "<a2@x.nl>", extra: ["Auto-Submitted: auto-replied"] }), ctxOf(fake()))).notify, undefined);
});

// ---- pollInbox met een nep-IMAP: één samengevatte pushmelding per ronde ----
import { pollInbox } from "./poll.ts";
function fakeImap(raws: Record<number, string>) {
  return {
    maxLiteral: 0,
    login: () => Promise.resolve(),
    list: () => Promise.resolve([]),
    select: () => Promise.resolve({ exists: Object.keys(raws).length, uidvalidity: 7, permanentFlags: ["\\*"] }),
    uidSearch: () => Promise.resolve(Object.keys(raws).map(Number)),
    uidFetch: (uids: number[]) => Promise.resolve([{ uid: uids[0], size: raws[uids[0]].length, body: new TextEncoder().encode(raws[uids[0]]) }]),
    uidStore: () => Promise.resolve(),
    uidMove: () => Promise.resolve(),
    logout: () => Promise.resolve(),
    close: () => {},
  };
}
const rawOf = (id: string, subject: string) => ["From: klant@x.nl", "To: inbox@pasr.nl", `Subject: ${subject}`, `Message-ID: ${id}`, "MIME-Version: 1.0", "Content-Type: text/plain; charset=utf-8", "", "Hallo, een vraag over mijn kaart.", ""].join("\r\n");

Deno.test("poll_inbox: drie nieuwe mails geven één melding met drie items; zonder nieuwe mail geen melding", async () => {
  const f = fake();
  const rpc = (name: string, args: Record<string, unknown> = {}) => {
    if (name === "pasr_mail_sync_lock") return Promise.resolve({ data: true, error: null });
    if (name === "pasr_mail_log_done") return Promise.resolve({ data: [], error: null });
    if (name === "pasr_mail_sync_state") return Promise.resolve({ data: null, error: null });
    return f.rpc(name, args);
  };
  const imap = fakeImap({ 1: rawOf("<p1@x.nl>", "Een"), 2: rawOf("<p2@x.nl>", "Twee"), 3: rawOf("<p3@x.nl>", "Drie") });
  const r = await pollInbox({ rpc, env: E, connect: () => Promise.resolve(imap as never), send: () => Promise.resolve({ ok: true }) });
  eq([r.new_threads, r.notified], [3, 3]);
  const n = f.calls.filter((c) => c.name === "pasr_mail_notify");
  eq(n.length, 1, "één seintje per ronde");
  eq((n[0].args.p_items as { subject: string }[]).map((i) => i.subject), ["Een", "Twee", "Drie"]);
  // niets nieuws: geen seintje
  const g = fake({ exists: true });
  const rpc2 = (name: string, args: Record<string, unknown> = {}) => name === "pasr_mail_sync_lock" ? Promise.resolve({ data: true, error: null }) : name === "pasr_mail_log_done" ? Promise.resolve({ data: [], error: null }) : g.rpc(name, args);
  const r2 = await pollInbox({ rpc: rpc2, env: E, connect: () => Promise.resolve(fakeImap({ 1: rawOf("<p1@x.nl>", "Een") }) as never), send: () => Promise.resolve({ ok: true }) });
  eq(r2.notified, 0);
  eq(g.calls.some((c) => c.name === "pasr_mail_notify"), false);
});
