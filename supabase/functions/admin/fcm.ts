// Pushmeldingen naar Android via Firebase Cloud Messaging (HTTP v1), naast APNs. Pure hulpjes zonder netwerk,
// getest in fcm_test.ts. Nooit tokens of de sleutel van het service-account loggen.
//
// Function secret FIREBASE_SERVICE_ACCOUNT_JSON: de JSON-sleutel van het service-account (als tekst of base64).

const te = new TextEncoder();

export type ServiceAccount = { project_id: string; client_email: string; private_key: string };

/** Service-account uit de secret (JSON of base64-JSON); null als er iets ontbreekt. */
export function parseServiceAccount(raw: string | undefined | null): ServiceAccount | null {
  const s = String(raw ?? "").trim();
  if (!s) return null;
  let text = s;
  if (!s.startsWith("{")) {
    try { text = atob(s); } catch { return null; }
  }
  try {
    const j = JSON.parse(text);
    if (typeof j?.project_id === "string" && typeof j?.client_email === "string" && typeof j?.private_key === "string") {
      return { project_id: j.project_id, client_email: j.client_email, private_key: j.private_key };
    }
  } catch { /* ongeldig */ }
  return null;
}

/** FCM-token: lang, alleen letters, cijfers en _:-. (zoals Firebase ze uitgeeft). */
export function cleanFcmToken(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const s = v.trim();
  return s.length >= 20 && s.length <= 4096 && /^[A-Za-z0-9_:.-]+$/.test(s) ? s : null;
}

function b64u(bytes: Uint8Array | string): string {
  const b = typeof bytes === "string" ? te.encode(bytes) : bytes;
  let s = "";
  for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function importRsaKey(pem: string): Promise<CryptoKey> {
  const body = String(pem).replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

/** JWT-assertion om bij Google een OAuth-token (scope firebase.messaging) te halen. */
export async function oauthAssertion(sa: ServiceAccount, key: CryptoKey, nowS = Math.floor(Date.now() / 1000)): Promise<string> {
  const head = b64u(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64u(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: nowS, exp: nowS + 3600,
  }));
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, te.encode(`${head}.${claims}`)));
  return `${head}.${claims}.${b64u(sig)}`;
}

export const fcmUrl = (projectId: string) => `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;

/**
 * Een APNs-payload ({aps:{alert:{title,body}, "thread-id"}, kind, ...}) als FCM-bericht. Data-only (de app maakt zelf
 * de melding en weet bij een tik welke kaart hij moet openen); alle velden als tekst, zoals FCM eist. Hoge prioriteit,
 * zodat de melding ook in Doze binnenkomt; 1 uur geldig (net als APNs).
 */
export function fcmMessage(token: string, payload: unknown, channel = "news") {
  const p = (payload && typeof payload === "object" ? payload : {}) as Record<string, unknown>;
  const aps = (p.aps ?? {}) as Record<string, unknown>;
  const alert = (aps.alert ?? {}) as Record<string, unknown>;
  const data: Record<string, string> = {};
  if (typeof alert.title === "string") data.title = alert.title.slice(0, 120);
  if (typeof alert.body === "string") data.body = alert.body.slice(0, 500);
  for (const [k, v] of Object.entries(p)) {
    if (k === "aps" || v === undefined || v === null) continue;
    data[k] = typeof v === "string" ? v.slice(0, 500) : JSON.stringify(v).slice(0, 500);
  }
  if (typeof aps["thread-id"] === "string" && !data.thread) data.thread = aps["thread-id"] as string;
  data.channel = channel;
  return { message: { token, data, android: { priority: "HIGH", ttl: "3600s", collapse_key: data.kind ?? channel } } };
}

/** Uitkomst van FCM: invalid = token weggooien (app verwijderd of token verlopen). */
export function fcmResult(status: number, body: unknown): { ok: true } | { ok: false; invalid: boolean; error: string } {
  if (status >= 200 && status < 300) return { ok: true };
  const err = ((body ?? {}) as { error?: { status?: string; details?: { errorCode?: string }[] } }).error;
  const code = err?.details?.find((d) => typeof d?.errorCode === "string")?.errorCode ?? err?.status ?? "";
  const c = /^[A-Z_]{1,40}$/.test(code) ? code : "";
  const invalid = status === 404 || c === "UNREGISTERED" || (status === 400 && (c === "INVALID_ARGUMENT" || c === "SENDER_ID_MISMATCH"))
    || c === "SENDER_ID_MISMATCH";
  return { ok: false, invalid, error: `fcm_${c || status}` };
}

/** Melding na een nieuwe stempel of een volle kaart (zakelijke stempelkaart), voor Android én (later) iOS. */
export function memberPayload(card: { name?: string | null; business?: string | null; reward?: string | null; stamps_total?: number | null },
  code: string, before: number, after: number) {
  const name = String(card.business || card.name || "je stempelkaart").replace(/[\r\n]+/g, " ").slice(0, 60);
  const total = typeof card.stamps_total === "number" && card.stamps_total > 0 ? card.stamps_total : null;
  const reward = String(card.reward ?? "").replace(/[\r\n]+/g, " ").trim().slice(0, 80);
  let title: string, body: string;
  if (total && after >= total && before < total) {
    title = `Je stempelkaart van ${name} is vol`;
    body = reward ? `Wissel je beloning in: ${reward}.` : "Wissel je beloning in bij je volgende bezoek.";
  } else if (after > before) {
    const n = after - before;
    title = n === 1 ? `Stempel erbij bij ${name}` : `${n} stempels erbij bij ${name}`;
    body = total ? `Je hebt er nu ${Math.min(after, total)} van de ${total}.` : `Je hebt er nu ${after}.`;
  } else {
    title = `Stempelkaart van ${name}`;
    body = total ? `Je stand is bijgewerkt: ${Math.min(after, total)} van de ${total}.` : "Je stand is bijgewerkt.";
  }
  return { aps: { alert: { title, body }, sound: "default", "thread-id": "stamps" }, kind: "stamps", code };
}
