// deno test supabase/functions/admin/community_test.ts
import { cleanDevices, communityPayload, PUSH_TYPES } from "./community.ts";
import { fcmMessage } from "./fcm.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const CAMP = "0f0e0d0c-0b0a-4909-8807-060504030201";

Deno.test("payload: type en campaign volgens het contract", () => {
  const want: Record<string, string> = {
    invite: "community_invite", invite_email: "community_invite", accepted: "community_invite_answered",
    declined: "community_invite_answered", active: "community_active", removed: "community_removed", revoked: "community_removed",
  };
  for (const [kind, type] of Object.entries(want)) {
    const p = communityPayload({ id: 1, kind: kind as keyof typeof PUSH_TYPES, campaign: CAMP.toUpperCase(), business_id: CAMP, title: "Route", actor: "De Bakkerij" });
    ok(p && p.type === type && p.campaign === CAMP, `${kind}: ${JSON.stringify(p)}`);
    ok(p!.aps.alert.title && p!.aps.alert.body.length <= 200, `${kind}: tekst`);
  }
});

Deno.test("payload: onbekend of geen campagne = niets", () => {
  ok(communityPayload({ id: 1, kind: "x" as never, campaign: CAMP, business_id: CAMP }) === null, "soort");
  ok(communityPayload({ id: 1, kind: "invite", campaign: "nope", business_id: CAMP }) === null, "campagne");
});

Deno.test("payload: regeleinden en lengte", () => {
  const p = communityPayload({ id: 1, kind: "accepted", campaign: CAMP, business_id: CAMP, title: "a\nb".repeat(50), actor: "Zaak\r\nX" })!;
  ok(!p.aps.alert.title.includes("\n") && !p.aps.alert.body.includes("\n"), "op één regel");
});

Deno.test("FCM: type en campaign komen als data mee", () => {
  const p = communityPayload({ id: 1, kind: "active", campaign: CAMP, business_id: CAMP, title: "Route" })!;
  const m = fcmMessage("t".repeat(30), p, "zakelijk");
  ok(m.message.data.type === "community_active" && m.message.data.campaign === CAMP, JSON.stringify(m));
});

Deno.test("apparaten: dubbel token en onbekende provider weg", () => {
  const list = cleanDevices([
    { device_id: "a1234567", token: "AB", provider: "apns", sandbox: true },
    { device_id: "b1234567", token: "ab", provider: "apns" },
    { device_id: "c1234567", token: "x", provider: "sms" },
    null,
  ]);
  ok(list.length === 1 && list[0].sandbox === true, JSON.stringify(list));
});
