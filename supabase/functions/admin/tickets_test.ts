// deno test --no-check supabase/functions/admin/tickets_test.ts
import { ticketPayload, tkDevices, TK_TYPES } from "./tickets.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const E = "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F", T = "7f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f";

Deno.test("elke soort: type, id's en een tekst zonder persoonsgegevens", () => {
  for (const kind of TK_TYPES) {
    const p = ticketPayload({ id: 1, kind, event_id: E, ticket_id: T, card_id: E, member_id: T, title: "Winterborrel",
      business: "Bakkerij de Korenschoof", starts_at: "2026-12-19T15:00:00Z", doors_at: "2026-12-19T14:45:00Z", tickets: 2,
      percent: 15, label: "15% op alles", ends_on: "2026-12-15" })!;
    ok(p && p.type === kind, kind);
    ok(p.aps.alert.title.length > 0 && p.aps.alert.body.length > 0, `${kind}: tekst`);
    if (kind === "member_discount_started") ok(p.card_id === E.toLowerCase() && p.kind === "member_card", "kaart");
    else ok(p.event_id === E.toLowerCase() && p.kind === "event", "event");
  }
});

Deno.test("teksten in Nederlandse tijd", () => {
  const r = ticketPayload({ id: 1, kind: "event_reminder", event_id: E, title: "Winterborrel", business: "Korenschoof",
    starts_at: "2026-12-19T15:00:00Z", doors_at: "2026-12-19T14:45:00Z", tickets: 2 })!;
  ok(r.aps.alert.title === "Morgen: Winterborrel" && r.aps.alert.body.includes("15:45") && r.aps.alert.body.includes("2 tickets"), r.aps.alert.body);
  const w = ticketPayload({ id: 2, kind: "waitlist_promoted", event_id: E, ticket_id: T, title: "Winterborrel" })!;
  ok(w.ticket_id === T && w.aps.alert.title === "Er is een plek vrij", "plek vrij");
  const c = ticketPayload({ id: 3, kind: "event_cancelled", event_id: E, title: "Winterborrel", message: "Helaas ziek" })!;
  ok(c.aps.alert.body.includes("Helaas ziek"), c.aps.alert.body);
  const d = ticketPayload({ id: 4, kind: "member_discount_started", card_id: E, title: "Korenschoof Klantenkaart",
    business: "Bakkerij de Korenschoof", percent: "20.00", to_time: "19:00" })!;
  ok(d.aps.alert.title === "Nieuwe korting bij Bakkerij de Korenschoof" && d.aps.alert.body.startsWith("20% korting") && d.aps.alert.body.includes("tot 19:00"), d.aps.alert.body);
});

Deno.test("onbekend of zonder id: geen melding", () => {
  ok(ticketPayload({ id: 1, kind: "ticket_confirmed", event_id: E }) === null, "bevestiging is alleen een mail");
  ok(ticketPayload({ id: 1, kind: "event_reminder", event_id: "x" }) === null, "zonder event");
  ok(ticketPayload({ id: 1, kind: "member_discount_started" }) === null, "zonder kaart");
});

Deno.test("apparaten: geldig, uniek, met bron", () => {
  const list = tkDevices([
    { device_id: "a", token: "ab".repeat(32), provider: "apns", sandbox: true, src: "user" },
    { device_id: "b", token: "AB".repeat(32), provider: "apns", src: "device" },
    { device_id: "c", token: "x".repeat(40), provider: "fcm" },
    { device_id: "d", token: "", provider: "fcm" },
    { device_id: "e", token: "z".repeat(40), provider: "web" },
  ]);
  ok(list.length === 2 && list[0].src === "user" && list[0].sandbox && list[1].provider === "fcm" && list[1].src === "device", JSON.stringify(list));
});
