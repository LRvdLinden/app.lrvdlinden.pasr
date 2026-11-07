// deno test supabase/functions/group-invite/index_test.ts
import { esc, render } from "./index.ts";

const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

Deno.test("mail: naam en groep HTML-veilig, onderwerp zonder regeleinden", () => {
  const m = render("Léon <script>", "Gezin & co\r\n");
  ok(m.html.includes("Léon &lt;script&gt;") && !m.html.includes("<script>"), "html escaped");
  ok(m.html.includes("Gezin &amp; co"), "groep escaped");
  ok(m.subject.startsWith("Léon <script> nodigt"), m.subject);
  ok(!m.html.includes("{{"), "alles ingevuld");
  ok(m.html.includes("https://pasr.nl/uitnodiging/"), "link");
});

Deno.test("escape", () => ok(esc(`"'&`) === "&quot;&#39;&amp;", "esc"));
