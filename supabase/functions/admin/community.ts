// Pushmeldingen bij gezamenlijke acties (Pasr Zakelijk, sinds 27-11-2026). Pure hulpjes zonder netwerk of database,
// getest in community_test.ts. De database zet gebeurtenissen in pasr_business_community_outbox; de functie admin haalt
// ze op met pasr_business_community_push_due (notify, kind "community") en stuurt ze naar de apparaten van Pasr Zakelijk
// van de betrokken zaak (APNs en FCM). Nooit tokens of apparaat-id's loggen.

/** Soorten in de outbox -> type in de payload (contract met de apps, docs/community-invites.md). */
export const PUSH_TYPES = {
  invite: "community_invite",
  invite_email: "community_invite",
  accepted: "community_invite_answered",
  declined: "community_invite_answered",
  active: "community_active",
  removed: "community_removed",
  revoked: "community_removed",
} as const;
export type OutboxKind = keyof typeof PUSH_TYPES;
export type PushType = typeof PUSH_TYPES[OutboxKind];

export type PushDevice = { device_id: string; token: string; provider: "apns" | "fcm"; sandbox: boolean };
export type PushItem = {
  id: number; kind: OutboxKind; campaign: string; business_id: string; title?: string | null; reward?: string | null;
  actor?: string | null; devices?: PushDevice[];
};

const line = (s: unknown, n: number) => String(s ?? "").replace(/\s+/g, " ").trim().slice(0, n);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Melding voor een gebeurtenis: {aps, kind: "community", type, campaign, business_id}. null bij een onbekende soort of campagne. */
export function communityPayload(item: PushItem) {
  const type = PUSH_TYPES[item?.kind as OutboxKind];
  if (!type || typeof item.campaign !== "string" || !UUID.test(item.campaign)) return null;
  const title = line(item.title, 60) || "gezamenlijke actie";
  const actor = line(item.actor, 60);
  const q = `“${title}”`;
  let t: string, body: string;
  switch (item.kind) {
    case "invite":
    case "invite_email":
      t = "Uitnodiging voor een gezamenlijke actie";
      body = `${actor || "Een ondernemer"} nodigt je zaak uit voor ${q}. Accepteren of weigeren?`;
      break;
    case "accepted":
      t = `${actor || "Een zaak"} doet mee`;
      body = `${actor || "Een uitgenodigde zaak"} heeft je uitnodiging voor ${q} geaccepteerd.`;
      break;
    case "declined":
      t = `${actor || "Een zaak"} doet niet mee`;
      body = `${actor || "Een uitgenodigde zaak"} heeft je uitnodiging voor ${q} geweigerd.`;
      break;
    case "active":
      t = "Gezamenlijke actie gestart";
      body = `${q} is gestart: er doen genoeg zaken mee. Klanten zien de actie nu in Pasr.`;
      break;
    case "removed":
      t = "Je zaak doet niet meer mee";
      body = `${actor || "Pasr"} heeft je zaak uit ${q} gehaald.`;
      break;
    default:
      t = "Uitnodiging ingetrokken";
      body = `${actor || "Pasr"} heeft de uitnodiging voor ${q} ingetrokken.`;
  }
  return {
    aps: { alert: { title: t, body }, sound: "default", "thread-id": "community" },
    kind: "community",
    type,
    campaign: item.campaign.toLowerCase(),
    ...(typeof item.business_id === "string" && UUID.test(item.business_id) ? { business_id: item.business_id.toLowerCase() } : {}),
  };
}

/** Alleen bruikbare apparaten; hetzelfde token één keer. */
export function cleanDevices(list: unknown): PushDevice[] {
  const seen = new Set<string>();
  const out: PushDevice[] = [];
  for (const d of Array.isArray(list) ? list : []) {
    const x = (d ?? {}) as Record<string, unknown>;
    if (typeof x.device_id !== "string" || typeof x.token !== "string" || !x.token) continue;
    if (x.provider !== "apns" && x.provider !== "fcm") continue;
    const key = x.token.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ device_id: x.device_id, token: x.token, provider: x.provider, sandbox: x.sandbox === true });
  }
  return out.slice(0, 20);
}
