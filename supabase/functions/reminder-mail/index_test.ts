// deno test supabase/functions/reminder-mail/index_test.ts
import { line, render, summary, type Due } from "./index.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

const due: Due = {
  user_id: "u", email: "a@b.nl", first_name: "Léon <b>", unsub: "0123456789abcdef0123456789abcdef",
  items: [
    { key: "bal:2026-12-01", type: "balance", kind: "voucher", store: "HEMA & co", balance: 12.5, currency: "EUR", date: null },
    { key: "exp:1:2026-12-08:7", type: "expiry", kind: "voucher", store: "Bol", days: 7, date: "2026-12-08", balance: 25, currency: "EUR" },
  ],
};

Deno.test("mail: veilig, alles ingevuld, afmeldlink", () => {
  const m = render(due);
  ok(!m.html.includes("{{"), "alles ingevuld");
  ok(m.html.includes("Léon &lt;b&gt;") && !m.html.includes("Léon <b>"), "naam escaped");
  ok(m.html.includes("HEMA &amp; co"), "winkel escaped");
  ok(m.html.includes("https://pasr.nl/afmelden/?t=0123456789abcdef0123456789abcdef"), "afmelden");
  ok(m.html.indexOf("Bol") < m.html.indexOf("HEMA"), "verlopend eerst");
  ok(m.text.includes("- Bol: Cadeaukaart verloopt op 8 december 2026"), m.text);
  ok(!m.subject.includes("\n"), "onderwerp op één regel");
});

Deno.test("onderwerp: één tegoed", () => {
  const s = summary([due.items[0]]);
  ok(s.subject.startsWith("Je hebt nog") && s.subject.includes("12,50") && s.subject.endsWith("bij HEMA & co"), s.subject);
});

Deno.test("onderwerp: alleen tegoed, totaal", () => {
  const s = summary([due.items[0], { ...due.items[0], store: "Bol", balance: 7.5 }]);
  ok(s.subject.includes("20,00") && s.subject.includes("2 cadeaukaarten"), s.subject);
});

Deno.test("regel: kortingscode vandaag en abonnement", () => {
  ok(line({ key: "k", type: "expiry", kind: "code", store: "Zalando", days: 0, date: "2026-12-01" }).detail === "Kortingscode verloopt vandaag", "code");
  const r = line({ key: "r", type: "renew", store: "Netflix", date: "2026-12-03", cost: 13.99, period: "month", currency: "EUR" });
  ok(r.detail.includes("3 december 2026") && r.detail.includes("13,99") && r.detail.includes("per maand"), r.detail);
});
