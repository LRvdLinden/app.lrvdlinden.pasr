// Pushmeldingen bij tickets en de klantenkaart met barcode (Pasr-app van de klant, sinds 27-11-2026). Pure hulpjes
// zonder netwerk of database, getest in tickets_test.ts. De database zet gebeurtenissen in pasr_tk_outbox; de functie
// admin haalt ze op met pasr_tk_push_due (notify, kind "tickets") en stuurt ze naar de apparaten van de klant (APNs via
// pasr_user_push of pasr_devices, FCM via pasr_devices). Contract: docs/tickets-klantenkaart.md. Nooit tokens loggen,
// nooit namen, e-mail of geboortedatum in een melding.

export const TK_TYPES = ["event_reminder", "event_changed", "event_cancelled", "waitlist_promoted", "member_discount_started"] as const;
export type TkType = typeof TK_TYPES[number];

export type TkDevice = { device_id: string; token: string; provider: "apns" | "fcm"; sandbox: boolean; src: "user" | "device" };
export type TkItem = {
  id: number; kind: string; event_id?: string | null; ticket_id?: string | null; card_id?: string | null; member_id?: string | null;
  title?: string | null; business?: string | null; starts_at?: string | null; doors_at?: string | null; tickets?: number | null;
  message?: string | null; percent?: number | string | null; label?: string | null; ends_on?: string | null; to_time?: string | null;
  devices?: TkDevice[];
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const line = (s: unknown, n: number) => String(s ?? "").replace(/\s+/g, " ").trim().slice(0, n);
const id = (v: unknown) => (typeof v === "string" && UUID.test(v) ? v.toLowerCase() : null);
const fmt = (iso: unknown, o: Intl.DateTimeFormatOptions) => {
  const d = new Date(String(iso ?? ""));
  return isNaN(d.getTime()) ? "" : new Intl.DateTimeFormat("nl-NL", { ...o, timeZone: "Europe/Amsterdam" }).format(d);
};
const pct = (v: unknown) => {
  const n = Number(v);
  return isFinite(n) && n > 0 ? `${n.toLocaleString("nl-NL", { maximumFractionDigits: 2 })}%` : "";
};

/** Melding voor een rij uit de outbox, of null (onbekende soort of zonder id's). */
export function ticketPayload(item: TkItem) {
  if (!(TK_TYPES as readonly unknown[]).includes(item?.kind)) return null;
  const type = item.kind as TkType;
  const name = line(item.title, 60) || "je event";
  const biz = line(item.business, 60);
  let title: string, body: string;
  if (type === "member_discount_started") {
    const card = id(item.card_id);
    if (!card) return null;
    const p = pct(item.percent), until = item.to_time ? `tot ${line(item.to_time, 5)}` : item.ends_on ? `t/m ${fmt(`${item.ends_on}T12:00:00Z`, { day: "numeric", month: "long" })}` : "";
    title = `Nieuwe korting bij ${biz || name}`;
    body = [`${p ? p + " korting" : line(item.label, 40) || "Korting"} met je ${name}`, until].filter(Boolean).join(", ") + ".";
    return {
      aps: { alert: { title, body }, sound: "default", "thread-id": `member-card-${card}` },
      kind: "member_card", type, card_id: card, ...(id(item.member_id) ? { member_id: id(item.member_id) } : {}),
    };
  }
  const event = id(item.event_id);
  if (!event) return null;
  const n = Number(item.tickets) || 0;
  const when = fmt(item.starts_at, { weekday: "long", day: "numeric", month: "long" });
  const at = fmt(item.starts_at, { hour: "2-digit", minute: "2-digit" });
  const doors = fmt(item.doors_at, { hour: "2-digit", minute: "2-digit" });
  switch (type) {
    case "event_reminder":
      title = `Morgen: ${name}`;
      body = `${biz ? biz + ": " : ""}${doors ? `deuren open om ${doors}` : at ? `begint om ${at}` : "morgen"}. ${n > 1 ? `Je ${n} tickets staan klaar` : "Je ticket staat klaar"} in Pasr.`;
      break;
    case "event_changed":
      title = `${name} is gewijzigd`;
      body = `${biz || "De organisator"} heeft het event aangepast${when ? `: nu op ${when}${at ? " om " + at : ""}` : ""}. Bekijk je ticket.`;
      break;
    case "event_cancelled":
      title = `${name} gaat niet door`;
      body = `${biz || "De organisator"} heeft het event afgelast.${item.message ? " " + line(item.message, 140) : ""}`;
      break;
    default:
      title = "Er is een plek vrij";
      body = `Je staat niet meer op de wachtlijst: je ticket voor ${name} staat klaar in Pasr.`;
  }
  return {
    aps: { alert: { title, body }, sound: "default", "thread-id": `event-${event}` },
    kind: "event", type, event_id: event, ...(id(item.ticket_id) ? { ticket_id: id(item.ticket_id) } : {}),
  };
}

/** Alleen bruikbare apparaten; hetzelfde token één keer, hoogstens 10. */
export function tkDevices(list: unknown): TkDevice[] {
  const seen = new Set<string>();
  const out: TkDevice[] = [];
  for (const d of Array.isArray(list) ? list : []) {
    const x = (d ?? {}) as Record<string, unknown>;
    if (typeof x.device_id !== "string" || typeof x.token !== "string" || !x.token) continue;
    if (x.provider !== "apns" && x.provider !== "fcm") continue;
    const key = x.token.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ device_id: x.device_id, token: x.token, provider: x.provider, sandbox: x.sandbox === true, src: x.src === "user" ? "user" : "device" });
  }
  return out.slice(0, 10);
}
