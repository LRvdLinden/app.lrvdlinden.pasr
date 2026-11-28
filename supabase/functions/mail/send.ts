// Pasr beheer › Mail: versturen via SMTP (nodemailer, de bestaande secrets PASR_SMTP_HOST/PORT/USER/PASSWORD). Eén verbinding die
// hergebruikt wordt (pool), hoogstens PASR_SMTP_RATE mails per seconde (standaard 5). Weigert de server het merkadres als afzender
// (550/553/554), dan één nieuwe poging vanaf PASR_SMTP_FROM met Reply-To naar het merkadres. Nooit adressen loggen.
import nodemailer from "npm:nodemailer@6.9.16";
import { addressOf, mailErrorCode, withName } from "./logic.ts";
import type { BuiltMail } from "./outbound.ts";

export type Env = (k: string) => string;
export const smtpConfigured = (env: Env) => !!(env("PASR_SMTP_HOST") && env("PASR_SMTP_USER") && env("PASR_SMTP_PASSWORD"));

export function transportOptions(env: Env) {
  const port = Number(env("PASR_SMTP_PORT") || 465);
  const rate = Math.max(1, Math.min(50, Number(env("PASR_SMTP_RATE") || 5) || 5));
  return {
    host: env("PASR_SMTP_HOST"), port, secure: port !== 587 && port !== 25, auth: { user: env("PASR_SMTP_USER"), pass: env("PASR_SMTP_PASSWORD") },
    pool: true, maxConnections: 1, maxMessages: 100, rateDelta: 1000, rateLimit: rate,
    connectionTimeout: 15000, greetingTimeout: 15000, socketTimeout: 30000,
  };
}

export type SendResult = { ok: true } | { ok: false; code: string; permanent: boolean };
// deno-lint-ignore no-explicit-any
export type Transport = { sendMail(m: any): Promise<unknown>; close(): void };

export function makeTransport(env: Env): Transport {
  // deno-lint-ignore no-explicit-any
  return nodemailer.createTransport(transportOptions(env)) as any;
}

/** Permanente fout (5xx): opnieuw proberen heeft geen zin. Tijdelijk (4xx, time-out, verbinding): later nog eens. */
export const isPermanent = (e: unknown) => {
  const c = Number((e as { responseCode?: number })?.responseCode ?? 0);
  return c >= 500 && c < 600;
};
const senderRefused = (e: unknown) => {
  const c = Number((e as { responseCode?: number })?.responseCode ?? 0);
  return [550, 553, 554, 501].includes(c) && /sender|from|mailbox|relay|not owned|authenticat/i.test(String((e as Error)?.message ?? ""));
};

export async function sendBuilt(t: Transport, m: BuiltMail, env: Env, brandName: string): Promise<SendResult> {
  try {
    await t.sendMail(m);
    return { ok: true };
  } catch (e) {
    const alt = env("PASR_SMTP_FROM").trim();
    if (alt && senderRefused(e) && addressOf(alt) !== addressOf(m.from)) {
      try {
        await t.sendMail({ ...m, from: withName(alt, brandName), replyTo: m.replyTo ?? addressOf(m.from), envelope: { ...m.envelope, from: addressOf(alt) } });
        return { ok: true };
      } catch (e2) {
        return { ok: false, code: mailErrorCode(e2), permanent: isPermanent(e2) };
      }
    }
    return { ok: false, code: mailErrorCode(e), permanent: isPermanent(e) };
  }
}
