import { cleanBusinessDetail, cleanBusinessSettings } from "./business.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const ID = "8f1d3c3e-5a7b-4c2d-9e1f-0a1b2c3d4e5f";

Deno.test("zaak-detail", () => {
  const d = cleanBusinessDetail({ id: ID });
  ok(d.ok && d.limit === 200 && d.days === 30, "standaard");
  ok(!cleanBusinessDetail({ id: "x" }).ok, "id");
  ok(!cleanBusinessDetail({ id: ID, limit: 0 }).ok && !cleanBusinessDetail({ id: ID, limit: 5000 }).ok, "limit");
  ok(!cleanBusinessDetail({ id: ID, days: 400 }).ok && !cleanBusinessDetail({ id: ID, days: 1.5 }).ok, "days");
  const e = cleanBusinessDetail({ id: ID, limit: "50", days: 7 });
  ok(e.ok && e.limit === 50 && e.days === 7, "tekst als getal");
});

Deno.test("instellingen: afkoeltijd en max per scan", () => {
  const s = cleanBusinessSettings({ id: ID, cooldown_minutes: 0, max_per_scan: 30 });
  ok(s.ok && s.settings.cooldown_minutes === 0 && s.settings.max_per_scan === 30, "grenzen mogen");
  ok(!cleanBusinessSettings({ id: ID, cooldown_minutes: 1441 }).ok, "afkoeltijd te hoog");
  ok(!cleanBusinessSettings({ id: ID, cooldown_minutes: -1 }).ok, "afkoeltijd negatief");
  ok(!cleanBusinessSettings({ id: ID, max_per_scan: 0 }).ok && !cleanBusinessSettings({ id: ID, max_per_scan: 31 }).ok, "max per scan");
  ok(!cleanBusinessSettings({ id: ID, max_per_scan: "drie" }).ok, "geen getal");
  ok(!cleanBusinessSettings({ id: ID }).ok, "niets om op te slaan");
  const one = cleanBusinessSettings({ id: ID, cooldown_minutes: 15 });
  ok(one.ok && !("max_per_scan" in one.settings), "alleen wat meegegeven is");
});

Deno.test("instellingen: vindbaar in Pasr, adres en locatie", () => {
  const s = cleanBusinessSettings({ id: ID, listed: false });
  ok(s.ok && s.settings.listed === false, "uit de lijst halen");
  ok(!cleanBusinessSettings({ id: ID, listed: "nee" }).ok, "listed is boolean");
  const a = cleanBusinessSettings({ id: ID, address: "  Hoofdstraat   1,  Apeldoorn ", lat: 52.21, lng: 5.97 });
  ok(a.ok && a.settings.address === "Hoofdstraat 1, Apeldoorn" && a.settings.lat === 52.21, "adres en locatie");
  ok(!cleanBusinessSettings({ id: ID, lat: 52.2 }).ok, "lat zonder lng");
  ok(!cleanBusinessSettings({ id: ID, lat: 100, lng: 5 }).ok, "lat buiten bereik");
  const n = cleanBusinessSettings({ id: ID, address: null, lat: null, lng: null });
  ok(n.ok && n.settings.address === null && n.settings.lat === null, "wissen");
});

import { cleanBusinessInput, cleanCardInput, dbError } from "./business.ts";

Deno.test("zaak aanmaken door het beheer", () => {
  const r = cleanBusinessInput({ business: { name: "  Koffie   A ", city: "Deventer", email: " A@X.nl ", website: "koffie-a.nl/", listed: false,
    cooldown_minutes: "15", max_per_scan: 5, address: "Brink 1" } }, true);
  ok(r.ok && r.value.name === "Koffie A" && r.value.email === "a@x.nl" && r.value.website === "https://koffie-a.nl", JSON.stringify(r));
  ok(r.ok && r.value.cooldown_minutes === 15 && r.value.listed === false && !("id" in r.value), "instellingen");
  ok(!cleanBusinessInput({ business: { name: "X" } }, true).ok, "naam te kort");
  ok(!cleanBusinessInput({ business: {} }, true).ok, "naam verplicht");
  ok(!cleanBusinessInput({ business: { name: "Goed", email: "geen-mail" } }, true).ok, "e-mail");
  ok(!cleanBusinessInput({ business: { name: "Goed", website: "javascript:alert(1)" } }, true).ok, "website");
  ok(!cleanBusinessInput({ business: { name: "Goed", website: "http://localhost" } }, true).ok, "geen hostnaam");
  ok(!cleanBusinessInput({ business: { name: "Goed", max_per_scan: 31 } }, true).ok, "max per scan");
  ok(!cleanBusinessInput({ business: { name: "Goed", cooldown_minutes: 2000 } }, true).ok, "afkoeltijd");
  ok(!cleanBusinessInput({ business: "Goed" }, true).ok, "geen object");
  const e = cleanBusinessInput({ business: { name: "Goed", email: "" } }, true);
  ok(e.ok && e.value.email === "", "zonder eigenaar");
});

Deno.test("zaak bewerken door het beheer", () => {
  ok(!cleanBusinessInput({ business: { name: "Goed" } }, false).ok, "id verplicht");
  const r = cleanBusinessInput({ id: ID, business: { website: null, address: "" } }, false);
  ok(r.ok && r.value.website === null && r.value.address === null && !("name" in r.value), "wissen en laten staan");
  ok(!cleanBusinessInput({ id: ID, business: {} }, false).ok, "niets te bewaren");
});

Deno.test("stempelkaart van het beheer", () => {
  const r = cleanCardInput({ business_id: ID, card: { name: " Koffiekaart ", reward: "1 gratis koffie", stamps_total: 8, color: "#12a77e",
    text_color: "#ffffff", logo: "data:image/png;base64,iVBORw0KGgoAAAA=", published: true } });
  ok(r.ok && r.card.color === "#12A77E" && r.card.text_color === "#FFFFFF" && r.card.logo === "iVBORw0KGgoAAAA=" && r.card.published === true, JSON.stringify(r));
  ok(r.ok && !("id" in r.card), "nieuw zonder id");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", stamps_total: 1 } }).ok, "minstens 2 stempels");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", stamps_total: 31 } }).ok, "hoogstens 30 stempels");
  ok(!cleanCardInput({ business_id: ID, card: { name: "", reward: "r" } }).ok, "naam");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "" } }).ok, "beloning");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", color: "rood" } }).ok, "kleur");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", logo: "<svg>" } }).ok, "logo");
  ok(!cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", logo: "iVBORw0KGgo" + "A".repeat(220_000) } }).ok, "logo te groot");
  ok(!cleanCardInput({ business_id: "x", card: { name: "K", reward: "r" } }).ok, "zaak-id");
  const keep = cleanCardInput({ business_id: ID, card: { id: ID, name: "K", reward: "r" } });
  ok(keep.ok && !("logo" in keep.card) && !("text_color" in keep.card) && !("published" in keep.card), "weglaten = laten staan");
  const clear = cleanCardInput({ business_id: ID, card: { name: "K", reward: "r", logo: null, text_color: "" } });
  ok(clear.ok && clear.card.logo === null && clear.card.text_color === "", "wissen");
});

Deno.test("databasefouten", () => {
  ok(dbError({ message: "owner_taken" })?.status === 409, "eigenaar bezet");
  ok(dbError({ message: "Max per scan moet tussen 1 en 30 liggen.", hint: "bad_settings" })?.error === "bad_settings", "hint");
  ok(dbError({ message: "not_found" })?.status === 404, "niet gevonden");
  ok(dbError({ message: "iets anders" }) === null, "onbekend = serverfout");
});
