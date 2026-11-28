// Tests voor de Markdown-renderer (geen netwerk): deno test supabase/functions/mail/markdown_test.ts
import { BRAND_STYLE } from "./layout.ts";
import { esc, markdownProblem, parseMarkdown, plainToMarkdown, renderMarkdown, safeUrl, textToHtml } from "./markdown.ts";

const T = BRAND_STYLE.pasr.theme;
const html = (md: string, vars = {}) => renderMarkdown(md, T, vars).html;
const text = (md: string, vars = {}) => renderMarkdown(md, T, vars).text;
function eq(a: unknown, b: unknown, msg = "") {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg} verwacht ${y}, kreeg ${x}`);
}
function ok(v: unknown, msg = "") { if (!v) throw new Error(`niet waar: ${msg}`); }
const has = (s: string, part: string, msg = "") => ok(s.includes(part), `${msg} «${part}» niet in: ${s.slice(0, 400)}`);
const hasNot = (s: string, part: string, msg = "") => ok(!s.includes(part), `${msg} «${part}» wel in: ${s.slice(0, 400)}`);

Deno.test("koppen, alinea's en harde regelafbreking", () => {
  const h = html("# Groot\n## Middel\n### Klein\n#### Nog kleiner\n\nEerste regel\nTweede regel\n\nNieuwe alinea");
  has(h, "<h2 "); has(h, "<h3 "); has(h, "<h4 ");
  eq((h.match(/<h4 /g) ?? []).length, 2, "koppen 3 en 4+ zijn allebei h4");
  has(h, "Eerste regel<br>Tweede regel");
  eq((h.match(/<p /g) ?? []).length, 2);
  eq(text("# Groot\n\nTekst"), "GROOT\n=====\n\nTekst");
  // twee spaties en backslash aan het regeleinde zijn ook gewoon een regelafbreking
  has(html("a  \nb"), "a<br>b");
  has(html("a\\\nb"), "a<br>b");
});

Deno.test("vet, cursief, code, doorgestreept, genest", () => {
  const h = html("**vet** en *cursief* en _ook cursief_ en __ook vet__ en `code` en ~~weg~~");
  has(h, "<strong>vet</strong>"); has(h, "<em>cursief</em>"); has(h, "<em>ook cursief</em>"); has(h, "<strong>ook vet</strong>");
  has(h, ">code</code>"); has(h, "<s>weg</s>");
  has(html("***allebei***"), "<strong><em>allebei</em></strong>");
  has(html("**vet met *cursief* erin**"), "<strong>vet met <em>cursief</em> erin</strong>");
  // code is letterlijk: geen opmaak en geen HTML
  has(html("`**niet vet** <b>`"), "**niet vet** &lt;b&gt;");
  // snake_case en een sterretje met spaties blijven tekst
  has(html("snake_case_naam"), "snake_case_naam");
  has(html("5 * 3 * 2"), "5 * 3 * 2");
  has(html("een * los sterretje"), "een * los sterretje");
  // onafgesloten: letterlijk
  has(html("**niet afgesloten"), "**niet afgesloten");
  eq(text("**vet** *cursief* `c` ~~w~~"), "vet cursief c w");
});

Deno.test("lijsten, citaten, lijn", () => {
  const h = html("- een\n- twee met **vet**\n\n1. eerste\n2. tweede\n\n> citaat\n> tweede regel\n\n---");
  has(h, "<ul "); eq((h.match(/<li /g) ?? []).length, 4); has(h, "<ol "); has(h, "<blockquote "); has(h, 'class="pm-hr"');
  has(html("3. begin bij drie\n4. vier"), '<ol start="3"');
  has(html("* sterlijst\n+ plus"), "<ul ");
  // een lege regel tussen items van dezelfde lijst houdt de lijst bij elkaar
  eq((html("- a\n\n- b").match(/<ul /g) ?? []).length, 1);
  // een voortzetting met inspringen hoort bij het item
  has(html("- een\n  vervolg\n- twee"), "een<br>vervolg");
  eq(text("- een\n- twee\n\n1. a\n2. b"), "- een\n- twee\n\n1. a\n2. b");
  eq(text("> citaat\n> nog een"), "> citaat\n> nog een");
  has(html("***"), 'class="pm-hr"'); has(html("- - -"), 'class="pm-hr"'); has(html("___"), 'class="pm-hr"');
  // citaat met opmaak en een lijst erin
  const q = html("> **belangrijk**\n> - punt");
  has(q, "<blockquote "); has(q, "<strong>belangrijk</strong>"); has(q, "<ul ");
});

Deno.test("links: alleen https en mailto, nooit gevaarlijke adressen", () => {
  has(html("[Pasr](https://pasr.nl/zakelijk/)"), 'href="https://pasr.nl/zakelijk/"');
  has(html("[Mail ons](mailto:support@pasr.nl)"), 'href="mailto:support@pasr.nl"');
  has(html("[met titel](https://pasr.nl \"titel\")"), 'href="https://pasr.nl/"');
  has(html("Zie https://pasr.nl/support/. En verder"), '<a class="pm-a" href="https://pasr.nl/support/"');
  hasNot(html("Zie https://pasr.nl/support/. En"), "support/.</a>");
  // de tekst van een link mag opmaak hebben
  has(html("[**vet**](https://pasr.nl)"), "<strong>vet</strong></a>");
  // alles behalve https/mailto: tekst zonder link
  for (const bad of [
    "javascript:alert(1)", "JaVaScRiPt:alert(1)", "  javascript:alert(1)", "data:text/html,<script>alert(1)</script>", "http://pasr.nl", "ftp://pasr.nl", "//pasr.nl",
    "vbscript:x", "file:///etc/passwd", "tel:+31612345678", "https://user:pass@pasr.nl", "https://localhost", "mailto:geen-adres", "mailto:",
    "&#106;avascript:alert(1)", "java%0ascript:alert(1)", "https://x.nl\"onclick=\"alert(1)", "https://x.nl/<script>",
  ]) {
    const h = html(`[klik](${bad})`);
    hasNot(h, "<a ", `link naar ${bad}`);
    hasNot(h, "href=", `link naar ${bad}`);
    hasNot(h, "<script", bad);
  }
  eq(safeUrl("https://pasr.nl/a b"), null);
  eq(safeUrl("https://pasr.nl/a%20b"), "https://pasr.nl/a%20b");
  eq(safeUrl("mailto:a@b.nl", {}), null);
  eq(safeUrl("mailto:a@b.nl?subject=Hoi"), "mailto:a@b.nl?subject=Hoi");
});

Deno.test("knoppen: [[Tekst|https://…]] op een eigen regel", () => {
  const h = html("[[Maak kennis met Pasr Zakelijk|https://pasr.nl/zakelijk/]]");
  has(h, 'href="https://pasr.nl/zakelijk/"'); has(h, ">Maak kennis met Pasr Zakelijk</a>"); has(h, "<table ");
  eq(text("[[Meer info|https://pasr.nl/zakelijk/]]"), "Meer info: https://pasr.nl/zakelijk/");
  // een onveilig adres: geen knop, de tekst blijft
  const bad = html("[[Klik|javascript:alert(1)]]");
  hasNot(bad, "href"); hasNot(bad, "<table");
  // midden in een alinea is het een gewone link
  const mid = html("Lees [[hier|https://pasr.nl]] meer");
  has(mid, "<a "); hasNot(mid, "<table");
  // knoptekst wordt ge-escaped
  has(html("[[<b>x</b>|https://pasr.nl]]"), "&lt;b&gt;x&lt;/b&gt;");
});

Deno.test("afbeeldingen: alleen https", () => {
  const h = html("![Logo van Pasr](https://pasr.nl/assets/icon.png)");
  has(h, '<img src="https://pasr.nl/assets/icon.png" alt="Logo van Pasr"'); has(h, "max-width:100%");
  hasNot(html("![x](http://pasr.nl/a.png)"), "<img");
  hasNot(html("![x](javascript:alert(1))"), "<img");
  hasNot(html("![x](data:image/png;base64,AAAA)"), "<img");
  hasNot(html("![x](https://a.nl/\" onerror=\"alert(1))"), "onerror=\"");
  // alt-tekst wordt ge-escaped
  has(html('![a"b<c](https://pasr.nl/a.png)'), 'alt="a&quot;b&lt;c"');
  // in een alinea blijft het een afbeelding in de regel
  has(html("Zie ![i](https://pasr.nl/i.png) hier"), "<img ");
  eq(text("![Logo](https://pasr.nl/a.png)"), "Logo (https://pasr.nl/a.png)");
});

Deno.test("XSS: niets raw, alles ge-escaped", () => {
  const attacks = [
    "<script>alert(1)</script>", "<img src=x onerror=alert(1)>", "<svg onload=alert(1)>", "<a href=\"javascript:alert(1)\">x</a>", "<iframe src=//evil></iframe>",
    "<style>body{display:none}</style>", "<!-- c -->", "</td></tr></table><script>x</script>", "<b onmouseover=alert(1)>x</b>", "&lt;script&gt;", "<math><mi xlink:href=\"data:x\">",
    "\"><script>alert(1)</script>", "'><img src=x onerror=1>",
  ];
  for (const a of attacks) {
    for (const md of [a, `# ${a}`, `**${a}**`, `- ${a}`, `> ${a}`, `[${a}](https://pasr.nl)`, `[[${a}|https://pasr.nl]]`, `![${a}](https://pasr.nl/a.png)`, `\`${a}\``]) {
      const h = html(md);
      ok(!/<(script|iframe|style|svg|math|img src=x|b onmouse|a href="javascript)/i.test(h), `onveilig voor ${md}: ${h}`);
      // geen event handler als attribuut van een echte tag (in ge-escapete tekst mag "onerror=" wel staan)
      ok(!/<[a-z0-9]+\s[^>]*\bon\w+\s*=/i.test(h.replace(/="[^"]*"/g, '=""')), `event handler voor ${md}: ${h}`);
      ok(!/<!--/.test(h), "geen commentaar");
    }
  }
  // het resultaat bevat alleen onze eigen tags
  const sample = html("# K\n\n**v** *c* `x` ~~s~~ [l](https://pasr.nl) <u>x</u>\n\n- a\n\n> q\n\n[[B|https://pasr.nl]]\n\n![a](https://pasr.nl/a.png)\n\n---");
  const tags = new Set([...sample.matchAll(/<\/?([a-z0-9]+)/g)].map((m) => m[1]));
  const allowed = new Set(["p", "h2", "strong", "em", "code", "s", "a", "ul", "li", "blockquote", "table", "tr", "td", "div", "img", "br"]);
  for (const t of tags) ok(allowed.has(t), `onverwachte tag ${t}`);
  // steuntekens en onzichtbare tekens gaan eruit
  hasNot(html("a\u0000b‮c"), "\u0000"); hasNot(html("a‮b"), "‮");
  eq(esc(`<>&"'`), "&lt;&gt;&amp;&quot;&#39;");
});

Deno.test("backslash-escapes en letterlijke tekens", () => {
  has(html("\\*geen cursief\\*"), "*geen cursief*");
  has(html("\\# geen kop"), "# geen kop");
  has(html("\\[geen link\\](https://pasr.nl)"), "[geen link](");
  has(html("a \\\\ b"), "a \\ b");
  has(html("a \\q b"), "a \\q b");
});

Deno.test("placeholders: {{voornaam}} met reserve, {{email}} niet toegestaan", () => {
  has(html("Hoi {{voornaam}}!", { voornaam: "Anna" }), "Hoi Anna!");
  has(html("Hoi {{ Voornaam }}!"), "Hoi daar!");
  has(html("Hoi {{voornaam}}!", { voornaam: "  " }), "Hoi daar!");
  // de naam is nooit HTML
  has(html("Hoi {{voornaam}}", { voornaam: "<img src=x onerror=1>" }), "Hoi &lt;img src=x onerror=1&gt;");
  hasNot(html("Hoi {{voornaam}}", { voornaam: "**vet**" }), "<strong>");
  eq(text("Hoi {{voornaam}},", { voornaam: "Léon" }), "Hoi Léon,");
  eq(markdownProblem("Mail aan {{email}}"), "bad_body");
  eq(markdownProblem("Mail aan {{ E-mail }}"), "bad_body");
  eq(markdownProblem("Hoi {{voornaam}}"), null);
  // andere accolades blijven gewoon staan
  has(html("{{iets anders}}"), "{{iets anders}}");
});

Deno.test("platte tekst als Markdown en als HTML", () => {
  const raw = "- niet een lijst\n1. ook niet\n# geen kop\n> geen citaat\n*ster* _streep_ [x](https://a.nl)";
  const h = html(plainToMarkdown(raw));
  hasNot(h, "<ul"); hasNot(h, "<ol"); hasNot(h, "<h2"); hasNot(h, "<blockquote"); hasNot(h, "<em>");
  eq(text(plainToMarkdown(raw)).replace(/\/\)/, ")"), raw.replace("https://a.nl", "https://a.nl"));
  eq(textToHtml("Hoi <b>x</b>\nregel 2\n\nNieuwe & alinea"), "<p>Hoi &lt;b&gt;x&lt;/b&gt;<br>regel 2</p><p>Nieuwe &amp; alinea</p>");
});

Deno.test("de boom: lege invoer, grote invoer en rommel blijven snel en veilig", () => {
  eq(parseMarkdown(""), []);
  eq(renderMarkdown("", T), { html: "", text: "" });
  // 50.000 onafgesloten opmaaktekens: lineair genoeg
  for (const junk of ["*a".repeat(25000), "[".repeat(50000), "_a".repeat(25000), "![".repeat(25000), "`".repeat(50000), "**".repeat(25000), "~a".repeat(25000)]) {
    const t0 = performance.now();
    const r = renderMarkdown(junk, T);
    const ms = performance.now() - t0;
    ok(ms < 3000, `te traag (${Math.round(ms)} ms) voor ${junk.slice(0, 6)}`);
    ok(!/<(script|iframe)/i.test(r.html));
  }
  // diep geneste citaten en opmaak lopen niet vast
  renderMarkdown("> ".repeat(500) + "x", T);
  renderMarkdown("*".repeat(300) + "a" + "*".repeat(300), T);
  renderMarkdown("[".repeat(300) + "a" + "](https://pasr.nl)".repeat(300), T);
});

Deno.test("de mail van een nieuwsbrief: realistisch voorbeeld", () => {
  const md = `# Nieuw in Pasr Zakelijk

Hoi {{voornaam}},

Je kunt nu **tickets** uitgeven voor je events en een *klantenkaart* met barcode maken.

- Gratis voor kleine zaken
- Werkt op iPhone en Android

[[Bekijk Pasr Zakelijk|https://pasr.nl/zakelijk/]]

> Pasr: alle klantenkaarten in één app.

Groet, het team`;
  const r = renderMarkdown(md, BRAND_STYLE.zakelijk.theme, { voornaam: "Els" });
  has(r.html, "Hoi Els,"); has(r.html, "#2ED3A6"); has(r.html, "<ul "); has(r.html, "Bekijk Pasr Zakelijk");
  has(r.text, "NIEUW IN PASR ZAKELIJK"); has(r.text, "- Gratis voor kleine zaken"); has(r.text, "Bekijk Pasr Zakelijk: https://pasr.nl/zakelijk/");
});
