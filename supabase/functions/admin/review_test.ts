import { alreadyExists, cleanReview } from "./review.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("review-account: invoer", () => {
  const r = cleanReview({ email: " Review@Pasr.nl ", password: "Appel1234567", first_name: " <b>Apple</b> " });
  ok(r.ok && r.value.email === "review@pasr.nl" && r.value.firstName === "bApple/b" && !r.value.reset, JSON.stringify(r));
  ok(!cleanReview({ email: "geen-adres", password: "Appel1234567" }).ok, "e-mail");
  ok(!cleanReview({ email: "a@b.nl", password: "kort1" }).ok, "te kort");
  ok(!cleanReview({ email: "a@b.nl", password: "alleenletters" }).ok, "cijfer nodig");
  ok(!cleanReview({ email: "a@b.nl", password: "1234567890123" }).ok, "letter nodig");
  ok(!cleanReview({ email: "a@b.nl", password: "a1" + "é".repeat(40) }).ok, "max 72 bytes");
  const d = cleanReview({ email: "a@b.nl", password: "Appel1234567", reset: true });
  ok(d.ok && d.value.firstName === "App Review" && d.value.reset, "standaardnaam en reset");
  ok(alreadyExists("A user with this email address has already been registered") && alreadyExists("x", 422) && !alreadyExists("boom", 500), "bestaat");
});
