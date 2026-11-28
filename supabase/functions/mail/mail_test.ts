// Tests voor logic.ts, requests.ts, auth.ts, outbound.ts en layout.ts (geen netwerk, geen database):
//   deno test --no-check supabase/functions/mail/mail_test.ts
import nodemailer from "npm:nodemailer@6.9.16";
import { adminKey, adminOk } from "./auth.ts";
import { BRAND_STYLE, renderMail } from "./layout.ts";
import {
  fromBase64, tooLarge, checkAddresses, chunk, cleanFileName, fromFor, LIMITS, newMessageId, parseAddressList, parseAttachments, statusAfter, subjectFor, toBase64, withName,
} from "./logic.ts";
import { parseMessage } from "./mime.ts";
import { buildMessage, genericUnsubPage, oneClickUrl, unsubPage } from "./outbound.ts";
import {
  parseCampaign, parseCompose, parseNote, parsePreview, parseReply, parseTest, parseThreadList, parseThreadStatus, statusFor,
} from "./requests.ts";

function eq(a: unknown, b: unknown, msg = "") {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg} verwacht ${y}, kreeg ${x}`);
}
function ok(v: unknown, msg = "") { if (!v) throw new Error(`niet waar: ${msg}`); }
const b64 = (s: string) => btoa(s);

// ---- adressen ----
Deno.test("adreslijst: komma's, puntkomma's, spaties, regels; kleine letters; zonder dubbelen; ongeldige geteld", () => {
  eq(parseAddressList("A@x.nl, b@x.nl;  c@x.nl\nA@X.nl d@x.nl"), { list: ["a@x.nl", "b@x.nl", "c@x.nl", "d@x.nl"], bad: 0 });
  eq(parseAddressList("goed@x.nl, kapot, @x.nl, a@b, x@@y.nl"), { list: ["goed@x.nl"], bad: 4 });
  eq(parseAddressList(["a@x.nl", "<b@x.nl>", "mailto:c@x.nl"]), { list: ["a@x.nl", "b@x.nl", "c@x.nl"], bad: 0 });
  eq(parseAddressList(undefined), { list: [], bad: 0 });
  eq(parseAddressList("a@x.nl\r\nBcc: boos@x.nl"), { list: ["a@x.nl", "boos@x.nl"], bad: 1 }, "regelinjectie wordt geen kopregel");
  ok(parseAddressList("a..b@x.nl").bad === 1, "dubbele punt");
});

Deno.test("Aan, CC en BCC: drie velden, grenzen, ontdubbeld", () => {
  const a = checkAddresses({ to: "a@x.nl", cc: ["c@x.nl"], bcc: "b1@x.nl b2@x.nl" });
  eq(a, { ok: true, value: { to: ["a@x.nl"], cc: ["c@x.nl"], bcc: ["b1@x.nl", "b2@x.nl"] } });
  // een adres dat al in Aan of CC staat, valt weg uit BCC (niemand dubbel)
  eq(checkAddresses({ to: "a@x.nl", cc: "a@x.nl c@x.nl", bcc: "a@x.nl c@x.nl d@x.nl" }), { ok: true, value: { to: ["a@x.nl"], cc: ["c@x.nl"], bcc: ["d@x.nl"] } });
  // Aan mag leeg zijn zolang er BCC is
  eq(checkAddresses({ bcc: "b@x.nl" }).ok, true);
  eq(checkAddresses({}), { ok: false, error: "no_recipient" });
  eq(checkAddresses({ to: "kapot" }), { ok: false, error: "bad_address" });
  eq(checkAddresses({ bcc: "ok@x.nl, kapot" }), { ok: false, error: "bad_address" });
  const many = (n: number, d = "x.nl") => Array.from({ length: n }, (_, i) => `u${i}@${d}`);
  eq(checkAddresses({ bcc: many(200) }).ok, true, "200 mag");
  eq(checkAddresses({ bcc: many(201) }), { ok: false, error: "too_many" });
  eq(checkAddresses({ to: many(100, "a.nl"), cc: many(20, "b.nl"), bcc: many(100, "c.nl") }), { ok: false, error: "too_many" }, "to > 20");
  eq(checkAddresses({ to: many(20, "a.nl"), cc: many(20, "b.nl"), bcc: many(160, "c.nl") }).ok, true);
  eq(checkAddresses({ to: many(21, "a.nl") }), { ok: false, error: "too_many" });
  // BCC in groepen van hoogstens 50
  eq(chunk(many(120), LIMITS.bccPerMail).map((g) => g.length), [50, 50, 20]);
  eq(chunk([], 50), []);
});

// ---- bijlagen ----
Deno.test("bijlagen: tot 20 MB in totaal, naam opgeschoond, type gecontroleerd", () => {
  const r = parseAttachments([{ name: "../../etc/passwd", type: "text/plain", data_b64: b64("hallo") }]);
  ok(r.ok);
  if (r.ok) { eq(r.list[0].name, "_.._etc_passwd"); eq(new TextDecoder().decode(r.list[0].data), "hallo"); eq(r.list[0].type, "text/plain"); }
  eq(parseAttachments(undefined), { ok: true, list: [] });
  eq(parseAttachments("x"), { ok: false, error: "bad_attachment" });
  eq(parseAttachments([{ name: "a", data_b64: "###" }]), { ok: false, error: "bad_attachment" });
  eq(parseAttachments([{ name: "a", data_b64: "" }]), { ok: false, error: "bad_attachment" });
  eq(parseAttachments([null]), { ok: false, error: "bad_attachment" });
  const t = parseAttachments([{ name: "a", type: "tekst; rommel", data_b64: b64("x") }]);
  ok(t.ok && t.list[0].type === "application/octet-stream", "onbekend type");
  // 12 MB + 9 MB = te groot; 12 MB + 8 MB mag; het handboek van 15,6 MB past
  const mb = (n: number) => toBase64(new Uint8Array(n * 1024 * 1024));
  eq(parseAttachments([{ name: "a", data_b64: mb(12) }, { name: "b", data_b64: mb(9) }]), { ok: false, error: "too_large" });
  ok(parseAttachments([{ name: "handboek.pdf", data_b64: mb(15.6) }]).ok, "15,6 MB handboek");
  ok(parseAttachments([{ name: "a", data_b64: mb(12) }, { name: "b", data_b64: mb(8) }]).ok, "20 MB mag");
  eq(parseAttachments([{ name: "a", data_b64: mb(21) }]), { ok: false, error: "too_large" });
  eq(parseAttachments(Array.from({ length: 11 }, () => ({ name: "a", data_b64: b64("x") }))), { ok: false, error: "too_large" }, "aantal");
  eq(cleanFileName("a\r\nb:c*.pdf"), "a b_c_.pdf".replace(" ", " "));
  eq(cleanFileName("   "), "bijlage");
  ok(cleanFileName("x".repeat(500)).length <= LIMITS.attachmentName);
});

// ---- verzoeken ----
const good = { to: "a@x.nl", subject: "Hoi", body_md: "Tekst", brand: "pasr" };
Deno.test("compose: velden, merk, onderwerp en tekst", () => {
  const r = parseCompose({ ...good, cc: "c@x.nl", bcc: "b@x.nl" });
  ok(r.ok);
  if (r.ok) { eq(r.value.to, ["a@x.nl"]); eq(r.value.cc, ["c@x.nl"]); eq(r.value.bcc, ["b@x.nl"]); eq(r.value.thread, true); eq(r.value.brand, "pasr"); }
  eq(parseCompose({ ...good, thread: false }).ok && (parseCompose({ ...good, thread: false }) as { value: { thread: boolean } }).value.thread, false);
  eq(parseCompose({ ...good, brand: "zakelijk" }).ok, true);
  eq(parseCompose({ ...good, brand: "anders" }), { ok: false, error: "bad_brand" });
  eq(parseCompose({ ...good, subject: "  " }), { ok: false, error: "bad_subject" });
  eq(parseCompose({ ...good, subject: "x".repeat(151) }), { ok: false, error: "bad_subject" });
  eq(parseCompose({ ...good, body_md: " " }), { ok: false, error: "bad_body" });
  eq(parseCompose({ ...good, body_md: "Mail naar {{email}}" }), { ok: false, error: "bad_body" });
  eq(parseCompose({ ...good, body_md: "x".repeat(LIMITS.bodyMd + 1) }), { ok: false, error: "bad_body" });
  eq(parseCompose({ ...good, to: "" }), { ok: false, error: "bad_address" });
  eq(parseCompose({ ...good, to: "kapot" }), { ok: false, error: "bad_address" });
  eq(parseCompose({ ...good, to: "", bcc: "b@x.nl" }).ok, true, "alleen BCC mag");
  // onderwerp: stuurtekens weg, dus geen kopregel-injectie
  const inj = parseCompose({ ...good, subject: "Hoi\r\nBcc: boos@x.nl" });
  ok(inj.ok && !/[\r\n]/.test(inj.value.subject), "onderwerp zonder regeleinden");
});

Deno.test("reply, status, notitie, test, preview, lijst, campagne", () => {
  const rp = parseReply({ number: "#1001", body_md: "Antwoord", cc: "c@x.nl", bcc: "b@x.nl", status: "closed", brand: "zakelijk" });
  ok(rp.ok);
  if (rp.ok) { eq(rp.value.number, 1001); eq(rp.value.status, "closed"); eq(rp.value.brand, "zakelijk"); eq(rp.value.cc, ["c@x.nl"]); eq(rp.value.bcc, ["b@x.nl"]); }
  eq(parseReply({ number: 0, body_md: "x" }), { ok: false, error: "bad_number" });
  eq(parseReply({ number: 5, body_md: "" }), { ok: false, error: "bad_body" });
  eq(parseReply({ number: 5, body_md: "x", status: "raar" }), { ok: false, error: "bad_status" });
  eq(parseReply({ number: 5, body_md: "x", cc: "kapot" }), { ok: false, error: "bad_address" });
  const rb = parseReply({ number: 5, body_md: "x" });
  ok(rb.ok && rb.value.brand === null && rb.value.status === null, "merk en status volgen het ticket");
  eq(parseThreadStatus({ number: 5, status: "open" }), { ok: true, value: { number: 5, status: "open", priority: null } });
  eq(parseThreadStatus({ number: 5, priority: "urgent" }), { ok: true, value: { number: 5, status: null, priority: "urgent" } });
  eq(parseThreadStatus({ number: 5 }), { ok: false, error: "bad_request" });
  eq(parseThreadStatus({ number: 5, status: "x" }), { ok: false, error: "bad_status" });
  eq(parseThreadStatus({ number: 5, priority: "x" }), { ok: false, error: "bad_priority" });
  eq(parseNote({ number: 5, text: "  intern  " }), { ok: true, value: { number: 5, text: "intern" } });
  eq(parseNote({ number: 5, text: "" }), { ok: false, error: "bad_body" });
  eq(parseTest({ ...good, to: "Jij@X.nl" }).ok, true);
  eq(parseTest({ ...good, to: "a@x.nl, b@x.nl" }), { ok: false, error: "bad_address" }, "één adres");
  eq(parsePreview({ body_md: "", brand: "pasr" }).ok, true, "lege preview mag");
  eq(parsePreview({ body_md: "{{email}}" }), { ok: false, error: "bad_body" });
  eq(parseThreadList({}), { ok: true, value: { status: "active", q: null, brand: null, page: 1, size: 30, box: "inbox" } });
  eq(parseThreadList({ box: "sent" }), { ok: true, value: { status: "all", q: null, brand: null, page: 1, size: 30, box: "sent" } });
  eq(parseThreadList({ box: "all", status: "open" }), { ok: true, value: { status: "open", q: null, brand: null, page: 1, size: 30, box: "all" } });
  eq(parseThreadList({ box: "raar" }), { ok: false, error: "bad_box" });
  eq(parseThreadList({ status: "closed", q: " zoek ", brand: "zakelijk", page: 3, page_size: 500 }), { ok: true, value: { status: "closed", q: "zoek", brand: "zakelijk", page: 3, size: 100, box: "inbox" } });
  eq(parseThreadList({ status: "raar" }), { ok: false, error: "bad_status" });
  eq(parseThreadList({ brand: "raar" }), { ok: false, error: "bad_brand" });
  const id = "123e4567-e89b-42d3-a456-426614174000";
  const c = parseCampaign({ audience: "owners", subject: "Nieuws", body_md: "Hoi", request_id: id });
  ok(c.ok && c.value.brand === "zakelijk", "ondernemers: merk Pasr Zakelijk");
  const u = parseCampaign({ audience: "users", subject: "Nieuws", body_md: "Hoi", request_id: id });
  ok(u.ok && u.value.brand === "pasr", "gebruikers: merk Pasr");
  const o = parseCampaign({ audience: "users", subject: "Nieuws", body_md: "Hoi", request_id: id, brand: "zakelijk" });
  ok(o.ok && o.value.brand === "zakelijk", "merk aanpasbaar");
  eq(parseCampaign({ audience: "list", subject: "x", body_md: "y", request_id: id }), { ok: false, error: "bad_audience" });
  eq(parseCampaign({ audience: "users", subject: "x", body_md: "y", request_id: "nee" }), { ok: false, error: "bad_request_id" });
  eq([statusFor("too_large"), statusFor("rate_limited"), statusFor("smtp_not_configured"), statusFor("not_found"), statusFor("bad_address")], [413, 429, 503, 404, 400]);
});

// ---- logic ----
Deno.test("onderwerp, Message-ID, afzender, status", () => {
  eq(subjectFor("Hoi", 1001), "[#1001] Hoi");
  eq(subjectFor("[#1001] Hoi", 1001), "[#1001] Hoi");
  eq(subjectFor("Hoi\r\nBcc: x@y.nl"), "Hoi Bcc: x@y.nl");
  eq(newMessageId(1001, "abc"), "<pasr-ticket-1001.abc@pasr.nl>");
  eq(newMessageId(null, "abc"), "<pasr-mail-abc@pasr.nl>");
  eq(withName("support@pasr.nl", "Pasr"), "Pasr <support@pasr.nl>");
  eq(withName("Eigen Naam <a@b.nl>", "Pasr"), "Eigen Naam <a@b.nl>");
  const none = () => "";
  eq(fromFor("pasr", none), "Pasr <support@pasr.nl>");
  eq(fromFor("zakelijk", none), "Pasr Zakelijk <zakelijk@pasr.nl>");
  eq(fromFor("zakelijk", (k) => (k === "PASR_MAIL_FROM_ZAKELIJK" ? "ondernemers@pasr.nl" : "")), "Pasr Zakelijk <ondernemers@pasr.nl>");
  eq(fromFor("pasr", (k) => (k === "PASR_MAIL_FROM_PASR" ? "Pasr Hulp <hulp@pasr.nl>" : "")), "Pasr Hulp <hulp@pasr.nl>");
  eq([statusAfter("new", "support"), statusAfter("closed", "support"), statusAfter("pending", "contact"), statusAfter("closed", "contact")], ["pending", "closed", "open", "open"]);
});

// ---- toegang ----
Deno.test("toegang: x-pasr-admin volgt uit PASR_TOKEN_SECRET", async () => {
  const secret = "s".repeat(40);
  const key = await adminKey(secret);
  ok(/^[0-9a-f]{64}$/.test(key));
  eq(await adminKey(secret), key, "stabiel");
  ok(key !== await adminKey("t".repeat(40)), "ander geheim, andere sleutel");
  eq(await adminKey("kort"), "", "te kort geheim: geen sleutel");
  ok(await adminOk(key, secret));
  ok(!(await adminOk(key.slice(0, -1) + "0", secret)));
  ok(!(await adminOk(null, secret)) && !(await adminOk("", secret)) && !(await adminOk(key, "")));
  ok(!(await adminOk("x".repeat(500), secret)));
});

// ---- uitgaande mail ----
const sendStream = async (built: ReturnType<typeof buildMessage>) => {
  const t = nodemailer.createTransport({ streamTransport: true, buffer: true, newline: "unix" });
  const r = await t.sendMail(built);
  return { raw: (r.message as Uint8Array).toString().replace(/\r\n/g, "\n"), envelope: r.envelope as { from: string; to: string[] } };
};
const base = {
  brand: "pasr" as const, kind: "mail" as const, from: "Pasr <support@pasr.nl>", replyTo: "inbox@pasr.nl", subject: "Hoi", markdown: "**Hallo** {{voornaam}}",
  messageId: "<pasr-mail-abc@pasr.nl>", vars: { voornaam: "Anna" },
};

Deno.test("headers: Aan en CC komen in de kopregels, BCC alleen in de envelop", async () => {
  const m = buildMessage({ ...base, to: ["a@x.nl", "a2@x.nl"], cc: ["c@x.nl"], bcc: ["geheim1@x.nl", "geheim2@x.nl"] });
  const { raw, envelope } = await sendStream(m);
  ok(/^To: a@x\.nl, a2@x\.nl$/m.test(raw), `To-kop: ${raw.slice(0, 300)}`);
  ok(/^Cc: c@x\.nl$/m.test(raw), "Cc-kop");
  ok(!/bcc/i.test(raw.split("\n\n")[0]), "geen Bcc-kop");
  ok(!raw.includes("geheim1@x.nl") && !raw.includes("geheim2@x.nl"), "BCC-adressen staan nergens in het bericht");
  eq(envelope.to.sort(), ["a2@x.nl", "a@x.nl", "c@x.nl", "geheim1@x.nl", "geheim2@x.nl"]);
  eq(envelope.from, "support@pasr.nl");
  ok(/^Reply-To: inbox@pasr\.nl$/m.test(raw), "Reply-To naar de inbox");
  ok(/^From: Pasr <support@pasr\.nl>$/m.test(raw));
  ok(/^X-Pasr-Ticket: mail$/m.test(raw), "eigen mail herkenbaar");
  ok(/^Message-ID: <pasr-mail-abc@pasr\.nl>$/m.test(raw));
});

Deno.test("alleen BCC: de To-kop toont de afzender zelf; geen To/CC van derden", async () => {
  const m = buildMessage({ ...base, to: [], cc: [], bcc: ["b1@x.nl", "b2@x.nl"] });
  const { raw, envelope } = await sendStream(m);
  ok(/^To: support@pasr\.nl$/m.test(raw), `To-kop: ${raw.slice(0, 300)}`);
  ok(!/^Cc:/m.test(raw));
  ok(!raw.includes("b1@x.nl"));
  eq(envelope.to, ["b1@x.nl", "b2@x.nl"], "afzender zelf ontvangt niets");
});

Deno.test("ticketmail: onderwerp [#n], In-Reply-To, References, X-Pasr-Ticket, marker, bijlagen", async () => {
  const m = buildMessage({
    ...base, brand: "zakelijk", kind: "reply", from: "Pasr Zakelijk <zakelijk@pasr.nl>", to: ["klant@x.nl"], cc: [], bcc: [], number: 1001,
    messageId: "<pasr-ticket-1001.abc123@pasr.nl>", inReplyTo: "<k1@x.nl>", references: ["<a@x.nl>", "<k1@x.nl>"],
    attachments: [{ name: "offerte.pdf", type: "application/pdf", data: new TextEncoder().encode("%PDF-1.4 test") }],
  });
  const { raw } = await sendStream(m);
  ok(/^Subject: \[#1001\] Hoi$/m.test(raw), "onderwerp");
  ok(/^In-Reply-To: <k1@x\.nl>$/m.test(raw));
  ok(/^References: <a@x\.nl> <k1@x\.nl>$/m.test(raw));
  ok(/^X-Pasr-Ticket: 1001$/m.test(raw));
  ok(/multipart\/mixed/.test(raw) && /filename=\"?offerte\.pdf/.test(raw) && /application\/pdf/.test(raw), "bijlage als multipart/mixed\n" + raw.slice(0, 1500));
  // het antwoord erop wordt herkend als ticket 1001 en is "onze eigen mail" als hij als kopie terugkomt
  const parsed = parseMessage(raw);
  eq(parsed.messageId, "<pasr-ticket-1001.abc123@pasr.nl>");
  eq(parsed.header("x-pasr-ticket"), "1001");
  ok(parsed.text.startsWith("-- Antwoord boven deze lijn"), "marker bovenaan de tekst");
  eq(parsed.attachments.map((a) => a.filename), ["offerte.pdf"]);
});

Deno.test("nieuwsbrief en uitnodiging: afmeldlink, List-Unsubscribe en -Post alleen met één-klik-adres", async () => {
  const token = "0123456789abcdef0123456789abcdef";
  const m = buildMessage({
    ...base, kind: "news", to: ["ont@x.nl"], cc: [], bcc: [], unsub: { page: unsubPage(token), oneClick: oneClickUrl("https://abc.supabase.co/", token) }, markdown: "Nieuws",
  });
  const raw = (await sendStream(m)).raw.replace(/\n[ \t]+/g, " ");
  const page = `https://pasr.nl/afmelden/?t=${token}&k=nieuws`;
  { const want = `List-Unsubscribe: <https://abc.supabase.co/functions/v1/mail?stop=${token}>, <${page}>`; ok(raw.includes(want), JSON.stringify(want) + "\n" + JSON.stringify(raw.slice(0, 400))); }
  ok(/^List-Unsubscribe-Post: List-Unsubscribe=One-Click$/m.test(raw));
  ok(/^X-Pasr-Ticket: campaign$/m.test(raw));
  ok(m.html.includes(page.replace("&", "&amp;")) && m.text.includes(page), "link in de voet (html en tekst)");
  ok(/Meld je hier af/.test(m.html));
  // BCC-groep: één gemeenschappelijke pagina, geen -Post (geen persoonlijke code)
  const inv = buildMessage({ ...base, brand: "zakelijk", kind: "invite", to: [], cc: [], bcc: ["a@x.nl"], unsub: { page: genericUnsubPage("owners") }, markdown: "Kom kennismaken" });
  const r2 = await sendStream(inv);
  ok(r2.raw.includes("List-Unsubscribe: <https://pasr.nl/afmelden/?k=nieuws&s=owners>"), r2.raw.slice(0, 600));
  ok(!/List-Unsubscribe-Post/i.test(r2.raw));
  ok(inv.html.includes("uitnodigt om kennis te maken"), "uitnodigingstekst");
  // gewone mail: geen afmeldkop
  ok(!/List-Unsubscribe/i.test((await sendStream(buildMessage({ ...base, to: ["a@x.nl"], cc: [], bcc: [] }))).raw));
});

Deno.test("merken: eigen kop, icoon, kleuren en voet; licht en donker", () => {
  const p = renderMail({ brand: "pasr", kind: "mail", subject: "Onderwerp", markdown: "# Kop\n\n[[Knop|https://pasr.nl]]" });
  const z = renderMail({ brand: "zakelijk", kind: "mail", subject: "Onderwerp", markdown: "# Kop\n\n[[Knop|https://pasr.nl/zakelijk/]]" });
  ok(p.html.includes("https://pasr.nl/assets/mail-icon.png") && !p.html.includes("mail-icon-zakelijk"), "Pasr-icoon");
  ok(z.html.includes("https://pasr.nl/assets/mail-icon-zakelijk.png"), "zakelijk icoon");
  ok(z.html.includes("Pasr voor ondernemers") && !p.html.includes("Pasr voor ondernemers"), "zakelijke koptekst");
  ok(p.html.includes("#6A5CFF") && !p.html.includes("#2ED3A6"), "Pasr: iris");
  ok(z.html.includes("#2ED3A6") && !z.html.includes("#6A5CFF"), "Zakelijk: mint");
  ok(p.html.includes(">pasr.nl</a>") && z.html.includes(">pasr.nl/zakelijk</a>") && z.html.includes('href="https://pasr.nl/zakelijk/"'), "voet");
  for (const m of [p, z]) {
    ok(m.html.includes("#0A0B10") && m.html.includes("#15171F"), "donkere huisstijl");
    ok(/prefers-color-scheme: light/.test(m.html) && /color-scheme" content="light dark"/.test(m.html), "ook lichte modus");
    ok(m.html.startsWith("<!doctype html>") && /<title>Onderwerp<\/title>/.test(m.html));
    ok(m.text.endsWith("\n") && m.text.includes("https://pasr.nl"), "tekstvariant met voet");
  }
  ok(p.text.includes("Pasr · https://pasr.nl") && z.text.includes("Pasr Zakelijk · https://pasr.nl/zakelijk/"));
  eq(BRAND_STYLE.zakelijk.fromName, "Pasr Zakelijk");
  // onderwerp en voorvertoning zijn nooit HTML
  const x = renderMail({ brand: "pasr", kind: "mail", subject: "<script>x</script>", markdown: "<script>y</script>" });
  ok(!x.html.includes("<script>"), "geen script");
});

Deno.test("mime: bijlagen met inhoud bewaren tot de limiet", () => {
  const raw = [
    "From: a@x.nl", "To: support@pasr.nl", "Subject: Bijlage", "MIME-Version: 1.0", 'Content-Type: multipart/mixed; boundary="B"', "",
    "--B", "Content-Type: text/plain; charset=utf-8", "", "Zie bijlage", "--B", 'Content-Type: application/pdf; name="x.pdf"', 'Content-Disposition: attachment; filename="x.pdf"',
    "Content-Transfer-Encoding: base64", "", btoa("PDF-inhoud"), "--B--", "",
  ].join("\r\n");
  const plain = parseMessage(raw);
  eq(plain.attachments.length, 1);
  ok(!plain.attachments[0].data, "zonder keepBytes alleen naam en grootte");
  eq(plain.attachments[0].size, 10);
  const kept = parseMessage(raw, { keepBytes: 1024 });
  eq(new TextDecoder().decode(kept.attachments[0].data), "PDF-inhoud");
  ok(!parseMessage(raw, { keepBytes: 5 }).attachments[0].data, "groter dan de limiet: niet bewaard");
});

Deno.test("too_large noemt het echte maximum", () => {
  const t = tooLarge();
  eq([t.max_bytes, t.max_mb], [20 * 1024 * 1024, 20]);
  ok(t.message.includes("20 MB") && /downloadlink/.test(t.message));
  eq(LIMITS.attachmentsTotal, 20 * 1024 * 1024);
});

Deno.test("base64: blokken geven dezelfde uitkomst als btoa, ook voor 20 MB (snel en zonder kopie)", () => {
  for (const n of [0, 1, 2, 3, 4, 49151, 49152, 49153, 100000]) {
    const b = Uint8Array.from({ length: n }, (_, i) => (i * 31 + 7) & 255);
    const s = toBase64(b);
    eq(s, btoa(String.fromCharCode(...b.subarray(0, Math.min(n, 100000)))));
    eq(Array.from(fromBase64(s)), Array.from(b), `rond ${n}`);
  }
  const big = new Uint8Array(LIMITS.attachmentsTotal);
  big[0] = 1; big[big.length - 1] = 2;
  const t0 = performance.now();
  const r = parseAttachments([{ name: "x.bin", data_b64: toBase64(big) }]);
  ok(r.ok && r.list[0].data.length === big.length && r.list[0].data[big.length - 1] === 2, "20 MB rond");
  ok(performance.now() - t0 < 3000, "20 MB in ruim onder de CPU-limiet");
  eq(parseAttachments([{ name: "x", data_b64: "AA\nAA" }]).ok, true, "regeleinden mogen");
  eq(parseAttachments([{ name: "x", data_b64: "A$AA" }]), { ok: false, error: "bad_attachment" });
});

Deno.test("handtekening: Team Pasr / Team Pasr Zakelijk onder de inhoud, boven de voet; uit te zetten; platte tekst", () => {
  const p = renderMail({ brand: "pasr", kind: "news", subject: "S", markdown: "Hoi", unsubUrl: "https://pasr.nl/afmelden/?k=nieuws" });
  const z = renderMail({ brand: "zakelijk", kind: "mail", subject: "S", markdown: "Hoi" });
  ok(p.html.includes('<a href="https://pasr.nl/" style="text-decoration:none"><img src="https://pasr.nl/assets/handtekening-pasr.jpg" width="600" height="150" alt="Team Pasr"'), "Pasr-handtekening");
  ok(!p.html.includes("handtekening-pasr-zakelijk") && !p.html.includes("Team Pasr Zakelijk"), "Pasr niet zakelijk");
  ok(z.html.includes('<a href="https://pasr.nl/zakelijk/" style="text-decoration:none"><img src="https://pasr.nl/assets/handtekening-pasr-zakelijk.jpg"') && z.html.includes('alt="Team Pasr Zakelijk"'), "zakelijk");
  ok(!z.html.includes("handtekening-pasr.jpg"), "zakelijk niet Pasr");
  ok(/display:block;width:100%;max-width:600px;height:auto;border:0;border-radius:12px/.test(p.html), "responsief");
  const i = p.html.indexOf("handtekening-pasr.jpg");
  ok(p.html.indexOf("Hoi") < i && i < p.html.indexOf("Meld je hier af"), "tussen inhoud en voet");
  ok(p.text.indexOf("Team Pasr\nhttps://pasr.nl/") > p.text.indexOf("Hoi") && p.text.indexOf("Team Pasr\n") < p.text.indexOf("Geen mails meer?"), "platte tekst vóór de afmeldregel");
  ok(z.text.includes("Team Pasr Zakelijk\nhttps://pasr.nl/zakelijk/"), "platte tekst zakelijk");
  for (const kind of ["reply", "mail", "news", "invite"] as const) {
    ok(renderMail({ brand: "pasr", kind, subject: "S", markdown: "x", unsubUrl: "https://pasr.nl/afmelden/" }).html.includes("handtekening-pasr.jpg"), `standaard aan bij ${kind}`);
  }
  const uit = renderMail({ brand: "zakelijk", kind: "mail", subject: "S", markdown: "Hoi", signature: false });
  ok(!uit.html.includes("handtekening") && !uit.text.includes("Team Pasr"), "signature false laat hem weg");
  // geen ongeschoonde waarden: niets uit de invoer belandt in de handtekening
  const x = renderMail({ brand: "pasr", kind: "mail", subject: '"><script>1</script>', markdown: "<img src=x onerror=1>" });
  ok(!x.html.includes("<script>") && !x.html.includes("<img src=x"), "ge-escaped");
  // aanvragen: standaard true, alleen false zet uit
  const base = { to: "a@x.nl", subject: "S", body_md: "Hoi" };
  const c = (extra: Record<string, unknown>) => { const v = parseCompose({ ...base, ...extra }); return v.ok && v.value.signature; };
  eq([c({}), c({ signature: true }), c({ signature: false }), c({ signature: "false" })], [true, true, false, false]);
  const r = (extra: Record<string, unknown>) => { const v = parseReply({ number: 1, body_md: "Hoi", ...extra }); return v.ok && v.value.signature; };
  eq([r({}), r({ signature: false })], [true, false]);
  const t = (extra: Record<string, unknown>) => { const v = parseTest({ ...base, to: "a@x.nl", ...extra }); return v.ok && v.value.signature; };
  eq([t({}), t({ signature: false })], [true, false]);
  const pv = (extra: Record<string, unknown>) => { const v = parsePreview({ body_md: "Hoi", ...extra }); return v.ok && v.value.signature; };
  eq([pv({}), pv({ signature: false })], [true, false]);
  const cp = (extra: Record<string, unknown>) => { const v = parseCampaign({ audience: "users", subject: "S", body_md: "Hoi", request_id: "123e4567-e89b-42d3-a456-426614174000", ...extra }); return v.ok && v.value.signature; };
  eq([cp({}), cp({ signature: false })], [true, false]);
  // buildMessage geeft de keuze door
  const mk = (signature?: boolean) => buildMessage({ brand: "pasr", kind: "mail", from: "Pasr <a@pasr.nl>", to: ["b@x.nl"], cc: [], bcc: [], subject: "S", markdown: "Hoi", messageId: "<1@x>", signature });
  ok(mk().html.includes("handtekening-pasr.jpg") && !mk(false).html.includes("handtekening-pasr.jpg"), "buildMessage");
});

Deno.test("zakelijkSmtp: eigen login alleen als beide secrets staan", async () => {
  const { zakelijkSmtp, transportOptions } = await import("./send.ts");
  const e = (m: Record<string, string>) => (k: string) => m[k] ?? "";
  eq(zakelijkSmtp(e({})), false);
  eq(zakelijkSmtp(e({ PASR_SMTP_ZAKELIJK_USER: "zakelijk@pasr.nl" })), false);
  const env = e({ PASR_SMTP_HOST: "h", PASR_SMTP_USER: "support@pasr.nl", PASR_SMTP_PASSWORD: "a", PASR_SMTP_ZAKELIJK_USER: "zakelijk@pasr.nl", PASR_SMTP_ZAKELIJK_PASSWORD: "b" });
  eq(zakelijkSmtp(env), true);
  eq(transportOptions(env, "zakelijk").auth.user, "zakelijk@pasr.nl");
  eq(transportOptions(env, "pasr").auth.user, "support@pasr.nl");
});
