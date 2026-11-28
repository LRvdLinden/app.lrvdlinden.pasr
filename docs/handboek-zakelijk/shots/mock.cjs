// Demo-backend voor de schermafbeeldingen van het handboek: dezelfde vormen als de echte pasr_business_*-functies
// (zie website/assets/zakelijk.js, loyalty2.js, tickets-klantenkaart.js en docs/*.md). Alle namen en cijfers zijn verzonnen.
// Klok van de browser staat vast op NOW (vrijdag 27 november 2026, 10:15 in Nederland).
const NOW = Date.parse("2026-11-27T10:15:00+01:00");
const DAY = 864e5;
const iso = (ms) => new Date(ms).toISOString();
const at = (days, h, m) => { const d = new Date(NOW + days * DAY); const s = d.toISOString().slice(0, 10); return iso(Date.parse(`${s}T${String(h).padStart(2, "0")}:${String(m || 0).padStart(2, "0")}:00+01:00`)); };
const ymd = (days) => new Date(NOW + days * DAY + 3600e3).toISOString().slice(0, 10);

const BIZ = "b1000000-0000-4000-8000-000000000001";
const CARD1 = "c1000000-0000-4000-8000-000000000001", CARD2 = "c2000000-0000-4000-8000-000000000002";
const EV1 = "e1000000-0000-4000-8000-000000000001", EV2 = "e2000000-0000-4000-8000-000000000002", EV3 = "e3000000-0000-4000-8000-000000000003";
const MC1 = "m1000000-0000-4000-8000-000000000001";

const cards = [
  { id: CARD1, name: "Koffiekaart", reward: "1 gratis koffie naar keuze", stamps_total: 10, color: "#8A4B1F", published: true, members: 342, stamps: 4870, rewards: 412, logo: null },
  { id: CARD2, name: "Broodkaart", reward: "Gratis heel brood", stamps_total: 8, color: "#2B7A4B", published: false, members: 0, stamps: 0, rewards: 0, logo: null },
];
const business = { id: BIZ, name: "Bakkerij de Korenschoof", city: "Apeldoorn", role: "owner", status: "approved", website: "jouwzaak.nl",
  note: "Bakkerij met koffiehoek, 2 vestigingen", created_at: iso(NOW - 200 * DAY), cooldown_minutes: 5, max_per_scan: 10, listed: true,
  address: "Hoofdstraat 12, 7311 AB Apeldoorn", lat: 52.2112, lng: 5.9699, cards };
const other = { id: "b2000000-0000-4000-8000-000000000002", name: "Lunchroom Het Plein", city: "Deventer", role: "staff", status: "approved", cards: [] };

function me(variant) {
  if (variant === "new") return { email: "marieke@jouwzaak.nl", businesses: [] };
  if (variant === "pending") return { email: "marieke@jouwzaak.nl", businesses: [Object.assign({}, business, { status: "pending", cards: [Object.assign({}, cards[0], { published: false, members: 0, stamps: 0, rewards: 0 })] })] };
  if (variant === "staff") return { email: "daan@jouwzaak.nl", businesses: [Object.assign({}, business, { role: "staff" })] };
  return { email: "marieke@jouwzaak.nl", businesses: [business, other] };
}

// 2 jaar aan dagcijfers met een weekpatroon (zaterdag druk, maandag rustig) en een lichte groei
function stats(days) {
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    const t = NOW - i * DAY, d = new Date(t + 3600e3), dow = d.getUTCDay();
    const base = [22, 31, 44, 47, 52, 61, 78][dow];
    const wobble = Math.round(9 * Math.sin(i * 1.7) + 6 * Math.cos(i * 0.37));
    const grow = Math.round((365 - Math.min(365, i)) / 40);
    const stamps = Math.max(8, base + wobble + grow);
    out.push({ day: d.toISOString().slice(0, 10), stamps, rewards: Math.max(0, Math.round(stamps / 11 + Math.sin(i) * 1.5)), new_members: Math.max(0, Math.round(2 + 2 * Math.sin(i * 0.9) + (dow === 6 ? 2 : 0))) });
  }
  return { days: out, totals: { members: 342 } };
}

const log = { events: [
  { at: at(0, 10, 9), kind: "stamp", amount: 1, card_name: "Koffiekaart", by_role: "owner", by_name: "Marieke", member_suffix: "7Q4K", stamps_before: 6, stamps_after: 7, device: "Webscanner" },
  { at: at(0, 9, 58), kind: "redeem", card_name: "Koffiekaart", by_role: "staff", by_name: "Daan", member_suffix: "M2XR", stamps_before: 10, stamps_after: 0, device: "iPhone" },
  { at: at(0, 9, 51), kind: "stamp", amount: 2, card_name: "Koffiekaart", by_role: "staff", by_name: "Daan", member_suffix: "HB9T", stamps_before: 3, stamps_after: 5, device: "iPhone" },
  { at: at(0, 9, 44), kind: "stamp", amount: 1, card_name: "Koffiekaart", by_role: "staff", by_name: "Daan", member_suffix: "K3PL", stamps_before: 8, stamps_after: 9, device: "iPhone", undone: true },
  { at: at(0, 9, 40), kind: "join", card_name: "Koffiekaart", by_role: "customer", member_suffix: "W8FD" },
  { at: at(0, 9, 31), kind: "stamp", amount: 1, card_name: "Koffiekaart", by_role: "owner", by_name: "Marieke", member_suffix: "ZJ4N", stamps_before: 1, stamps_after: 2, device: "Mac" },
  { at: at(0, 9, 12), kind: "claim", card_name: "Koffiekaart", by_role: "customer", member_suffix: "W8FD" },
  { at: at(0, 8, 47), kind: "stamp", amount: 1, card_name: "Koffiekaart", by_role: "staff", by_name: "Fatima", member_suffix: "QA7C", stamps_before: 4, stamps_after: 5, device: "Android" },
  { at: at(-1, 17, 22), kind: "stamp", amount: 1, card_name: "Koffiekaart", by_role: "staff", by_name: "Fatima", member_suffix: "R5VE", stamps_before: 9, stamps_after: 10, device: "Android" },
  { at: at(-1, 16, 3), kind: "undo", card_name: "Koffiekaart", by_role: "owner", by_name: "Marieke", member_suffix: "D6GU", stamps_before: 3, stamps_after: 2, device: "Webscanner" },
] };

const coupons = [
  { id: "a1000000-0000-4000-8000-000000000001", business_id: BIZ, title: "15% korting op taarten", description: "Op alle hele taarten, alleen in de winkel", discount_type: "percent", discount_value: 15, min_spend: 10,
    starts_at: at(-20, 0), ends_at: at(4, 23, 59), max_claims: 500, one_per_customer: true, public: true, claimed: 87, redeemed: 52 },
  { id: "a2000000-0000-4000-8000-000000000002", business_id: BIZ, title: "€ 2,50 korting op je volgende aankoop", description: "Vanaf € 10", discount_type: "amount", discount_value: 2.5, min_spend: 10,
    starts_at: at(-3, 0), ends_at: at(40, 23, 59), max_claims: 300, one_per_customer: true, public: true, claimed: 23, redeemed: 6 },
  { id: "a3000000-0000-4000-8000-000000000003", business_id: BIZ, title: "Kerstkransje gratis bij een kerststol", description: "In december", discount_type: "percent", discount_value: 100, min_spend: 12,
    starts_at: at(5, 0), ends_at: at(30, 23, 59), max_claims: 200, one_per_customer: true, public: false, claimed: 0, redeemed: 0 },
];
const codes = [
  { id: "p1000000-0000-4000-8000-000000000001", title: "Herfstactie", code: "HERFST20", discount_type: "percent", discount_value: 20, min_spend: 0, starts_at: at(-25, 0), ends_at: at(3, 23, 59), max_uses: 200, used_count: 64, active: true },
  { id: "p2000000-0000-4000-8000-000000000002", title: "Weekendontbijt", code: "ONTBIJT5", discount_type: "amount", discount_value: 5, min_spend: 25, starts_at: at(-2, 0), ends_at: at(60, 23, 59), max_uses: 100, used_count: 9, active: true },
];
const community = [
  { id: "g1000000-0000-4000-8000-000000000001", name: "Winterwandeling Hoofdstraat", reward: "Gratis warme chocolademelk", required: 3, starts_at: at(-6, 0), ends_at: at(54, 23, 59),
    lead_business: "Bakkerij de Korenschoof", lead_city: "Apeldoorn", is_lead: true, role: "owner", participants: 4, accepted_count: 4, min_participants: 3, state: "active",
    participant_names: ["Bakkerij de Korenschoof", "Cafe Centraal", "Boekhandel Het Hoekje", "Fietsplus"], joined: true, claims_here: 18, can_manage: true, open_same_city: false, invite_only: true, pending_invites: 2 },
  { id: "g2000000-0000-4000-8000-000000000002", name: "Sinterklaas in de binnenstad", reward: "Chocoladeletter", required: 4, starts_at: at(-2, 0), ends_at: at(9, 23, 59),
    lead_business: "Cafe Centraal", lead_city: "Apeldoorn", is_lead: false, role: "participant", participants: 2, accepted_count: 2, min_participants: 4, state: "waiting",
    participant_names: ["Cafe Centraal", "Bakkerij de Korenschoof"], joined: true, claims_here: 0, can_manage: false, open_same_city: true, invite_only: false },
];
const invites = [
  { invite_id: "i1000000-0000-4000-8000-000000000001", campaign_id: "g3000000-0000-4000-8000-000000000003", title: "Kerstmarkt Marktplein", reward: "10% korting bij je vierde zaak",
    starts_at: at(7, 0), ends_at: at(35, 23, 59), initiator_name: "Kaashandel De Wit", initiator_city: "Apeldoorn", participant_names: ["Kaashandel De Wit", "Bloemenhuis Flora", "Slagerij Bos"], required: 4, min_participants: 3, accepted_count: 3, created_at: at(-1, 14) },
];
const communityInvites = [
  { invite_id: "x1", business_id: BIZ, name: "Bakkerij de Korenschoof", city: "Apeldoorn", status: "accepted", organizer: true, created_at: at(-8, 10) },
  { invite_id: "x2", business_id: "z2", name: "Cafe Centraal", city: "Apeldoorn", status: "accepted", created_at: at(-8, 10) },
  { invite_id: "x3", business_id: "z3", name: "Boekhandel Het Hoekje", city: "Apeldoorn", status: "accepted", created_at: at(-7, 11) },
  { invite_id: "x4", business_id: "z4", name: "Fietsplus", city: "Apeldoorn", status: "accepted", created_at: at(-7, 11) },
  { invite_id: "x5", business_id: "z5", name: "Kapsalon Knip", city: "Apeldoorn", status: "invited", created_at: at(-2, 9), expires_at: at(12, 9) },
  { invite_id: "x6", business_id: null, name: "info@ijssalon.jouwzaak.nl", city: "", email: "info@ijssalon.jouwzaak.nl", status: "invited", created_at: at(-1, 9), expires_at: at(13, 9) },
  { invite_id: "x7", business_id: "z7", name: "Schoenmakerij Hak", city: "Apeldoorn", status: "declined", created_at: at(-5, 9) },
];
const communitySearch = [
  { business_id: "z8", name: "Bakkerij Bol", city: "Apeldoorn", logo_url: null, invite_status: null },
  { business_id: "z5", name: "Kapsalon Knip", city: "Apeldoorn", logo_url: null, invite_status: "invited" },
  { business_id: "z9", name: "Eetcafe De Brink", city: "Apeldoorn", logo_url: null, invite_status: null },
];

const events = [
  { id: EV1, name: "Winterborrel", description: "Glühwein, warme chocolademelk en ons nieuwe winterbrood. Kom proeven en neem gerust iemand mee.",
    starts_at: at(21, 16), ends_at: at(21, 19), doors_at: at(21, 15, 45), address: "Hoofdstraat 12, 7311 AB Apeldoorn", lat: null, lng: null, capacity: 120, max_per_person: 4,
    signup_until: null, waitlist_enabled: true, reminder: true, header_url: null, status: "published", color: "#1F3A5F", registered: 118, checked_in: 0, waitlist: 7, cancelled: 4,
    signup_open: true, add_link: "https://pasr.nl/add/e/" + EV1, created_at: at(-10, 9),
    ticket_types: [{ id: "t1", name: "Toegang", capacity: 100, registered: 99, waitlist: 7 }, { id: "t2", name: "Kinderen t/m 12", capacity: 20, registered: 19, waitlist: 0 }] },
  { id: EV2, name: "Workshop zuurdesem bakken", description: "In twee uur je eigen zuurdesembrood. Neem een schort mee.", starts_at: at(8, 19), ends_at: at(8, 21, 30), doors_at: null,
    address: "Hoofdstraat 12, 7311 AB Apeldoorn", capacity: 16, max_per_person: 2, waitlist_enabled: true, reminder: true, status: "published", color: "#8A4B1F",
    registered: 11, checked_in: 0, waitlist: 0, cancelled: 1, signup_open: true, add_link: "https://pasr.nl/add/e/" + EV2, ticket_types: [{ id: "t3", name: "Deelnemer", capacity: null, registered: 11, waitlist: 0 }] },
  { id: EV3, name: "Nieuwjaarsborrel", description: "", starts_at: at(43, 17), ends_at: at(43, 20), address: "", capacity: 80, max_per_person: 4, waitlist_enabled: true, reminder: true,
    status: "draft", color: "#6A5CFF", registered: 0, checked_in: 0, waitlist: 0, cancelled: 0, ticket_types: [{ id: "t4", name: "Toegang", capacity: null }] },
];
const people = [
  ["Anna", "de Vries", "anna.devries@voorbeeld.nl", "1991-03-14", "Toegang", "registered", null, null, 2],
  ["Mehmet", "Yilmaz", "m.yilmaz@voorbeeld.nl", "1985-11-02", "Toegang", "registered", null, null, 1],
  ["Sanne", "Bakker", "sanne.b@voorbeeld.nl", "1979-06-27", "Kinderen t/m 12", "registered", null, null, 2],
  ["Joris", "Hendriks", "joris.h@voorbeeld.nl", "1996-09-09", "Toegang", "registered", null, null, 1],
  ["Lotte", "Mulder", "lotte.m@voorbeeld.nl", "2001-01-21", "Toegang", "registered", null, null, 3],
  ["Fatima", "El Amrani", "f.elamrani@voorbeeld.nl", "1988-01-30", "Toegang", "waitlist", null, 2, 1],
  ["Kees", "Jansen", "kees@voorbeeld.nl", "1970-05-01", "Toegang", "cancelled", null, null, 1],
];
const regs = [];
people.forEach((p, i) => { for (let k = 0; k < p[8]; k++) regs.push({ registration_id: "r" + i, ticket_id: "k" + i + "-" + k, first_name: p[0], last_name: p[1], email: p[2], birth_date: p[3], ticket_type: k && p[4] === "Kinderen t/m 12" ? "Kinderen t/m 12" : p[4],
  status: p[5], created_at: at(-9 + i, 10 + i, 12), checked_in_at: p[6], waitlist_position: p[7] }); });

const memberCards = [{ id: MC1, name: "Korenschoof Klantenkaart", color: "#8A4B1F", logo: null, barcode_type: "code128", status: "published", members: 214, prefix: "KS-", visits_today: 41,
  add_link: "https://pasr.nl/add/m/" + MC1, created_at: at(-40, 10),
  goals: { membership: false, saving: { enabled: true, unit: "visits", target: 10, reward: "Gratis gebakje naar keuze" }, fixed_discount: { enabled: false, percent: 0 },
    periods: [{ id: "q1", label: "15% op alles", percent: 15, starts_on: ymd(-2), ends_on: ymd(3), weekdays: null, from_time: null, to_time: null },
      { id: "q2", label: "happy hour", percent: 20, starts_on: ymd(-2), ends_on: ymd(40), weekdays: [2], from_time: "16:00", to_time: "18:00" },
      { id: "q3", label: "kerstbrood", percent: 10, starts_on: ymd(20), ends_on: ymd(27), weekdays: null, from_time: null, to_time: null }] },
  discount_now: { percent: 15, label: "15% op alles", until: at(3, 23, 59), kind: "period", period_id: "q1", until_date: ymd(3) },
  next_discount: { percent: 20, label: "happy hour", starts_at: at(4, 16) } }];

const staff = [
  { id: "s0", name: "Marieke", email: "marieke@jouwzaak.nl", role: "owner", created_at: at(-200, 9) },
  { id: "s1", name: "Daan Jansen", email: "daan@jouwzaak.nl", role: "staff", accepted_at: at(-150, 9) },
  { id: "s2", name: "Fatima", email: null, role: "staff", accepted_at: at(-60, 9) },
  { id: "s3", name: "Joris", email: "joris@jouwzaak.nl", role: "staff", pending: true, created_at: at(-2, 9) },
  { id: "s4", name: "Tim", email: null, role: "staff", revoked: true, revoked_at: at(-30, 9) },
];
const members = { total: 342, members: [
  ["PZ…7Q4K", true, 7, 3, -0, -180], ["PZ…M2XR", true, 0, 5, -0, -170], ["PZ…HB9T", false, 5, 1, -0, -90], ["PZ…ZJ4N", true, 2, 0, -0, -14], ["PZ…QA7C", true, 5, 2, -0, -120],
  ["PZ…R5VE", false, 10, 1, -1, -66], ["PZ…W8FD", true, 0, 0, -0, -0], ["PZ…D6GU", true, 2, 4, -1, -160]].map((m) => ({ code: m[0], app: m[1], stamps_count: m[2], rewards_redeemed: m[3], last_stamp_at: at(m[4], 9), created_at: at(m[5], 9) })) };

const locations = [{ id: "l1", name: "Hoofdstraat", address: "Hoofdstraat 12, 7311 AB Apeldoorn", active: true }, { id: "l2", name: "Station", address: "Stationsplein 3, 7311 NZ Apeldoorn", active: true },
  { id: "l3", name: "Zomerkraam Marktplein", address: "", active: false }];
const locationStats = [{ id: "l1", stamps_30d: 1034 }, { id: "l2", stamps_30d: 412 }, { id: "l3", stamps_30d: 0 }];
const marketing = [
  { id: "mk1", title: "Sinterklaasweek", card_id: CARD1, card_name: "Koffiekaart", starts_on: ymd(1), ends_on: ymd(9), channel: "social", status: "planned", details: "Dubbele stempels op woensdag; post op Instagram en Facebook." },
  { id: "mk2", title: "Kerstbestellingen", card_id: null, card_name: null, starts_on: ymd(10), ends_on: ymd(27), channel: "winkel", status: "planned", details: "Flyer bij de kassa en de poster in de etalage." },
  { id: "mk3", title: "Nieuwsbrief december", card_id: null, starts_on: ymd(5), ends_on: ymd(5), channel: "email", status: "draft", details: "" },
];
const program = { settings: { rewards: [{ stamps: 5, title: "Gratis koekje bij je koffie" }], retention: { enabled: true, days: 30 }, referral: { enabled: true, bonus: 1 },
  campaign: { enabled: true, multiplier: 2, weekday: 3, start: ymd(1), end: ymd(30) }, locations: { enabled: true, names: ["Hoofdstraat", "Station"] },
  vip: { enabled: true, silver: 10, gold: 25, silver_benefit: "Gratis upgrade naar een grote koffie", gold_benefit: "Elke maand een gratis gebakje" }, marketing: { enabled: false }, community: { enabled: false } } };
const trash = [{ id: "tr1", kind: "coupon", title: "Zomerijs 2+1" }, { id: "tr2", kind: "code", title: "ZOMER10 · Zomeractie" }];

const scan = { card: { name: "Koffiekaart", business: "Bakkerij de Korenschoof", city: "Apeldoorn", color: "#8A4B1F", stamps_total: 10, reward: "1 gratis koffie naar keuze" },
  business_id: BIZ, stamps_count: 7, stamps_total: 10, reward: "1 gratis koffie naar keuze", max_per_scan: 10, member_code: "PZ7HKD2M9XQ37Q4K", member_code_suffix: "7Q4K",
  rewards_redeemed: 3, can_undo_event_id: "ev-1", event_id: "ev-1", last_stamp_at: iso(NOW - 20e3), cooldown_until: null };
const scanFull = Object.assign({}, scan, { stamps_count: 10, member_code_suffix: "R5VE", can_undo_event_id: null, event_id: null });
const ticketOk = { result: "valid", ticket_id: "k0-0", first_name: "Anna", last_name: "de Vries", ticket_type: "Toegang", event_id: EV1, event_name: "Winterborrel", checked_in_at: iso(NOW),
  counts: { checked_in: 86, registered: 118, capacity: 120, waitlist: 7 } };
const ticketUsed = Object.assign({}, ticketOk, { result: "used", first_name: "Mehmet", last_name: "Yilmaz", checked_in_at: iso(NOW - 22 * 60e3) });
const mcScan = { result: "valid", card_id: MC1, card_name: "Korenschoof Klantenkaart", member_name: "Anna de Vries", number: "KS-000124", member_id: "mm1", color: "#8A4B1F", barcode_type: "code128",
  discount_now: { percent: 15, label: "15% op alles", until: at(3, 23, 59), kind: "period" }, next_discount: null, saving: { count: 6, target: 10, reward: "Gratis gebakje naar keuze", can_redeem: false, unit: "visits" } };

const pubEvent = Object.assign({}, events[0], { business_name: "Bakkerij de Korenschoof", business_city: "Apeldoorn", business_logo: null, header_url: null,
  ticket_types: [{ id: "t1", name: "Toegang", available: 2 }, { id: "t2", name: "Kinderen t/m 12", available: 1 }], spots_left: 3, max_per_person: 4, signup_open: true, waitlist: true });

/** Antwoord voor een aanroep naar de (gemockte) server. variant: zie me(). opts.scan: welk scanresultaat. */
function respond(url, body, variant, opts) {
  opts = opts || {};
  const m = url.match(/\/rpc\/([a-z0-9_]+)/), fn = m ? m[1] : "";
  if (/\/auth\/v1\//.test(url)) return {};
  if (/functions\/v1\/business-brand/.test(url)) return { domain: "jouwzaak.nl", color: "#8A4B1F" };
  switch (fn) {
    case "pasr_business_me": return me(variant);
    case "pasr_business_stats": return stats(Math.min(730, (body && body.p_days) || 30));
    case "pasr_business_log": return log;
    case "pasr_business_loyalty_insights": return { members: 342, members_30d: 41, stamps_30d: 1446, returning_customers_90d: 198, milestone_rewards: 23, claimed_coupons: 110, redeemed_coupons: 58 };
    case "pasr_business_coupon_list": return coupons;
    case "pasr_business_promo_list": return codes;
    case "pasr_business_community_list": return community;
    case "pasr_business_community_my_invites": return opts.noInvites ? [] : invites;
    case "pasr_business_community_invites": return communityInvites;
    case "pasr_business_community_search": return communitySearch;
    case "pasr_business_community_open": return [];
    case "pasr_business_community_invite_preview": return { status: "invited", campaign_id: invites[0].campaign_id, title: invites[0].title, reward: invites[0].reward, starts_at: invites[0].starts_at, ends_at: invites[0].ends_at,
      initiator_name: "Kaashandel De Wit", participant_names: invites[0].participant_names };
    case "pasr_business_community_member": return [{ id: community[0].id, name: community[0].name, reward: community[0].reward, visited: 2, required: 3, claimed: false }];
    case "pasr_business_events": return events;
    case "pasr_business_event_registrations": return regs;
    case "pasr_business_member_cards": return memberCards;
    case "pasr_business_staff_list": return staff;
    case "pasr_business_staff_invite": return { link: "https://pasr.nl/zakelijk/uitnodiging/#K7Q2MXDATRZ5" };
    case "pasr_business_members_list": return members;
    case "pasr_business_locations_list": return locations;
    case "pasr_business_location_insights": return locationStats;
    case "pasr_business_marketing_list": return marketing;
    case "pasr_business_program": return program;
    case "pasr_business_trash": return trash;
    case "pasr_business_scan": return opts.full ? scanFull : scan;
    case "pasr_business_reward_progress": return [{ stamps: 5, title: "Gratis koekje bij je koffie", available: false }];
    case "pasr_business_ticket_scan": return opts.ticket === "used" ? ticketUsed : opts.ticket === "valid" ? ticketOk : { result: "invalid" };
    case "pasr_business_member_card_scan": return mcScan;
    case "pasr_business_coupon_check": return { valid: true, business: "Bakkerij de Korenschoof", title: "15% korting op taarten", discount_type: "percent", discount_value: 15, min_spend: 10, description: "Op alle hele taarten" };
    case "pasr_event_public": return pubEvent;
    case "pasr_business_staff_invite_info": return { status: "ok", role: "staff", business: "Bakkerij de Korenschoof", city: "Apeldoorn", name: "Joris" };
    default: return [];
  }
}

module.exports = { NOW, respond, EV1, CARD1, MC1 };
