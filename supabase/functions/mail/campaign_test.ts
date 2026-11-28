// Tests voor campaign.ts met een nep-database en nep-verzender (geen netwerk):
//   deno test --no-check supabase/functions/mail/campaign_test.ts
import { BATCH, continueCampaigns, MAX_TEMP_FAILS, runCampaign } from "./campaign.ts";

function eq(a: unknown, b: unknown, msg = "") {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg} verwacht ${y}, kreeg ${x}`);
}
function ok(v: unknown, msg = "") { if (!v) throw new Error(`niet waar: ${msg}`); }

const tok = (i: number) => String(i).padStart(26, "0") + "ab";
const rowsOf = (n: number) => Array.from({ length: n }, (_, i) => ({ email: `u${i}@x.nl`, first_name: `V${i}`, token: tok(i) }));

function fake(n: number, opts: { already?: string[]; status?: string; cancelAfterProgress?: number } = {}) {
  const log = { progress: [] as Record<string, unknown>[], claimed: 0 };
  let progressCalls = 0;
  const rpc = (name: string, args: Record<string, unknown>) => {
    switch (name) {
      case "pasr_mail_campaign_claim": log.claimed++; return Promise.resolve({ data: true, error: null });
      case "pasr_mail_campaign_get":
        return Promise.resolve({ data: { id: 1, brand: "zakelijk", audience: "owners", subject: "Nieuws", body_md: "Hoi {{voornaam}}", status: opts.status ?? "sending" }, error: null });
      case "pasr_mail_audience": return Promise.resolve({ data: rowsOf(n), error: null });
      case "pasr_mail_campaign_sent_hashes": return Promise.resolve({ data: opts.already ?? [], error: null });
      case "pasr_mail_campaign_attachments": return Promise.resolve({ data: [], error: null });
      case "pasr_mail_campaign_progress": {
        log.progress.push(args); progressCalls++;
        const cancelled = opts.cancelAfterProgress !== undefined && progressCalls >= opts.cancelAfterProgress;
        return Promise.resolve({ data: { status: cancelled ? "cancelled" : args.p_done ? "done" : "sending" }, error: null });
      }
      case "pasr_mail_campaign_due": return Promise.resolve({ data: [1], error: null });
    }
    return Promise.resolve({ data: null, error: { message: "onbekend " + name } });
  };
  return { rpc, log };
}
const env = (k: string) => (k === "SUPABASE_URL" ? "https://abc.supabase.co" : "");

Deno.test("hele doelgroep: elke ontvanger een eigen mail met eigen afmeldlink, klaar na de laatste", async () => {
  const f = fake(3);
  const sent: { to: string; html: string; headers: Record<string, string> }[] = [];
  const r = await runCampaign({
    rpc: f.rpc, env, send: (m) => { sent.push({ to: m.to, html: m.html, headers: m.headers }); return Promise.resolve({ ok: true }); },
  }, 1, 60_000);
  eq([r.claimed, r.sent, r.failed, r.status, r.left], [true, 3, 0, "done", 0]);
  eq(sent.map((s) => s.to), ["u0@x.nl", "u1@x.nl", "u2@x.nl"]);
  ok(sent[1].html.includes("Hoi V1"), "voornaam ingevuld");
  ok(sent[1].html.includes(tok(1)) && !sent[1].html.includes(tok(2)), "eigen afmeldtoken");
  ok(String(sent[0].headers["List-Unsubscribe"]).includes(`stop=${tok(0)}`));
  eq(f.log.progress.at(-1)?.p_done, true);
});

Deno.test("hervatten: wie al een mail kreeg, krijgt er geen tweede", async () => {
  const f = fake(4, { already: [tok(0).slice(0, 26), tok(2).slice(0, 26)] });
  const to: string[] = [];
  const r = await runCampaign({ rpc: f.rpc, env, send: (m) => { to.push(m.to); return Promise.resolve({ ok: true }); } }, 1, 60_000);
  eq(to, ["u1@x.nl", "u3@x.nl"]);
  eq(r.sent, 2);
});

Deno.test("blijvende fout telt als mislukt; tijdelijke fouten stoppen de ronde zonder af te sluiten", async () => {
  const f = fake(3);
  const r = await runCampaign({
    rpc: f.rpc, env, send: (m) => Promise.resolve(m.to === "u1@x.nl" ? { ok: false, permanent: true, code: "bad" } : { ok: true }),
  }, 1, 60_000);
  eq([r.sent, r.failed, r.status], [2, 1, "done"]);
  ok(JSON.stringify(f.log.progress).includes(tok(1).slice(0, 26)), "mislukte hash vastgelegd");

  const g = fake(20);
  let calls = 0;
  const r2 = await runCampaign({ rpc: g.rpc, env, send: () => { calls++; return Promise.resolve({ ok: false, code: "timeout" }); } }, 1, 60_000);
  eq(calls, MAX_TEMP_FAILS);
  eq([r2.sent, r2.status], [0, "sending"], "niet klaar: de cron probeert later weer");
  eq(g.log.progress.at(-1)?.p_done, false);
});

Deno.test("tijdsbudget: stopt en laat de rest voor de volgende ronde", async () => {
  const f = fake(10);
  let t = 0;
  const r = await runCampaign({ rpc: f.rpc, env, now: () => t, send: () => { t += 1000; return Promise.resolve({ ok: true }); } }, 1, 3500);
  eq(r.sent, 4);
  eq(r.left, 6);
  eq(r.status, "sending");
});

Deno.test("afbreken tijdens het versturen: na de volgende voortgangsmelding is het klaar", async () => {
  const f = fake(BATCH * 2 + 5, { cancelAfterProgress: 1 });
  let calls = 0;
  const r = await runCampaign({ rpc: f.rpc, env, send: () => { calls++; return Promise.resolve({ ok: true }); } }, 1, 60_000);
  eq(calls, BATCH);
  eq(r.status, "cancelled");
});

Deno.test("geen lopende campagne: niets versturen", async () => {
  const f = fake(3, { status: "done" });
  let calls = 0;
  const r = await runCampaign({ rpc: f.rpc, env, send: () => { calls++; return Promise.resolve({ ok: true }); } }, 1, 60_000);
  eq(calls, 0);
  eq(r.status, "done");
});

Deno.test("cron: gaat verder met campagnes die geen ronde hebben", async () => {
  const f = fake(2);
  const n = await continueCampaigns({ rpc: f.rpc, env, send: () => Promise.resolve({ ok: true }) }, 60_000);
  eq(n, 1);
  eq(await continueCampaigns({ rpc: f.rpc, env, send: () => Promise.resolve({ ok: true }) }, 1000), 0, "te weinig tijd over");
});
