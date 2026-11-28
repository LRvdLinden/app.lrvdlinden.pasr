// PasrBeheer › Mail (Inbox, Nieuwe mail, Nieuwsbrief). Praat via admin.js (window.PasrBeheerCore) met de functie admin,
// acties mail_* die doorsturen naar de functie mail. Contract: docs/mail-contract (zie beheer/README.md).
// Veiligheid: geen innerHTML met data (alles via createElement/textContent); HTML van binnengekomen mail alleen in een
// sandboxed iframe zonder scripts; HTML van de eigen renderer (mail_preview) in een Shadow DOM na opschonen.
// Geen e-mailadressen in console of logs; BCC-lijsten worden nergens bewaard.
(() => {
  "use strict";
  const core = window.PasrBeheerCore;
  if (!core) return;
  const { api, el, num, ago, toast } = core;
  const $ = (id) => document.getElementById(id);

  // ---- constanten en teksten ----
  const MAX_ATT = 10 * 1024 * 1024;       // totaal aan bijlagen per mail
  const MAX_CALL = 200;                   // adressen per aanroep
  const MAX_BCC_MAIL = 50;                // BCC per mail (de server splitst of weigert daarboven)
  const BRANDS = { pasr: "Pasr", zakelijk: "Pasr Zakelijk" };
  const STATUS = { new: "Nieuw", open: "Open", pending: "Wacht op klant", closed: "Gesloten" };
  const STATUS_CLS = { new: "bad", open: "ok", pending: "wait", closed: "" };
  const PRIO = { low: "Laag", normal: "Normaal", high: "Hoog", urgent: "Urgent" };
  const FILTERS = [["active", "Actief"], ["all", "Alle"], ["new", "Nieuw"], ["open", "Open"], ["pending", "Wacht"], ["closed", "Gesloten"]];
  const ERR = {
    bad_subject: "Vul een onderwerp in (hoogstens 200 tekens).",
    bad_body: "Schrijf een bericht.",
    bad_address: "Eén of meer e-mailadressen zijn ongeldig.",
    too_many: "Te veel ontvangers in één keer (hoogstens 200 per verzending, 50 BCC per mail).",
    too_large: "De bijlagen zijn samen te groot (hoogstens 10 MB).",
    rate_limited: "Even wachten: te veel mails in korte tijd. Probeer het over een paar minuten opnieuw.",
    smtp_not_configured: "E-mail versturen is nog niet ingesteld (PASR_SMTP_*).",
    imap_not_configured: "Mail ophalen is nog niet ingesteld (PASR_IMAP_*).",
    bad_brand: "Kies Pasr of Pasr Zakelijk.",
    bad_audience: "Kies een doelgroep.",
    no_recipients: "Er zijn geen ontvangers in deze doelgroep.",
    duplicate: "Deze nieuwsbrief is al verstuurd.",
    not_found: "Niet gevonden.",
    bad_status: "Onbekende status.",
    bad_attachment: "Een bijlage kon niet worden gebruikt.",
  };
  const errMsg = (e) => ERR[e && e.code] || (e && e.message) || "Er ging iets mis.";

  // Alle mailacties via admin (actie mail_<naam>); fouten krijgen een eigen Nederlandse tekst.
  async function call(name, params) {
    try { return await api("mail_" + name, params || {}); }
    catch (e) { if (e.status === 401) throw e; e.message = errMsg(e); throw e; }
  }

  // ---- hulpfuncties ----
  const EMAIL_RE = /^[^\s@<>(),;:"\[\]\\]+@[^\s@<>(),;:"\[\]\\]+\.[A-Za-z]{2,}$/;
  const validEmail = (s) => s.length <= 254 && EMAIL_RE.test(s);
  // "a@x.nl, Naam <b@y.nl>; c@z.nl" -> ["a@x.nl","b@y.nl","c@z.nl"] (alles gescheiden door komma, puntkomma, spatie of regel)
  function parseAddresses(text) {
    const out = [];
    for (const seg of String(text || "").split(/[,;\n\r]+/)) {
      const m = seg.match(/<([^<>]+)>/);
      if (m) { out.push(m[1].trim()); continue; }
      for (const t of seg.split(/\s+/)) if (t) out.push(t.replace(/^["'()]+|["'()]+$/g, ""));
    }
    return out.filter(Boolean);
  }
  const fmtSize = (n) => n >= 1048576 ? (n / 1048576).toFixed(1).replace(".", ",") + " MB" : n >= 1024 ? Math.round(n / 1024) + " kB" : n + " B";
  const fmtDT = (iso) => iso ? new Date(iso).toLocaleString("nl-NL", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "";
  const plural = (n, one, many) => `${num(n)} ${n === 1 ? one : many}`;
  let uid = 0;
  const nid = (p) => `${p}${++uid}`;
  const btn = (label, cls, onclick, type) => { const b = el("button", "btn " + (cls || ""), label); b.type = type || "button"; if (onclick) b.addEventListener("click", onclick); return b; };
  function field(labelText, control, hint) {
    const l = el("label", "mx-field"); l.append(el("span", "mx-lab", labelText), control);
    if (hint) l.append(el("span", "muted sm", hint));
    return l;
  }
  function seg(label, options, value, onChange) {
    const box = el("div", "seg"); box.setAttribute("role", "group"); box.setAttribute("aria-label", label);
    const set = (v, fire) => {
      value = v;
      box.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.v === v)));
      if (fire && onChange) onChange(v);
    };
    for (const [v, l] of options) { const b = el("button", null, l); b.type = "button"; b.dataset.v = v; b.addEventListener("click", () => set(v, true)); box.append(b); }
    set(value, false);
    return { root: box, get: () => value, set: (v) => set(v, false) };
  }
  function msgBox(cls) { const d = el("div", cls || "err"); d.setAttribute("role", "status"); d.setAttribute("aria-live", "polite"); return d; }
  function say(box, text, ok) { box.textContent = text || ""; box.classList.toggle("ok", !!ok); }

  // ---- bevestigingsdialoog ----
  function confirmDialog(title, rows, note, okLabel) {
    return new Promise((resolve) => {
      const modal = $("mailModal"), prev = document.activeElement;
      $("mmTitle").textContent = title;
      const dl = $("mmRows"); dl.replaceChildren();
      for (const [k, v] of rows) { dl.append(el("dt", null, k), el("dd", null, v)); }
      $("mmNote").textContent = note || "";
      $("mmOk").textContent = okLabel || "Versturen";
      modal.classList.remove("hidden");
      $("mmOk").focus();
      const done = (v) => {
        modal.classList.add("hidden"); document.removeEventListener("keydown", key);
        $("mmOk").onclick = $("mmCancel").onclick = null;
        if (prev && prev.focus) prev.focus();
        resolve(v);
      };
      const key = (e) => {
        if (e.key === "Escape") done(false);
        if (e.key === "Tab") { // focus blijft in het venster
          const f = [$("mmCancel"), $("mmOk")], i = f.indexOf(document.activeElement);
          e.preventDefault(); f[(i + (e.shiftKey ? f.length - 1 : 1)) % f.length].focus();
        }
      };
      document.addEventListener("keydown", key);
      $("mmOk").onclick = () => done(true);
      $("mmCancel").onclick = () => done(false);
    });
  }

  // ---- adresveld: Aan, CC, BCC (altijd zichtbaar, meerdere adressen, teller, ongeldig rood, dubbele eruit) ----
  function addrField(labelText, opts) {
    opts = opts || {};
    const id = nid("mx-addr-");
    const items = []; // {addr, ok}
    let dups = 0;
    const root = el("div", "mx-field mx-addr");
    const lab = el("label", "mx-lab", labelText); lab.htmlFor = id;
    const box = el("div", "mx-addr-box");
    const chips = el("ul", "mx-chips"); chips.setAttribute("aria-label", labelText + ": adressen");
    const input = el("input"); input.id = id; input.type = "text"; input.autocomplete = "off"; input.spellcheck = false; input.autocapitalize = "none";
    input.setAttribute("inputmode", "email");
    input.placeholder = opts.placeholder || "Typ of plak adressen";
    const count = el("div", "mx-count muted sm"); count.setAttribute("aria-live", "polite");
    box.append(chips, input);
    root.append(lab, box, count);
    if (opts.help) root.append(el("div", "muted sm", opts.help));
    const listeners = [];
    const state = () => ({ n: items.length, bad: items.filter((x) => !x.ok).length });
    function render() {
      chips.replaceChildren();
      items.forEach((it, i) => {
        const li = el("li", "mx-chip" + (it.ok ? "" : " bad"));
        li.append(el("span", null, it.addr));
        if (!it.ok) li.title = "Ongeldig e-mailadres";
        const x = el("button", null, "×"); x.type = "button"; x.setAttribute("aria-label", `${it.ok ? "Verwijder" : "Verwijder ongeldig adres"} ${it.addr}`);
        x.addEventListener("click", () => { items.splice(i, 1); render(); input.focus(); });
        li.append(x); chips.append(li);
      });
      const s = state();
      const parts = [];
      parts.push(s.n ? plural(s.n, "adres", "adressen") : "Geen adressen");
      if (s.bad) parts.push(`${num(s.bad)} ongeldig`);
      if (dups) parts.push(`${plural(dups, "dubbel", "dubbele")} overgeslagen`);
      count.textContent = parts.join(" · ");
      count.classList.toggle("bad", s.bad > 0);
      box.classList.toggle("has-bad", s.bad > 0);
      input.setAttribute("aria-invalid", String(s.bad > 0));
      listeners.forEach((f) => f());
    }
    function add(text) {
      for (const a of parseAddresses(text)) {
        if (items.some((x) => x.addr.toLowerCase() === a.toLowerCase())) { dups++; continue; }
        items.push({ addr: a, ok: validEmail(a) });
      }
      render();
    }
    const commit = () => { if (input.value.trim()) { const v = input.value; input.value = ""; add(v); } };
    input.addEventListener("paste", (e) => {
      const t = (e.clipboardData || window.clipboardData || {}).getData ? (e.clipboardData || window.clipboardData).getData("text") : "";
      if (t) { e.preventDefault(); add(t); }
    });
    input.addEventListener("input", () => { if (/[,;\s]$/.test(input.value) && /\S/.test(input.value)) commit(); });
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); commit(); }
      else if (e.key === "Backspace" && !input.value && items.length) { items.pop(); render(); }
    });
    input.addEventListener("blur", commit);
    box.addEventListener("click", (e) => { if (e.target === box || e.target === chips) input.focus(); });
    render();
    return {
      root, input,
      all: () => { commit(); return items.map((x) => x.addr); },
      valid: () => { commit(); return items.filter((x) => x.ok).map((x) => x.addr); },
      invalid: () => { commit(); return items.filter((x) => !x.ok).length; },
      clear: () => { items.length = 0; dups = 0; input.value = ""; render(); },
      onChange: (f) => listeners.push(f),
    };
  }

  // ---- bijlagen (bestandskeuze, slepen, base64, totaal hoogstens 10 MB) ----
  function attachments() {
    const files = []; // {name,type,size,data_b64,key}
    const id = nid("mx-file-");
    const root = el("div", "mx-field mx-att");
    root.append(el("span", "mx-lab", "Bijlagen"));
    const zone = el("label", "mx-drop"); zone.htmlFor = id;
    zone.append(el("span", null, "Sleep bestanden hierheen of kies ze"), el("span", "muted sm", "Samen hoogstens 10 MB"));
    const input = el("input", "sr"); input.type = "file"; input.multiple = true; input.id = id;
    const list = el("ul", "mx-files");
    const info = msgBox("err sm");
    root.append(zone, input, list, info);
    const total = () => files.reduce((a, f) => a + f.size, 0);
    function render() {
      list.replaceChildren();
      for (const f of files) {
        const li = el("li", "mx-file");
        li.append(el("span", "mx-fn", f.name), el("span", "muted sm", fmtSize(f.size)));
        const x = el("button", "icbtn", "×"); x.type = "button"; x.setAttribute("aria-label", `Verwijder bijlage ${f.name}`);
        x.addEventListener("click", () => { files.splice(files.indexOf(f), 1); render(); });
        li.append(x); list.append(li);
      }
      if (files.length) { const t = el("li", "mx-file total muted sm"); t.textContent = `Totaal ${fmtSize(total())} van ${fmtSize(MAX_ATT)}`; list.append(t); }
    }
    const read = (file) => new Promise((res, rej) => {
      const r = new FileReader();
      r.onload = () => { const s = String(r.result || ""), i = s.indexOf(","); res(i >= 0 ? s.slice(i + 1) : ""); };
      r.onerror = () => rej(new Error("read"));
      r.readAsDataURL(file);
    });
    async function add(fileList) {
      say(info, "");
      for (const file of Array.from(fileList || [])) {
        if (total() + file.size > MAX_ATT) { say(info, `"${file.name}" past er niet meer bij: bijlagen zijn samen hoogstens 10 MB.`); continue; }
        if (!file.size) { say(info, `"${file.name}" is leeg en is overgeslagen.`); continue; }
        try {
          const data = await read(file);
          files.push({ name: file.name.replace(/[\\/\u0000-\u001f]/g, "_").slice(0, 120), type: file.type || "application/octet-stream", size: file.size, data_b64: data });
        } catch { say(info, `"${file.name}" kon niet worden gelezen.`); }
      }
      render();
    }
    input.addEventListener("change", async () => { await add(input.files); input.value = ""; });
    for (const ev of ["dragenter", "dragover"]) zone.addEventListener(ev, (e) => { e.preventDefault(); zone.classList.add("over"); });
    for (const ev of ["dragleave", "drop"]) zone.addEventListener(ev, (e) => { e.preventDefault(); zone.classList.remove("over"); });
    zone.addEventListener("drop", (e) => add(e.dataTransfer && e.dataTransfer.files));
    input.addEventListener("focus", () => zone.classList.add("focus"));
    input.addEventListener("blur", () => zone.classList.remove("focus"));
    return {
      root, count: () => files.length, size: total,
      payload: () => files.map((f) => ({ name: f.name, type: f.type, data_b64: f.data_b64 })),
      clear: () => { files.length = 0; render(); say(info, ""); },
    };
  }

  // ---- veilig tonen van mail-HTML ----
  const DROP = "script,iframe,frame,frameset,object,embed,applet,form,input,button,textarea,select,base,meta,link,noscript,template,audio,video,source";
  const safeUrl = (v) => /^(https:|mailto:|#)/i.test(String(v).trim());
  // Opschonen: inert parsen; scripts, formulieren en event-attributen weg; alleen https/mailto-links.
  function cleanDoc(html, blockImages) {
    const cssParts = [];
    const src = String(html || "").replace(/<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi, (_, c) => { cssParts.push(c); return ""; })
      .replace(/(<[a-z][^>]*?\s)style(\s*=)/gi, "$1data-mx-style$2");
    const doc = new DOMParser().parseFromString(src, "text/html");
    doc.querySelectorAll(DROP).forEach((n) => n.remove());
    doc.querySelectorAll("*").forEach((n) => {
      for (const a of [...n.attributes]) {
        const nm = a.name.toLowerCase();
        if (nm.startsWith("on") || nm === "srcset" || nm === "formaction" || nm === "ping") n.removeAttribute(a.name);
        else if ((nm === "href" || nm === "action" || nm === "background" || nm === "xlink:href") && !safeUrl(a.value)) n.removeAttribute(a.name);
        else if (nm === "src" && !(blockImages ? /^data:image\//i.test(a.value.trim()) : /^(https:|data:image\/)/i.test(a.value.trim()))) n.removeAttribute(a.name);
      }
      if (n.tagName === "A") { n.setAttribute("target", "_blank"); n.setAttribute("rel", "noopener noreferrer"); }
    });
    return { doc, css: cssParts.join("\n") };
  }

  // Voorbeeld van onze eigen renderer: Shadow DOM (de strikte CSP laat geen inline stijl in een iframe toe). theme: light|dark.
  function mountPreview(host, html, theme) {
    const { doc, css } = cleanDoc(html, false);
    const root = host.shadowRoot || host.attachShadow({ mode: "open" });
    root.replaceChildren();
    const dark = theme === "dark";
    const themed = css
      .replace(/@media\s*\(\s*prefers-color-scheme\s*:\s*dark\s*\)/gi, dark ? "@media all" : "@media not all")
      .replace(/@media\s*\(\s*prefers-color-scheme\s*:\s*light\s*\)/gi, dark ? "@media not all" : "@media all")
      .replace(/(^|[\s,}{])html\b/g, "$1:host").replace(/(^|[\s,}{])body\b/g, "$1.mx-body");
    try {
      const base = new CSSStyleSheet();
      base.replaceSync(`:host{display:block;color-scheme:${dark ? "dark" : "light"};background:${dark ? "#0F1016" : "#F4F4F8"};color:${dark ? "#F2F1FA" : "#17162A"}}` +
        ".mx-body{min-height:220px;overflow:auto;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif}img{max-width:100%;height:auto}");
      const sheets = [base];
      if (themed.trim()) { const s = new CSSStyleSheet(); s.replaceSync(themed); sheets.push(s); }
      root.adoptedStyleSheets = sheets;
    } catch { /* oudere browser: alleen inline stijlen */ }
    const wrap = document.createElement("div");
    wrap.className = "mx-body";
    const b = doc.body;
    for (const a of ["bgcolor", "data-mx-style"]) if (b.hasAttribute(a)) wrap.setAttribute(a, b.getAttribute(a));
    wrap.append(...[...b.childNodes].map((n) => document.importNode(n, true)));
    root.append(wrap);
    root.querySelectorAll("[data-mx-style]").forEach((n) => { n.style.cssText = n.getAttribute("data-mx-style"); n.removeAttribute("data-mx-style"); });
    if (wrap.hasAttribute("bgcolor")) wrap.style.backgroundColor = wrap.getAttribute("bgcolor");
  }

  // Binnengekomen mail: sandboxed iframe zonder scripts, externe afbeeldingen geblokkeerd; of de tekstvariant.
  function mailBody(m) {
    const wrap = el("div", "mx-body-wrap");
    const text = String(m.body_text || "");
    const html = String(m.body_html || "");
    const showText = () => { wrap.replaceChildren(); const pre = el("pre", "mx-text", text || "(geen tekst)"); wrap.append(pre); };
    const showHtml = () => {
      wrap.replaceChildren();
      const { doc } = cleanDoc(html, true);
      const f = document.createElement("iframe");
      f.className = "mx-frame";
      f.setAttribute("sandbox", "allow-popups allow-popups-to-escape-sandbox"); // geen allow-scripts, geen allow-same-origin
      f.setAttribute("referrerpolicy", "no-referrer");
      f.setAttribute("csp", "default-src 'none'; img-src data:; style-src 'unsafe-inline'");
      f.setAttribute("title", "Inhoud van de mail");
      f.srcdoc = "<!doctype html><meta charset=utf-8><meta name=referrer content=no-referrer>" + doc.documentElement.outerHTML;
      f.style.background = "#fff";
      wrap.append(f, el("p", "muted sm", "Externe afbeeldingen en scripts worden niet geladen."));
    };
    if (!html) { showText(); return wrap; }
    const tabs = seg("Weergave", [["html", "Opgemaakt"], ["text", "Tekst"]], "html", (v) => (v === "text" ? showText() : showHtml()));
    tabs.root.classList.add("mx-view-seg");
    const holder = el("div"); holder.append(tabs.root, wrap);
    showHtml();
    return holder;
  }

  // ---- editor: Markdown met werkbalk en live voorbeeld (mail_preview) ----
  function wrapSel(ta, before, after, ph) {
    const s = ta.selectionStart, e = ta.selectionEnd, sel = ta.value.slice(s, e) || ph;
    ta.setRangeText(before + sel + after, s, e, "end");
    ta.setSelectionRange(s + before.length, s + before.length + sel.length);
    ta.focus(); ta.dispatchEvent(new Event("input", { bubbles: true }));
  }
  function linePrefix(ta, prefix, ph) {
    const s = ta.selectionStart, e = ta.selectionEnd;
    const ls = ta.value.lastIndexOf("\n", s - 1) + 1;
    const sel = ta.value.slice(s, e);
    if (!sel) { const pre = (ls === s ? "" : "\n") + prefix; ta.setRangeText(pre + ph, s, e, "end"); ta.setSelectionRange(s + pre.length, s + pre.length + ph.length); }
    else { ta.setRangeText(sel.split("\n").map((l) => prefix + l).join("\n"), s, e, "end"); }
    ta.focus(); ta.dispatchEvent(new Event("input", { bubbles: true }));
  }
  // selecteer het adres-deel zodat je het meteen kunt overtypen
  function insertLink(ta, before, label, mid, url, after) {
    const s = ta.selectionStart, e = ta.selectionEnd, sel = ta.value.slice(s, e) || label;
    const text = before + sel + mid + url + after;
    ta.setRangeText(text, s, e, "end");
    const u = s + before.length + sel.length + mid.length;
    ta.setSelectionRange(u, u + url.length);
    ta.focus(); ta.dispatchEvent(new Event("input", { bubbles: true }));
  }
  const TOOLS = [
    ["Kop", "Kop (## kop)", (t) => linePrefix(t, "## ", "Kop")],
    ["B", "Vet (**tekst**)", (t) => wrapSel(t, "**", "**", "vet"), "b"],
    ["I", "Cursief (*tekst*)", (t) => wrapSel(t, "*", "*", "cursief"), "i"],
    ["Lijst", "Lijst (- punt)", (t) => linePrefix(t, "- ", "punt")],
    ["Link", "Link [tekst](https://…)", (t) => insertLink(t, "[", "tekst", "](", "https://", ")")],
    ["Knop", "Knop [[tekst|https://…]]", (t) => insertLink(t, "[[", "Knoptekst", "|", "https://", "]]")],
    ["Afbeelding", "Afbeelding ![omschrijving](https://…)", (t) => insertLink(t, "![", "omschrijving", "](", "https://", ")")],
  ];
  function editor(o) {
    // o: {label, rows, getBrand(), getSubject(), placeholder, draftKey}
    const root = el("div", "mx-editor");
    const id = nid("mx-md-");
    const lab = el("label", "mx-lab", o.label || "Bericht (Markdown)"); lab.htmlFor = id;
    const bar = el("div", "mx-bar"); bar.setAttribute("role", "toolbar"); bar.setAttribute("aria-label", "Opmaak");
    const ta = el("textarea"); ta.id = id; ta.rows = o.rows || 12; ta.maxLength = 20000; ta.spellcheck = true;
    ta.placeholder = o.placeholder || "Schrijf je bericht. Gebruik de knoppen voor opmaak, of Markdown: ## kop, **vet**, - lijst.";
    for (const [lbl, title, fn, cls] of TOOLS) {
      const b = el("button", "mx-tool" + (cls ? " " + cls : ""), lbl); b.type = "button"; b.title = title; b.setAttribute("aria-label", title);
      b.addEventListener("click", () => fn(ta)); bar.append(b);
    }
    const hint = el("p", "muted sm", "Placeholder {{voornaam}} wordt de voornaam van de ontvanger (leeg: “daar”).");
    // voorbeeld
    const pv = el("div", "mx-preview");
    const pvHead = el("div", "mx-pv-head");
    pvHead.append(el("h3", null, "Voorbeeld"));
    let theme = "light", pvView = "html";
    const themeSeg = seg("Thema van het voorbeeld", [["light", "Licht"], ["dark", "Donker"]], "light", (v) => { theme = v; draw(); });
    const viewSeg = seg("Soort voorbeeld", [["html", "Opgemaakt"], ["text", "Tekst"]], "html", (v) => { pvView = v; draw(); });
    pvHead.append(viewSeg.root, themeSeg.root);
    const subj = el("div", "mx-pv-subj muted sm");
    const host = el("div", "mx-pv-host"); host.setAttribute("role", "region"); host.setAttribute("aria-label", "Voorbeeld van de mail");
    const txt = el("pre", "mx-text hidden");
    const state = msgBox("muted sm");
    pv.append(pvHead, subj, host, txt, state);
    let last = null, seq = 0, timer;
    function draw() {
      host.classList.toggle("hidden", pvView !== "html"); txt.classList.toggle("hidden", pvView !== "text");
      if (!last) return;
      if (pvView === "html") mountPreview(host, last.html, theme); else txt.textContent = last.text || "";
    }
    async function refresh() {
      const body = ta.value.trim(), my = ++seq;
      if (!body) { last = null; if (host.shadowRoot) host.shadowRoot.replaceChildren(); txt.textContent = ""; say(state, "Het voorbeeld verschijnt zodra je iets schrijft."); subj.textContent = ""; return; }
      say(state, "Voorbeeld bijwerken…");
      try {
        const subject = (o.getSubject && o.getSubject()) || "";
        const r = await call("preview", { body_md: ta.value, brand: o.getBrand ? o.getBrand() : "pasr", subject });
        if (my !== seq) return;
        last = r; say(state, ""); subj.textContent = subject ? "Onderwerp: " + subject : ""; draw();
      } catch (e) { if (my === seq && e.status !== 401) say(state, "Voorbeeld niet beschikbaar: " + errMsg(e)); }
    }
    const schedule = () => { clearTimeout(timer); timer = setTimeout(refresh, 450); };
    ta.addEventListener("input", schedule);
    root.append(lab, bar, ta, hint, pv);
    return {
      root, ta, refresh: schedule, now: refresh,
      get: () => ta.value, set: (v) => { ta.value = v; schedule(); },
      focus: () => ta.focus(), clear: () => { ta.value = ""; schedule(); },
    };
  }

  // ---- gedeelde verzend-hulp ----
  function totals(to, cc, bcc) {
    const a = new Set([...to.valid(), ...cc.valid(), ...bcc.valid()].map((x) => x.toLowerCase()));
    return a.size;
  }
  function checkRecipients(fields, msg) {
    for (const f of fields) if (f.invalid()) { say(msg, "Verwijder of corrigeer de rood gemarkeerde adressen."); f.input.focus(); return false; }
    return true;
  }
  function brandChoice(label, initial, onChange) {
    return seg(label, [["pasr", "Pasr"], ["zakelijk", "Pasr Zakelijk"]], initial, onChange);
  }

  // ======================= subtab: Nieuwe mail =======================
  function buildCompose(host) {
    const form = el("form", "mx-form card"); form.noValidate = true; form.autocomplete = "off";
    const to = addrField("Aan", { help: "Meerdere adressen: komma, spatie of nieuwe regel. Mag leeg zijn zolang er een BCC-adres is." });
    const cc = addrField("CC");
    const bcc = addrField("BCC", { help: "Ontvangers zien elkaar niet. BCC-lijsten worden niet bewaard." });
    const subject = el("input"); subject.type = "text"; subject.maxLength = 200; subject.autocomplete = "off";
    let brand = "pasr";
    const brandSeg = brandChoice("Merk", "pasr", (v) => { brand = v; ed.now(); });
    const ed = editor({ getBrand: () => brand, getSubject: () => subject.value.trim() });
    subject.addEventListener("input", () => ed.refresh());
    const att = attachments();
    const msg = msgBox();
    const testTo = el("input"); testTo.type = "text"; testTo.autocomplete = "off"; testTo.placeholder = "adres voor de testmail"; testTo.setAttribute("inputmode", "email"); testTo.setAttribute("aria-label", "Adres voor de testmail");
    const testBtn = btn("Testmail sturen", "ghost", null);
    const sendBtn = btn("Versturen…", "", null, "submit");
    // concept (zonder adressen) in localStorage
    const DK = "pasr.beheer.mail.draft";
    try { const d = JSON.parse(localStorage.getItem(DK) || "{}"); if (d.subject) subject.value = d.subject; if (d.body) ed.set(d.body); if (d.brand in BRANDS) { brand = d.brand; brandSeg.set(d.brand); } } catch { /* geen concept */ }
    const save = () => { try { localStorage.setItem(DK, JSON.stringify({ subject: subject.value, body: ed.get(), brand })); } catch { /* */ } };
    subject.addEventListener("input", save); ed.ta.addEventListener("input", save); brandSeg.root.addEventListener("click", save);

    const grid = el("div", "mx-cols");
    const left = el("div", "mx-stack");
    left.append(to.root, cc.root, bcc.root, field("Onderwerp", subject), el("div", "mx-field"), att.root);
    left.children[4].append(el("span", "mx-lab", "Merk"), brandSeg.root);
    grid.append(left, ed.root);
    const testRow = el("div", "mx-testrow"); testRow.append(testTo, testBtn);
    const actions = el("div", "row-btns"); actions.append(sendBtn, testRow);
    form.append(grid, actions, msg);
    host.append(form);

    testBtn.addEventListener("click", async () => {
      say(msg, "");
      const a = testTo.value.trim();
      if (!validEmail(a)) { say(msg, "Vul een geldig adres in voor de testmail."); testTo.focus(); return; }
      if (!subject.value.trim()) { say(msg, ERR.bad_subject); subject.focus(); return; }
      if (!ed.get().trim()) { say(msg, ERR.bad_body); ed.focus(); return; }
      testBtn.disabled = true;
      try { await call("test", { body_md: ed.get(), brand, subject: subject.value.trim(), to: a }); say(msg, "Testmail verstuurd.", true); toast("Testmail verstuurd."); }
      catch (e) { if (e.status !== 401) say(msg, errMsg(e)); }
      finally { testBtn.disabled = false; }
    });
    let busy = false;
    form.addEventListener("submit", async (e) => {
      e.preventDefault(); if (busy) return;
      say(msg, "");
      if (!checkRecipients([to, cc, bcc], msg)) return;
      const T = to.valid(), C = cc.valid(), B = bcc.valid();
      if (!T.length && !B.length) { say(msg, "Vul minstens één adres in bij Aan of BCC."); (T.length ? bcc : to).input.focus(); return; }
      const all = totals(to, cc, bcc);
      if (all > MAX_CALL || B.length > MAX_CALL) { say(msg, ERR.too_many); return; }
      if (!subject.value.trim()) { say(msg, ERR.bad_subject); subject.focus(); return; }
      if (!ed.get().trim()) { say(msg, ERR.bad_body); ed.focus(); return; }
      const rows = [["Merk", BRANDS[brand]], ["Onderwerp", subject.value.trim()],
        ["Ontvangers", `${plural(all, "adres", "adressen")} (Aan ${num(T.length)}, CC ${num(C.length)}, BCC ${num(B.length)})`]];
      if (att.count()) rows.push(["Bijlagen", `${plural(att.count(), "bestand", "bestanden")}, ${fmtSize(att.size())}`]);
      const note = B.length > MAX_BCC_MAIL ? `Meer dan ${MAX_BCC_MAIL} BCC-adressen: de server verstuurt dit in meerdere mails. ` : "";
      if (!(await confirmDialog("Mail versturen?", rows, note + "Antwoorden komen terug in de Inbox. Dit kan niet worden teruggedraaid.", "Versturen"))) { sendBtn.focus(); return; }
      busy = true; sendBtn.disabled = true;
      try {
        const r = await call("compose", { to: T, cc: C, bcc: B, subject: subject.value.trim(), body_md: ed.get(), brand, attachments: att.payload(), thread: true });
        const txt = `Verstuurd: ${num(r.sent ?? 0)}${r.failed ? `, mislukt: ${num(r.failed)}` : ""}${r.number ? ` (ticket #${r.number})` : ""}.`;
        say(msg, txt, !r.failed); toast(txt);
        if (!r.failed) { to.clear(); cc.clear(); bcc.clear(); subject.value = ""; ed.clear(); att.clear(); save(); }
      } catch (err) { if (err.status !== 401) say(msg, errMsg(err)); }
      finally { busy = false; sendBtn.disabled = false; }
    });
    return { show: () => ed.refresh() };
  }

  // ======================= subtab: Nieuwsbrief =======================
  function buildNews(host) {
    const AUD = { users: ["Gebruikers", "pasr"], owners: ["Ondernemers", "zakelijk"] };
    const form = el("form", "mx-form card"); form.noValidate = true; form.autocomplete = "off";
    let audience = "users", brand = "pasr", brandTouched = false, requestId = crypto.randomUUID();
    const count = el("b", null, "–"); count.setAttribute("aria-live", "polite");
    const audSeg = seg("Doelgroep", [["users", "Gebruikers"], ["owners", "Ondernemers"]], "users", (v) => {
      audience = v; if (!brandTouched) { brand = AUD[v][1]; brandSeg.set(brand); }
      loadCount(); ed.now();
    });
    const brandSeg = brandChoice("Merk", "pasr", (v) => { brand = v; brandTouched = true; ed.now(); });
    const subject = el("input"); subject.type = "text"; subject.maxLength = 200; subject.autocomplete = "off";
    const ed = editor({ getBrand: () => brand, getSubject: () => subject.value.trim(), placeholder: "Schrijf de nieuwsbrief. Begin met “Hoi {{voornaam}},”. Elke mail krijgt automatisch een afmeldlink." });
    subject.addEventListener("input", () => { ed.refresh(); requestId = crypto.randomUUID(); });
    ed.ta.addEventListener("input", () => { requestId = crypto.randomUUID(); });
    const att = attachments();
    const msg = msgBox();
    const testTo = el("input"); testTo.type = "text"; testTo.autocomplete = "off"; testTo.placeholder = "adres voor de testmail"; testTo.setAttribute("inputmode", "email"); testTo.setAttribute("aria-label", "Adres voor de testmail");
    const testBtn = btn("Testmail sturen", "ghost");
    const sendBtn = btn("Versturen…", "", null, "submit");
    const cnt = el("div", "mx-audcount"); cnt.append(el("span", "muted", "Ontvangers"), count, el("span", "muted sm", "(alleen een aantal; het beheer ziet nooit adressenlijsten)"));
    const left = el("div", "mx-stack");
    const f1 = el("div", "mx-field"); f1.append(el("span", "mx-lab", "Doelgroep"), audSeg.root, cnt);
    const f2 = el("div", "mx-field"); f2.append(el("span", "mx-lab", "Merk"), brandSeg.root, el("span", "muted sm", "Volgt de doelgroep; je kunt het aanpassen."));
    left.append(f1, f2, field("Onderwerp", subject), att.root);
    const grid = el("div", "mx-cols"); grid.append(left, ed.root);
    const testRow = el("div", "mx-testrow"); testRow.append(testTo, testBtn);
    const actions = el("div", "row-btns"); actions.append(sendBtn, testRow);
    form.append(grid, actions, msg);
    // overzicht van campagnes
    const hist = el("article", "card mx-hist");
    const hh = el("header", "card-h"); hh.append(el("h2", null, "Eerdere nieuwsbrieven")); const rb = btn("Vernieuwen", "ghost sm", () => loadCampaigns()); hh.append(rb);
    const histList = el("div", "acc-list"); histList.setAttribute("aria-live", "polite");
    hist.append(hh, histList);
    host.append(form, hist);

    let audN = null;
    async function loadCount() {
      count.textContent = "–"; audN = null;
      const a = audience;
      try { const r = await call("campaign_audience", { audience: a }); if (a === audience) { audN = r.count || 0; count.textContent = num(audN); } }
      catch (e) { if (e.status !== 401) count.textContent = "?"; }
    }
    const CST = { draft: ["Concept", ""], sending: ["Bezig met versturen", "wait"], sent: ["Verstuurd", "ok"], cancelled: ["Geannuleerd", ""] };
    let pollTimer = null;
    async function loadCampaigns() {
      let rows = [];
      try { const r = await call("campaign_list", {}); rows = Array.isArray(r) ? r : (r.items || r.campaigns || []); }
      catch (e) { if (e.status !== 401) { histList.replaceChildren(el("p", "empty", errMsg(e))); } return; }
      histList.replaceChildren();
      if (!rows.length) histList.append(el("p", "empty", "Nog geen nieuwsbrieven verstuurd."));
      for (const c of rows) {
        const row = el("div", "hist");
        const l = el("div"); const st = CST[c.status] || [c.status, ""];
        l.append(el("b", null, c.subject || "(geen onderwerp)"));
        const meta = el("div", "meta mx-meta");
        meta.append(el("span", "badge " + st[1], st[0]), el("span", null, BRANDS[c.brand] || c.brand), el("span", null, (AUD[c.audience] || [c.audience])[0]), el("span", null, fmtDT(c.created_at)));
        l.append(meta);
        const n = el("div", "n");
        n.append(el("b", null, `${num(c.sent)} / ${num(c.recipients)}`), el("div", "muted sm", c.failed ? `${num(c.failed)} mislukt` : "verstuurd"));
        if (c.status === "sending") {
          const pr = el("progress"); pr.max = Math.max(1, c.recipients || 1); pr.value = c.sent || 0; pr.setAttribute("aria-label", "Voortgang"); l.append(pr);
          const cb = btn("Annuleren", "danger sm", async () => {
            if (!(await confirmDialog("Verzending annuleren?", [["Nieuwsbrief", c.subject || ""], ["Al verstuurd", `${num(c.sent)} van ${num(c.recipients)}`]], "De rest wordt niet meer verstuurd.", "Annuleren"))) return;
            try { await call("campaign_cancel", { id: c.id }); toast("Verzending geannuleerd."); } catch (e) { if (e.status !== 401) toast(errMsg(e)); }
            loadCampaigns();
          });
          n.append(cb);
        }
        row.append(l, n); histList.append(row);
      }
      clearTimeout(pollTimer);
      if (rows.some((c) => c.status === "sending") && $("mail-news").offsetParent !== null) pollTimer = setTimeout(loadCampaigns, 4000);
    }

    testBtn.addEventListener("click", async () => {
      say(msg, "");
      const a = testTo.value.trim();
      if (!validEmail(a)) { say(msg, "Vul een geldig adres in voor de testmail."); testTo.focus(); return; }
      if (!subject.value.trim()) { say(msg, ERR.bad_subject); subject.focus(); return; }
      if (!ed.get().trim()) { say(msg, ERR.bad_body); ed.focus(); return; }
      testBtn.disabled = true;
      try { await call("test", { body_md: ed.get(), brand, subject: subject.value.trim(), to: a }); say(msg, "Testmail verstuurd.", true); toast("Testmail verstuurd."); }
      catch (e) { if (e.status !== 401) say(msg, errMsg(e)); }
      finally { testBtn.disabled = false; }
    });
    let busy = false;
    form.addEventListener("submit", async (e) => {
      e.preventDefault(); if (busy) return;
      say(msg, "");
      if (!subject.value.trim()) { say(msg, ERR.bad_subject); subject.focus(); return; }
      if (!ed.get().trim()) { say(msg, ERR.bad_body); ed.focus(); return; }
      let n;
      try { n = (await call("campaign_audience", { audience })).count || 0; count.textContent = num(n); }
      catch (err) { if (err.status !== 401) say(msg, errMsg(err)); return; }
      if (!n) { say(msg, ERR.no_recipients); return; }
      const rows = [["Doelgroep", AUD[audience][0]], ["Ontvangers", plural(n, "persoon", "personen")], ["Merk", BRANDS[brand]], ["Onderwerp", subject.value.trim()]];
      if (att.count()) rows.push(["Bijlagen", `${plural(att.count(), "bestand", "bestanden")}, ${fmtSize(att.size())}`]);
      if (!(await confirmDialog("Nieuwsbrief versturen?", rows, "Elke mail krijgt een eigen afmeldlink; afgemelde adressen worden overgeslagen. Dit kan niet worden teruggedraaid.", "Versturen"))) { sendBtn.focus(); return; }
      busy = true; sendBtn.disabled = true;
      try {
        const r = await call("campaign_send", { audience, brand, subject: subject.value.trim(), body_md: ed.get(), request_id: requestId, attachments: att.payload() });
        const txt = `Nieuwsbrief wordt verstuurd naar ${num(r.recipients ?? n)} ${((r.recipients ?? n) === 1) ? "persoon" : "personen"}.`;
        say(msg, txt, true); toast(txt);
        subject.value = ""; ed.clear(); att.clear(); requestId = crypto.randomUUID();
        loadCampaigns();
      } catch (err) { if (err.status !== 401) say(msg, errMsg(err)); }
      finally { busy = false; sendBtn.disabled = false; }
    });
    return { show: () => { loadCount(); loadCampaigns(); ed.refresh(); }, hide: () => clearTimeout(pollTimer) };
  }

  // ======================= subtab: Inbox =======================
  function buildInbox(host) {
    let filter = "active", brandF = "", q = "", unreadOnly = false, page = 0, total = 0, openNo = null, items = [];
    const PAGE = 25;
    // statusregel
    const bar = el("div", "mx-status"); bar.setAttribute("aria-live", "polite");
    const dot = el("span", "dot"); const barTxt = el("span", "mx-status-t");
    const pollBtn = btn("Nu ophalen", "ghost sm", doPoll);
    bar.append(dot, barTxt, pollBtn);
    // gereedschap
    const tools = el("div", "acc-tools mx-tools");
    const fseg = el("div", "seg mx-filters"); fseg.setAttribute("role", "group"); fseg.setAttribute("aria-label", "Filter op status");
    const search = el("input"); search.type = "search"; search.placeholder = "Zoek op onderwerp, naam of tekst"; search.setAttribute("aria-label", "Zoek in de inbox"); search.autocomplete = "off"; search.spellcheck = false;
    const brandSel = el("select"); brandSel.setAttribute("aria-label", "Merk");
    for (const [v, l] of [["", "Alle merken"], ["pasr", "Pasr"], ["zakelijk", "Pasr Zakelijk"]]) { const o = el("option", null, l); o.value = v; brandSel.append(o); }
    const unrLab = el("label", "se-check mx-unread"); const unr = el("input"); unr.type = "checkbox"; unrLab.append(unr, document.createTextNode(" Alleen ongelezen"));
    tools.append(fseg, search, brandSel, unrLab);
    const err = el("div", "banner hidden"); err.setAttribute("role", "alert");
    // lijst en detail
    const layout = el("div", "mx-layout");
    const listCol = el("div", "mx-listcol");
    const list = el("ul", "mx-list"); list.setAttribute("aria-label", "Tickets");
    const pager = el("div", "mx-pager");
    const prev = btn("Vorige", "ghost sm", () => { if (page > 0) { page--; loadList(); } });
    const pageTxt = el("span", "muted sm"); pageTxt.setAttribute("aria-live", "polite");
    const next = btn("Volgende", "ghost sm", () => { if ((page + 1) * PAGE < total) { page++; loadList(); } });
    pager.append(prev, pageTxt, next);
    listCol.append(list, pager);
    const detail = el("section", "mx-detail card"); detail.setAttribute("aria-label", "Ticket");
    detail.tabIndex = -1;
    layout.append(listCol, detail);
    host.append(bar, tools, err, layout);
    showEmpty();

    function showEmpty() { detail.replaceChildren(el("p", "empty", "Kies een ticket om het gesprek te lezen.")); layout.classList.remove("mx-open"); }

    // filters
    function renderFilters(counts) {
      fseg.replaceChildren();
      for (const [k, l] of FILTERS) {
        const b = el("button", null, l); b.type = "button"; b.dataset.f = k; b.setAttribute("aria-pressed", String(k === filter));
        const n = counts ? (k === "all" ? (counts.new + counts.open + counts.pending + counts.closed) : k === "active" ? (counts.new + counts.open + counts.pending) : counts[k]) : null;
        if (n != null && !Number.isNaN(n)) b.append(document.createTextNode(" "), el("span", "n", num(n)));
        b.addEventListener("click", () => { filter = k; page = 0; loadList(); });
        fseg.append(b);
      }
    }
    renderFilters(null);
    let st;
    search.addEventListener("input", () => { clearTimeout(st); st = setTimeout(() => { q = search.value.trim(); page = 0; loadList(); }, 300); });
    brandSel.addEventListener("change", () => { brandF = brandSel.value; page = 0; loadList(); });
    unr.addEventListener("change", () => { unreadOnly = unr.checked; renderList(); });

    // IMAP/SMTP-status
    async function loadStatus() {
      try {
        const s = await call("status", {});
        const parts = [];
        let cls = "ok";
        parts.push(el("span", null, `Ontvangen (IMAP): ${s.imap ? "ingesteld" : "niet ingesteld"}`));
        parts.push(el("span", null, `Versturen (SMTP): ${s.smtp ? "ingesteld" : "niet ingesteld"}`));
        const sy = s.sync || {};
        if (s.imap) parts.push(el("span", null, `laatst opgehaald ${sy.last_run ? ago(sy.last_run) : "nog nooit"}${sy.fetched != null ? `, ${plural(sy.fetched, "mail", "mails")} bekeken, ${num(sy.imported || 0)} nieuw` : ""}`));
        if (!s.imap || !s.smtp) cls = "off";
        if (sy.last_error) { cls = "warn"; parts.push(el("span", "bad", "Fout bij ophalen: " + sy.last_error)); }
        dot.className = "dot " + cls;
        barTxt.replaceChildren(...parts);
        pollBtn.disabled = !s.imap;
        if (s.counts) { renderFilters(s.counts); setBadge(s.counts.unread); }
      } catch (e) { if (e.status !== 401) { dot.className = "dot warn"; barTxt.textContent = "Status niet beschikbaar: " + errMsg(e); } }
    }
    async function doPoll() {
      pollBtn.disabled = true; pollBtn.textContent = "Ophalen…";
      try {
        const r = await call("poll", {});
        if (r.skipped) toast("Mail ophalen is niet ingesteld (IMAP).");
        else if (r.ok === false) toast("Ophalen mislukt" + (r.error ? `: ${r.error}` : "."));
        else { const n = (r.new_threads || 0) + (r.replies || 0); toast(n ? `${plural(r.new_threads || 0, "nieuw ticket", "nieuwe tickets")}, ${plural(r.replies || 0, "antwoord", "antwoorden")}.` : `Geen nieuwe mail (${num(r.fetched || 0)} bekeken).`); }
      } catch (e) { if (e.status !== 401) toast(errMsg(e)); }
      pollBtn.textContent = "Nu ophalen";
      await loadStatus(); loadList();
    }

    // lijst
    async function loadList() {
      fseg.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.f === filter)));
      err.classList.add("hidden");
      list.setAttribute("aria-busy", "true");
      try {
        const p = { status: filter, q, page, page_size: PAGE };
        if (brandF) p.brand = brandF;
        const r = await call("thread_list", p);
        items = r.items || []; total = r.total || 0;
        if (r.counts) { renderFilters(r.counts); fseg.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.f === filter))); setBadge(r.counts.unread); }
        renderList();
      } catch (e) { if (e.status !== 401) { err.textContent = errMsg(e); err.classList.remove("hidden"); } }
      finally { list.removeAttribute("aria-busy"); }
    }
    function renderList() {
      list.replaceChildren();
      const shown = unreadOnly ? items.filter((t) => t.unread) : items;
      if (!shown.length) list.append(el("li", "empty", q ? "Geen tickets gevonden." : unreadOnly ? "Geen ongelezen tickets." : filter === "active" ? "Geen open tickets. Alles is beantwoord." : "Geen tickets."));
      for (const t of shown) {
        const li = el("li"); const b = el("button", "mx-item" + (t.unread ? " unread" : "") + (t.number === openNo ? " on" : "")); b.type = "button";
        if (t.number === openNo) b.setAttribute("aria-current", "true");
        const top = el("div", "mx-item-top");
        if (t.unread) { const d = el("span", "udot"); d.setAttribute("role", "img"); d.setAttribute("aria-label", "Ongelezen"); top.append(d); }
        top.append(el("span", "num", "#" + t.number), el("span", "mx-when muted sm", ago(t.last_message_at)));
        const subj = el("div", "mx-subj", t.subject || "(geen onderwerp)");
        const who = el("div", "mx-who muted sm", t.contact_name || t.contact_email || "");
        const badges = el("div", "mx-badges");
        badges.append(el("span", "badge " + (STATUS_CLS[t.status] || ""), STATUS[t.status] || t.status), el("span", "badge brand " + t.brand, BRANDS[t.brand] || t.brand || ""));
        const prevw = el("div", "mx-prev muted sm", t.preview || "");
        b.append(top, subj, who, prevw, badges);
        b.addEventListener("click", () => openThread(t.number));
        li.append(b); list.append(li);
      }
      const pages = Math.max(1, Math.ceil(total / PAGE));
      pageTxt.textContent = `Pagina ${page + 1} van ${pages} · ${plural(total, "ticket", "tickets")}`;
      prev.disabled = page === 0; next.disabled = page + 1 >= pages;
      pager.classList.toggle("hidden", total <= PAGE);
    }

    // detail
    async function openThread(n) {
      openNo = n;
      renderList();
      detail.replaceChildren(el("p", "muted", "Laden…"));
      layout.classList.add("mx-open");
      let r;
      try { r = await call("thread_get", { number: n }); }
      catch (e) { if (e.status !== 401) detail.replaceChildren(el("p", "err", errMsg(e))); return; }
      if (openNo !== n) return;
      renderThread(r);
      detail.focus({ preventScroll: false });
      loadStatus(); // ongelezen-teller
      const it = items.find((x) => x.number === n); if (it) { it.unread = false; renderList(); }
    }
    function renderThread(r) {
      const t = r.thread || {};
      detail.replaceChildren();
      const back = btn("← Terug naar de lijst", "ghost sm mx-back", () => { layout.classList.remove("mx-open"); openNo = null; renderList(); });
      const head = el("header", "mx-dhead");
      const h = el("h2"); h.append(el("span", "num", "#" + t.number + " "), document.createTextNode(t.subject || "(geen onderwerp)"));
      const meta = el("div", "mx-badges");
      meta.append(el("span", "badge " + (STATUS_CLS[t.status] || ""), STATUS[t.status] || t.status), el("span", "badge brand " + t.brand, BRANDS[t.brand] || ""));
      if (t.priority && t.priority !== "normal") meta.append(el("span", "badge wait", PRIO[t.priority] || t.priority));
      const who = el("p", "muted sm");
      who.append(document.createTextNode((t.contact_name ? t.contact_name + " · " : "")));
      if (t.contact_email) { const a = el("a", null, t.contact_email); a.href = "mailto:" + encodeURIComponent(t.contact_email).replace(/%40/g, "@"); who.append(a); }
      if (t.created_at) who.append(document.createTextNode(" · aangemaakt " + fmtDT(t.created_at)));
      head.append(h, meta, who);
      const thread = el("div", "mx-thread"); thread.setAttribute("aria-label", "Gesprek"); thread.setAttribute("role", "list");
      for (const m of r.messages || []) thread.append(messageEl(m));
      if (!(r.messages || []).length) thread.append(el("p", "empty", "Geen berichten."));
      detail.append(back, head, thread, replyForm(t, r), statusForm(t));
    }
    function messageEl(m) {
      const d = el("article", "mx-msg " + (m.direction || "in")); d.setAttribute("role", "listitem");
      const who = m.direction === "out" ? "Verstuurd" : m.direction === "note" ? "Interne notitie" : "Ontvangen";
      const hd = el("div", "mx-mh"); hd.append(el("b", null, who), el("span", "muted sm", fmtDT(m.created_at)));
      if (m.error) hd.append(el("span", "badge bad", "Niet verstuurd"));
      d.append(hd);
      const addr = [];
      if (m.from) addr.push(["Van", m.from]);
      if ((m.to || []).length) addr.push(["Aan", [].concat(m.to).join(", ")]);
      if ((m.cc || []).length) addr.push(["CC", [].concat(m.cc).join(", ")]);
      if (m.bcc_count) addr.push(["BCC", plural(m.bcc_count, "ontvanger", "ontvangers")]);
      if (addr.length) { const dl = el("dl", "mx-addrs muted sm"); for (const [k, v] of addr) dl.append(el("dt", null, k), el("dd", null, v)); d.append(dl); }
      if (m.error) d.append(el("p", "err sm", "Fout bij versturen: " + m.error));
      if (m.direction === "note") d.append(el("pre", "mx-text", m.body_text || ""));
      else d.append(mailBody(m));
      if ((m.attachments || []).length) {
        const ul = el("ul", "mx-atts");
        for (const a of m.attachments) {
          const li = el("li"); const b = el("button", "btn ghost sm"); b.type = "button";
          b.append(document.createTextNode(a.name || "bijlage"), el("span", "muted sm", " " + fmtSize(a.size || 0)));
          b.setAttribute("aria-label", `Download ${a.name || "bijlage"} (${fmtSize(a.size || 0)})`);
          b.addEventListener("click", () => download(a, b));
          li.append(b); ul.append(li);
        }
        d.append(ul);
      }
      return d;
    }
    async function download(a, b) {
      b.disabled = true;
      try {
        const r = await call("attachment", { id: a.id });
        const bin = atob(r.data_b64 || ""), buf = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
        const url = URL.createObjectURL(new Blob([buf], { type: "application/octet-stream" }));
        const link = document.createElement("a"); link.href = url; link.download = String(r.name || a.name || "bijlage").replace(/[\\/\u0000-\u001f]/g, "_"); link.rel = "noopener";
        document.body.append(link); link.click(); link.remove();
        setTimeout(() => URL.revokeObjectURL(url), 30000);
      } catch (e) { if (e.status !== 401) toast(errMsg(e)); }
      finally { b.disabled = false; }
    }

    function replyForm(t, r) {
      const wrap = el("section", "mx-reply"); wrap.setAttribute("aria-label", "Antwoorden");
      let kind = "reply", brand = t.brand in BRANDS ? t.brand : "pasr";
      const kindSeg = seg("Soort bericht", [["reply", "Antwoord aan klant"], ["note", "Interne notitie"]], "reply", (v) => { kind = v; sync(); });
      const form = el("form", "mx-form"); form.noValidate = true;
      // antwoord
      const replyBox = el("div", "mx-stack");
      const brandSeg = brandChoice("Merk", brand, (v) => { brand = v; ed.now(); });
      const ed = editor({ label: "Antwoord (Markdown)", rows: 8, getBrand: () => brand, getSubject: () => (/^re:/i.test(t.subject || "") ? t.subject : "Re: " + (t.subject || "")) + ` [#${t.number}]` });
      const cc = addrField("CC"), bcc = addrField("BCC");
      const att = attachments();
      const after = el("select"); after.setAttribute("aria-label", "Status na verzenden");
      for (const [v, l] of [["pending", "Wacht op klant"], ["open", "In behandeling"], ["closed", "Gesloten"]]) { const o = el("option", null, l); o.value = v; after.append(o); }
      const to = el("p", "muted sm", `Aan: ${t.contact_name ? t.contact_name + " " : ""}${t.contact_email ? "<" + t.contact_email + ">" : ""}`);
      const bf = el("div", "mx-field"); bf.append(el("span", "mx-lab", "Merk"), brandSeg.root);
      replyBox.append(to, bf, ed.root, cc.root, bcc.root, att.root, field("Status na verzenden", after));
      // notitie
      const noteBox = el("div", "mx-stack hidden");
      const note = el("textarea"); note.rows = 5; note.maxLength = 5000;
      noteBox.append(field("Interne notitie (alleen zichtbaar in het beheer)", note));
      const msg = msgBox();
      const go = btn("Versturen…", "", null, "submit");
      const actions = el("div", "row-btns"); actions.append(go);
      form.append(replyBox, noteBox, actions, msg);
      wrap.append(kindSeg.root, form);
      function sync() {
        replyBox.classList.toggle("hidden", kind !== "reply"); noteBox.classList.toggle("hidden", kind !== "note");
        go.textContent = kind === "note" ? "Notitie opslaan" : "Versturen…"; say(msg, "");
        if (kind === "reply") ed.refresh();
      }
      let busy = false;
      form.addEventListener("submit", async (e) => {
        e.preventDefault(); if (busy) return; say(msg, "");
        busy = true; go.disabled = true;
        try {
          if (kind === "note") {
            const text = note.value.trim(); if (!text) { say(msg, "Schrijf een notitie."); return; }
            await call("thread_note", { number: t.number, text }); toast("Notitie opgeslagen.");
          } else {
            if (!checkRecipients([cc, bcc], msg)) return;
            if (!ed.get().trim()) { say(msg, ERR.bad_body); ed.focus(); return; }
            const C = cc.valid(), B = bcc.valid();
            const rows = [["Merk", BRANDS[brand]], ["Ticket", "#" + t.number], ["Ontvangers", `${plural(1 + C.length + B.length, "adres", "adressen")} (klant${C.length ? `, CC ${num(C.length)}` : ""}${B.length ? `, BCC ${num(B.length)}` : ""})`],
              ["Status daarna", after.options[after.selectedIndex].text]];
            if (att.count()) rows.push(["Bijlagen", `${plural(att.count(), "bestand", "bestanden")}, ${fmtSize(att.size())}`]);
            if (!(await confirmDialog("Antwoord versturen?", rows, "Dit kan niet worden teruggedraaid.", "Versturen"))) return;
            const x = await call("thread_reply", { number: t.number, body_md: ed.get(), brand, cc: C, bcc: B, attachments: att.payload(), status: after.value });
            toast(x.email_sent === false ? "Antwoord opgeslagen, maar de mail is niet verstuurd." : "Antwoord verstuurd.");
          }
          await openThread(t.number); loadList(); loadStatus();
        } catch (err) { if (err.status !== 401) say(msg, errMsg(err)); }
        finally { busy = false; go.disabled = false; }
      });
      sync();
      return wrap;
    }
    function statusForm(t) {
      const box = el("section", "mx-statusform"); box.setAttribute("aria-label", "Status en prioriteit");
      const s = el("select"); const p = el("select");
      for (const [k, v] of Object.entries(STATUS)) { const o = el("option", null, v); o.value = k; o.selected = k === t.status; s.append(o); }
      for (const [k, v] of Object.entries(PRIO)) { const o = el("option", null, v); o.value = k; o.selected = k === (t.priority || "normal"); p.append(o); }
      const save = btn("Opslaan", "ghost", async () => {
        const body = { number: t.number };
        if (s.value !== t.status) body.status = s.value;
        if (p.value !== (t.priority || "normal")) body.priority = p.value;
        if (Object.keys(body).length === 1) { toast("Niets gewijzigd."); return; }
        save.disabled = true;
        try { await call("thread_status", body); toast("Opgeslagen."); await openThread(t.number); loadList(); loadStatus(); }
        catch (e) { if (e.status !== 401) toast(errMsg(e)); save.disabled = false; }
      });
      const row = el("div", "se-row"); row.append(field("Status", s), field("Prioriteit", p), save);
      box.append(row);
      return box;
    }

    return { show: () => { loadStatus(); loadList(); } };
  }

  // ======================= tab Mail =======================
  function setBadge(n) {
    const b = $("mailBadge"); if (!b) return;
    b.textContent = n > 99 ? "99+" : String(n || 0);
    b.classList.toggle("hidden", !n);
    const tab = $("tab-mail"); if (tab) tab.setAttribute("aria-label", n ? `Mail, ${n} ongelezen` : "Mail");
  }
  let built = false, parts = {}, sub = "inbox";
  const SUBS = ["inbox", "compose", "news"];
  function showSub(s, focus) {
    sub = s;
    for (const k of SUBS) {
      const tb = $("mtab-" + k), on = k === s;
      tb.setAttribute("aria-selected", String(on)); tb.tabIndex = on ? 0 : -1;
      $("mail-" + k).classList.toggle("hidden", !on);
    }
    if (parts.news && s !== "news") parts.news.hide();
    if (parts[s] && parts[s].show) parts[s].show();
    if (focus) $("mtab-" + s).focus();
    try { sessionStorage.setItem("pasr.beheer.mailsub", s); } catch { /* */ }
  }
  function build() {
    built = true;
    parts.inbox = buildInbox($("mail-inbox"));
    parts.compose = buildCompose($("mail-compose"));
    parts.news = buildNews($("mail-news"));
    SUBS.forEach((k, i) => {
      const tb = $("mtab-" + k);
      tb.addEventListener("click", () => showSub(k));
      tb.addEventListener("keydown", (e) => { // pijltjestoetsen binnen de subtabs
        const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (d) { e.preventDefault(); showSub(SUBS[(i + d + SUBS.length) % SUBS.length], true); }
        else if (e.key === "Home") { e.preventDefault(); showSub(SUBS[0], true); }
        else if (e.key === "End") { e.preventDefault(); showSub(SUBS[SUBS.length - 1], true); }
      });
    });
  }
  function show() {
    if (!built) build();
    let s = "inbox"; try { s = sessionStorage.getItem("pasr.beheer.mailsub") || "inbox"; } catch { /* */ }
    showSub(SUBS.includes(s) ? s : sub);
  }
  // ongelezen-teller in het menu (ook buiten de tab Mail)
  async function refreshBadge() {
    try { const s = await api("mail_status", {}); if (s && s.counts) setBadge(s.counts.unread); } catch { /* geen badge */ }
  }
  window.PasrMail = { show, refreshBadge, _test: { parseAddresses, validEmail } };
  setInterval(() => { if (!document.hidden && document.getElementById("app") && !document.getElementById("app").classList.contains("hidden")) refreshBadge(); }, 120000);
})();
