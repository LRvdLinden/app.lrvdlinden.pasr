import { okLink, ownerMail } from "./owner_mail.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("eigenaarsmail", () => {
  const link = "https://pasr.nl/zakelijk/uitnodiging/#ABCDEFGHJKLMNPQRSTUV";
  const m = ownerMail("Koffie <b>& co</b>\r\nBcc: x", "Apeldoorn", link, "2026-12-22T10:00:00Z");
  ok(!m.subject.includes("\n") && !m.subject.includes("\r"), "geen regeleinde in onderwerp");
  ok(m.html.includes("Koffie &lt;b&gt;&amp; co&lt;/b&gt;") && !m.html.includes("<b>&"), "naam HTML-veilig");
  ok(m.html.includes(link) && m.text.includes(link), "link in mail");
  ok(m.text.includes("22 december 2026"), "verloopdatum");
  ok(m.text.includes("in Apeldoorn"), "plaats");
});

Deno.test("alleen echte uitnodigingslinks", () => {
  ok(okLink("https://pasr.nl/zakelijk/uitnodiging/#ABCDEFGHJKLMNPQRSTUV"), "goed");
  ok(!okLink("https://evil.nl/zakelijk/uitnodiging/#ABCDEFGHJKLMNPQRSTUV"), "ander domein");
  ok(!okLink("https://pasr.nl/zakelijk/uitnodiging/#abc"), "korte code");
  ok(!okLink(null), "leeg");
});
