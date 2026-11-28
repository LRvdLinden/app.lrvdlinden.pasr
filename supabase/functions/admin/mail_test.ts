// Tests voor mail.ts (doorsturen van mail_*-acties naar de functie mail):
//   deno test --no-check supabase/functions/admin/mail_test.ts
import { adminKey } from "../mail/auth.ts";
import { auditDetail, forwardBody, forwardToMail, isMailAction, MAIL_ACTIONS, MAIL_MAX_BODY, mailKey, NORMAL_MAX_BODY, readBody } from "./mail.ts";

function eq(a: unknown, b: unknown, msg = "") {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg} verwacht ${y}, kreeg ${x}`);
}
function ok(v: unknown, msg = "") { if (!v) throw new Error(`niet waar: ${msg}`); }

Deno.test("alleen bekende mail_*-acties; prototype-namen tellen niet", () => {
  ok(isMailAction("mail_compose") && isMailAction("mail_campaign_cancel"));
  ok(!isMailAction("constructor") && !isMailAction("__proto__") && !isMailAction("status") && !isMailAction(5));
  for (const [k, v] of Object.entries(MAIL_ACTIONS)) ok(k.startsWith("mail_") && v.action.length > 0, k);
});

Deno.test("doorsturen: alleen toegestane velden, actienaam van de functie mail", () => {
  eq(forwardBody("mail_compose", { to: "a@x.nl", cc: "c@x.nl", bcc: "b@x.nl", subject: "S", body_md: "B", evil: 1, token: "geheim", action: "poll_inbox" }),
    { action: "compose", to: "a@x.nl", cc: "c@x.nl", bcc: "b@x.nl", subject: "S", body_md: "B" });
  eq(forwardBody("mail_poll", { x: 1 }), { action: "poll_inbox" });
  eq(forwardBody("mail_thread_get", { number: 5 }), { action: "thread_get", number: 5 });
});

Deno.test("sleutel: gelijk aan mail/auth.ts adminKey en leeg bij kort geheim", async () => {
  const s = "k".repeat(48);
  eq(await mailKey(s), await adminKey(s));
  eq(await mailKey("kort"), "");
});

Deno.test("logboek: aantallen en onderwerp, nooit adressen of inhoud", () => {
  const body = { to: "klant@x.nl", cc: "a@x.nl b@x.nl", bcc: ["c@x.nl"], subject: "Nieuwe actie", body_md: "geheime tekst", attachments: [{}, {}] };
  const d = auditDetail("mail_compose", body, { sent: 4, failed: 1 });
  eq(d, 'to=1 cc=2 bcc=1 att=2 sent=4 failed=1 "Nieuwe actie"');
  ok(!d.includes("@") && !d.includes("geheime"));
  const c = auditDetail("mail_campaign_send", { audience: "owners", brand: "zakelijk", subject: "Hoi\nBcc: x" }, { recipients: 10, sent: 9, failed: 1, campaign_id: 3 });
  ok(!c.includes("\n") && c.includes("recipients=10"));
  eq(auditDetail("mail_thread_reply", { number: 1001, cc: "a@x.nl", body_md: "x" }, {}), "#1001 cc=1 bcc=0 att=0");
  eq(auditDetail("mail_status", {}, {}), "");
});

const stream = (n: number) => {
  const chunk = new Uint8Array(65536).fill(97);
  let left = n;
  return new ReadableStream<Uint8Array>({
    pull(c) { if (left <= 0) return c.close(); const k = Math.min(left, chunk.length); c.enqueue(chunk.subarray(0, k)); left -= k; },
  });
};
const req = (n: number) => new Request("https://x.nl/", { method: "POST", body: stream(n) });

Deno.test("verzoek lezen: 700 kB gewoon, groter alleen met token, nooit boven 20 MB", async () => {
  let asked = 0;
  const yes = () => { asked++; return Promise.resolve(true); }, no = () => { asked++; return Promise.resolve(false); };
  eq(("text" in await readBody(req(1000), no)), true);
  eq(asked, 0, "klein verzoek vraagt geen token");
  eq(await readBody(req(NORMAL_MAX_BODY + 1000), no), { error: "too_large" });
  const big = await readBody(req(5 * 1024 * 1024), yes);
  ok("text" in big && big.text.length === 5 * 1024 * 1024, "5 MB met token");
  eq(await readBody(req(MAIL_MAX_BODY + 70000), yes), { error: "too_large" });
  eq(await readBody(new Request("https://x.nl/"), no), { text: "" });
});

Deno.test("doorsturen naar mail: kop x-pasr-admin, netwerkfout wordt 502", async () => {
  let seen: { url: string; key: string | null; body: string } | null = null;
  const f = ((url: string, init: RequestInit) => {
    seen = { url, key: new Headers(init.headers).get("x-pasr-admin"), body: String(init.body) };
    return Promise.resolve(new Response('{"ok":true}', { status: 201 }));
  }) as unknown as typeof fetch;
  eq(await forwardToMail("https://p.supabase.co/functions/v1/mail", "sleutel", { action: "status" }, f), { status: 201, text: '{"ok":true}' });
  eq(seen, { url: "https://p.supabase.co/functions/v1/mail", key: "sleutel", body: '{"action":"status"}' });
  const bad = (() => Promise.reject(new Error("down"))) as unknown as typeof fetch;
  eq(await forwardToMail("https://x/", "k", {}, bad), { status: 502, text: '{"error":"mail_unreachable"}' });
});
