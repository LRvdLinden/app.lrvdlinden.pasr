// PasrBeheer (beheer.pasr.nl). Praat alleen met de functie admin; token in sessionStorage (weg als het tabblad dicht gaat).
// Geen inline scripts of styles (CSP): kleuren en breedtes gaan via element.style.
(() => {
  "use strict";
  const CFG = window.BEHEER || {};
  const URL_ADMIN = CFG.url ? CFG.url.replace(/\/+$/, "") + "/functions/v1/admin" : "";
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
  const svgEl = (tag, attrs) => { const e = document.createElementNS("http://www.w3.org/2000/svg", tag); for (const k in attrs) e.setAttribute(k, attrs[k]); return e; };
  const nf = new Intl.NumberFormat("nl-NL");
  const num = (n) => nf.format(Number(n) || 0);
  const store = { get(k) { try { return sessionStorage.getItem(k); } catch { return null; } },
                  set(k, v) { try { v == null ? sessionStorage.removeItem(k) : sessionStorage.setItem(k, v); } catch {} } };

  // ---- API ----
  let token = store.get("pasr.beheer.token");
  let expires = Number(store.get("pasr.beheer.exp") || 0);
  async function api(action, params = {}) {
    const headers = { "Content-Type": "application/json" };
    if (CFG.key) headers.apikey = CFG.key;
    if (token) headers.Authorization = "Bearer " + token;
    let res;
    try {
      res = await fetch(URL_ADMIN, { method: "POST", headers, body: JSON.stringify({ action, ...params }) });
    } catch { throw Object.assign(new Error("Geen verbinding met de server."), { code: "network" }); }
    let body = {};
    try { body = await res.json(); } catch {}
    if (!res.ok) {
      const code = body.error || "server_error";
      if (res.status === 401 && action !== "login") { signOut("Je sessie is verlopen. Log opnieuw in."); }
      throw Object.assign(new Error(errText(code, body)), { code, status: res.status });
    }
    return body;
  }
  function errText(code, body) {
    switch (code) {
      case "invalid_credentials": return "Onjuiste gebruikersnaam of wachtwoord.";
      case "locked": return `Te veel pogingen. Probeer het over ${Math.ceil((body.retry_after || 900) / 60)} minuten opnieuw.`;
      case "not_configured": return "Het beheer is nog niet ingericht (PASR_ADMIN_USER / PASR_ADMIN_PASSWORD).";
      case "unauthorized": return "Je sessie is verlopen. Log opnieuw in.";
      case "already_confirmed": return "Dit account is al bevestigd.";
      case "rate_limited": return "Even wachten: te veel verzoeken.";
      case "not_found": return "Niet gevonden.";
      case "bad_name": return "Vul een naam in.";
      case "bad_color": return "Kies een kaartkleur.";
      case "bad_domain": return "Dit is geen geldige website.";
      case "bad_guide": return "De cadeaubon-gids klopt niet (online en winkel: ja, nee of onbekend).";
      case "bad_guide_url": return "Vul bij de gids (voorwaarden of programmapagina) een geldig https-adres in.";
      case "bad_guide_date": return "Vul bij 'Gecontroleerd op' een geldige datum in.";
      case "bad_logo": return "Dit logo kan niet worden gebruikt (PNG, JPEG of WebP, kleiner dan 300 kB).";
      case "too_large": return "Het logo of kaartontwerp is te groot. Kies een kleiner bestand.";
      case "bad_cover": return "Dit kaartontwerp kan niet worden gebruikt (PNG of JPEG).";
      case "cover_too_large": return "Het kaartontwerp is te groot (hoogstens ~150 kB).";
      case "bad_email": return "Dit is geen geldig e-mailadres.";
      case "bad_url": return "Vul een geldig https-adres in.";
      case "bad_id": return "Kies een winkel uit de lijst (of typ het winkel-id).";
      case "weak_password": return "Kies een wachtwoord van minimaal 10 tekens met letters en cijfers.";
      case "exists": return "Dit account bestaat al. Vink aan dat je het wachtwoord wilt vervangen.";
      case "bad_body": return "Schrijf een bericht.";
      case "bad_audience": return "Kies een doelgroep.";
      case "bad_store": return "Kies een winkel (het winkel-id, bijv. ah).";
      case "duplicate": return "Dit bericht is in de laatste 10 minuten al verstuurd.";
      case "bad_platform": return "Kies Alles, Apple of Android.";
      case "bad_app": return "Kies Pasr, Pasr Zakelijk of beide (alleen bij Iedereen met meldingen aan).";
      case "apns_not_configured": return "Pushmeldingen zijn nog niet ingericht (APNS_KEY_P8 / APNS_KEY_ID).";
      case "bad_status": return "Onbekende status.";
      case "group_limit": return "Dit account zit al in 2 gedeelde Pasrs.";
      case "owner_taken": return "Dit Pasr-account is al eigenaar van een andere zaak. Gebruik een ander e-mailadres of laat het leeg.";
      case "has_owner": return "Deze zaak heeft al een eigenaar.";
      case "not_approved": return "Keur de zaak eerst goed; daarna kan de kaart online.";
      case "card_limit": return "Een zaak heeft hoogstens 5 stempelkaarten.";
      case "bad_reward": return "Vul een beloning in.";
      case "bad_total": return "Kies 2 tot 30 stempels.";
      case "bad_city": return "De plaats is te lang.";
      case "bad_address": return "Het adres is te lang (hoogstens 200 tekens).";
      case "bad_cooldown": return "Afkoeltijd: 0 tot 1440 minuten.";
      case "bad_max_per_scan": case "bad_settings": return "Max per scan: 1 tot 30; afkoeltijd: 0 tot 1440 minuten.";
      case "logo_too_large": return "Het logo is te groot (hoogstens ~150 kB). Kies een kleiner bestand.";
      case "no_website": return "Vul eerst een website in.";
      case "unreachable": return "Van deze website kon geen huisstijl worden gehaald. Kies zelf een kleur en logo.";
      case "bad_business": return "Vul de gegevens van de zaak in.";
      case "test_limit": return "Hoogstens 10 testklanten per kaart.";
      case "update_failed": return "Het account kon niet worden bijgewerkt. Probeer het opnieuw.";
      case "create_failed": case "seed_failed": return "Het review-account kon niet worden gemaakt. Probeer het opnieuw.";
      default: return `Er ging iets mis op de server (${code}).`;
    }
  }

  // ---- melding en bevestigen ----
  let toastTimer;
  function toast(text) {
    const t = $("toast");
    t.textContent = text;
    t.classList.remove("hidden");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.add("hidden"), 3200);
  }
  function ask(title, text, okLabel) {
    return new Promise((resolve) => {
      $("mTitle").textContent = title;
      $("mText").textContent = text;
      $("mOk").textContent = okLabel;
      $("modal").classList.remove("hidden");
      $("mOk").focus();
      const done = (v) => { $("modal").classList.add("hidden"); $("mOk").onclick = $("mCancel").onclick = null; document.removeEventListener("keydown", esc); resolve(v); };
      const esc = (e) => { if (e.key === "Escape") done(false); };
      document.addEventListener("keydown", esc);
      $("mOk").onclick = () => done(true);
      $("mCancel").onclick = () => done(false);
    });
  }

  // ---- inloggen ----
  function showLogin(msg) {
    $("app").classList.add("hidden");
    $("login").classList.remove("hidden");
    const ready = !!(CFG.url && CFG.key);
    $("loginForm").classList.toggle("hidden", !ready);
    $("setup").classList.toggle("hidden", ready);
    $("loginErr").textContent = msg || "";
    if (ready) setTimeout(() => $("lu").focus(), 50);
  }
  function signOut(msg) {
    token = null; expires = 0;
    store.set("pasr.beheer.token", null); store.set("pasr.beheer.exp", null);
    showLogin(msg);
  }
  $("loginForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const user = $("lu").value.trim(), password = $("lp").value;
    if (!user || !password) { $("loginErr").textContent = "Vul je gebruikersnaam en wachtwoord in."; return; }
    $("loginBtn").disabled = true;
    $("loginErr").textContent = "";
    try {
      const r = await api("login", { user, password });
      token = r.token; expires = Date.parse(r.expires) || Date.now() + 12 * 3600e3;
      store.set("pasr.beheer.token", token); store.set("pasr.beheer.exp", String(expires));
      $("lp").value = "";
      start();
    } catch (err) {
      $("loginErr").textContent = err.message;
    } finally { $("loginBtn").disabled = false; }
  });

  // ---- tabs ----
  let tab = "overview";
  function setTab(t) {
    tab = t;
    document.querySelectorAll(".tabs button").forEach((b) => b.setAttribute("aria-selected", String(b.dataset.tab === t)));
    document.querySelectorAll(".view").forEach((v) => v.classList.toggle("hidden", v.id !== "view-" + t));
    if (t === "overview" || t === "insights") { skeleton(); if (stats) renderAll(); else loadStats(); }
    if (t === "accounts") loadUsers(true);
    if (t === "settings") showSettings();
    if (t === "stores") loadStores();
    if (t === "news") loadNews();
    if (t === "business") loadBusinesses();
    try { history.replaceState(null, "", "#" + t); } catch {}
  }
  document.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => setTab(b.dataset.tab)));

  // ---- statistieken (gedeeld door Overzicht en Insights) ----
  const METRICS = [
    { key: "accounts", label: "Accounts", detail: "totaal aan het eind van de dag", kind: "line", color: "#8A7FFF" },
    { key: "signups", label: "Nieuwe accounts", detail: "aangemaakt", kind: "bar", color: "#6A5CFF" },
    { key: "confirmed", label: "Bevestigd", detail: "e-mailadres bevestigd", kind: "bar", color: "#2ED3A6" },
    { key: "deleted", label: "Verwijderd", detail: "door de gebruiker zelf", kind: "bar", color: "#FF6B57" },
    { key: "cards", label: "Kaarten in accounts", detail: "totaal (elk uur gemeten)", kind: "line", color: "#FF8A78" },
    { key: "wallet", label: "Apple Wallet-passen", detail: "gemaakt", kind: "bar", color: "#4FB3FF" },
    { key: "gwallet", label: "Google Wallet-passen", detail: "gemaakt (Android)", kind: "bar", color: "#0E8A62" },
    { key: "pasr_ios", label: "Pasr actief op iOS", detail: "toestellen die de app openden", kind: "bar", color: "#8A7FFF" },
    { key: "pasr_android", label: "Pasr actief op Android", detail: "toestellen die de app openden", kind: "bar", color: "#2BB38A" },
    { key: "new_android", label: "Nieuwe Android-toestellen", detail: "installaties (Pasr + Zakelijk)", kind: "bar", color: "#0E8A62" },
    { key: "new_ios", label: "Nieuwe iOS-toestellen", detail: "installaties (Pasr + Zakelijk)", kind: "bar", color: "#6A5CFF" },
    { key: "zakelijk_android", label: "Pasr Zakelijk actief op Android", detail: "toestellen", kind: "bar", color: "#2ED3A6" },
    { key: "zakelijk_ios", label: "Pasr Zakelijk actief op iOS", detail: "toestellen", kind: "bar", color: "#C77DFF" },
    { key: "groups", label: "Gedeelde Pasrs", detail: "nieuw gemaakt", kind: "bar", color: "#2ED3A6" },
    { key: "temp_shares", label: "Tijdelijk gedeeld", detail: "kaarten tijdelijk gedeeld", kind: "bar", color: "#C77DFF" },
    { key: "store_requests", label: "Winkels aangevraagd", detail: "aanvragen uit de app", kind: "bar", color: "#FFB547" },
    { key: "bots", label: "Bots tegengehouden", detail: "aanmeldingen geweigerd", kind: "bar", color: "#FFB547" },
  ];
  const RANGES = [[7, "Week"], [30, "Maand"], [90, "Kwartaal"], [365, "Jaar"]];
  const saved = (() => { try { return JSON.parse(localStorage.getItem("pasr.beheer.insights") || "{}"); } catch { return {}; } })();
  let range = { days: RANGES.some(([d]) => d === saved.days) ? saved.days : 30, offset: 0 };
  let sources = Array.isArray(saved.sources) ? saved.sources.filter((k) => METRICS.some((m) => m.key === k)) : ["accounts", "signups", "wallet"];
  const remember = () => { try { localStorage.setItem("pasr.beheer.insights", JSON.stringify({ days: range.days, sources })); } catch {} };
  let stats = null, loading = null;

  async function loadStats() {
    const key = range.days + "|" + range.offset;
    if (loading === key) return;
    loading = key;
    $("ovErr").classList.add("hidden"); $("insErr").classList.add("hidden");
    try {
      const [s, p] = await Promise.all([api("stats", range), api("platforms", { days: range.days }).catch(() => null)]);
      if (loading !== key) return;
      // platformen (iOS/Android, Google Wallet) per dag erbij; alleen voor de huidige periode
      if (p && range.offset === 0) {
        const byDay = Object.fromEntries((p.series || []).map((d) => [d.day, d]));
        for (const d of s.per_day || []) {
          const x = byDay[d.day];
          if (x) for (const k of ["gwallet", "pasr_ios", "pasr_android", "new_android", "new_ios", "zakelijk_android", "zakelijk_ios"]) d[k] = x[k] ?? 0;
        }
      }
      s.platforms = p;
      stats = s;
      renderAll();
    } catch (err) {
      if (err.status === 401) return;
      for (const id of ["ovErr", "insErr"]) { $(id).textContent = err.message; $(id).classList.remove("hidden"); }
    } finally { if (loading === key) loading = null; }
  }
  function setRange(days, offset) {
    range = { days, offset: Math.max(0, offset) };
    remember();
    document.querySelectorAll(".panels").forEach((p) => p.classList.add("busy"));
    loadStats();
  }
  $("refresh").addEventListener("click", loadStats);

  function renderAll() {
    if (!stats) return;
    document.querySelectorAll(".panels").forEach((p) => p.classList.remove("busy"));
    renderKpis(stats);
    renderDists();
    renderControls();
    drawPanels($("ovPanels"), ["accounts", "signups"], true);
    drawPanels($("insPanels"), sources, false);
    renderSources();
    $("updated").textContent = "Bijgewerkt om " + new Date(stats.generated || Date.now()).toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" });
  }

  function kpi(label, value, sub, color) {
    const k = el("div", "kpi");
    k.style.setProperty("--accent", color);
    k.append(el("div", "l", label), el("div", "v", value));
    if (sub) { const s = el("div", "s"); s.append(...sub); k.append(s); }
    return k;
  }
  function renderKpis(s) {
    const t = s.totals || {};
    const box = $("kpis");
    box.replaceChildren();
    box.removeAttribute("aria-busy");
    const plus = (n, word) => [el("b", null, "+" + num(n)), document.createTextNode(" " + word)];
    const txt = (x) => [document.createTextNode(x)];
    box.append(
      kpi("Accounts", num(t.accounts), plus(t.new_7d, "deze week"), "#6A5CFF"),
      kpi("Bevestigd", num(t.confirmed), txt(`${num(t.unconfirmed)} wachten nog`), "#2ED3A6"),
      kpi("Kaarten in accounts", num(t.cards), txt(`${num(t.with_cards)} accounts met kaarten`), "#FF6B57"),
      kpi("Actief", num(t.active_30d), txt("ingelogd, 30 dagen"), "#8A7FFF"),
      kpi("Wallet-passen", num(s.wallet_total), txt(`Apple · ${num(s.platforms?.gwallet?.objects)} in Google Wallet`), "#4FB3FF"),
      kpi("Android", num(s.platforms?.apps?.pasr?.android?.active_30), txt(`actief, 30 dagen · iOS ${num(s.platforms?.apps?.pasr?.ios?.active_30)}`), "#2BB38A"),
      kpi("Push aan", num((s.platforms?.push?.ios || 0) + (s.platforms?.push?.android || 0)), txt(`iOS ${num(s.platforms?.push?.ios)} · Android ${num(s.platforms?.push?.android)}`), "#FF6B57"),
      kpi("Landen", num(Object.keys(s.countries || {}).filter((c) => c !== "?").length), txt("waar accounts vandaan komen"), "#FFB547"),
      kpi("Gedeelde Pasrs", num(s.shared?.groups), txt(`${num(s.shared?.people)} personen · ${num(s.shared?.cards)} kaarten`), "#2ED3A6"),
      kpi("Tijdelijk gedeeld", num(s.temp?.active), txt(`nu geldig · +${num(s.temp?.new_7d)} deze week`), "#C77DFF"),
    );
  }
  function skeleton() {
    const box = $("kpis");
    if (box.children.length) return;
    for (let i = 0; i < 10; i++) { const k = kpi("……", "000", null, "#262A37"); k.classList.add("skel"); box.append(k); }
  }

  const fmtDay = (d, opts) => new Date(d + "T00:00:00Z").toLocaleDateString("nl-NL", { timeZone: "UTC", ...opts });
  const periodText = () => {
    const r = stats?.range;
    return r?.from ? `${fmtDay(r.from, { day: "numeric", month: "short" })} – ${fmtDay(r.to, { day: "numeric", month: "short", year: "numeric" })}` : "";
  };
  function renderControls() {
    document.querySelectorAll("[data-period]").forEach((e) => { e.textContent = periodText(); });
    document.querySelectorAll("[data-range]").forEach((box) => {
      if (!box.children.length) {
        for (const [d, label] of RANGES) {
          const b = el("button", null, label);
          b.type = "button"; b.dataset.days = d;
          b.addEventListener("click", () => setRange(d, 0));
          box.append(b);
        }
      }
      box.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(Number(b.dataset.days) === range.days)));
    });
    document.querySelectorAll("[data-prev]").forEach((b) => { b.disabled = (range.offset + 1) * range.days > 1100; b.onclick = () => setRange(range.days, range.offset + 1); });
    document.querySelectorAll("[data-next]").forEach((b) => { b.disabled = range.offset === 0; b.onclick = () => setRange(range.days, range.offset - 1); });
  }
  document.querySelectorAll("[data-goto]").forEach((b) => b.addEventListener("click", () => setTab(b.dataset.goto)));

  // Reeks van de periode; bij een jaar per week (staven opgeteld, lijnen de laatste waarde van de week).
  function seriesRows() {
    const days = stats?.per_day || [];
    if (range.days !== 365) return { rows: days.map((d) => ({ ...d, label: d.day })), step: "dag" };
    const out = [];
    for (let i = 0; i < days.length; i += 7) {
      const chunk = days.slice(i, i + 7), w = { label: chunk[0].day, to: chunk[chunk.length - 1].day };
      for (const m of METRICS) {
        if (m.kind === "bar") w[m.key] = chunk.reduce((a, x) => a + (x[m.key] || 0), 0);
        else { const v = chunk.map((x) => x[m.key]).filter((x) => x != null); w[m.key] = v.length ? v[v.length - 1] : null; }
      }
      out.push(w);
    }
    return { rows: out, step: "week" };
  }

  function summary(rows, m) {
    const v = rows.map((r) => r[m.key]).filter((x) => x != null);
    if (!v.length) return null;
    const sum = v.reduce((a, b) => a + b, 0);
    const s = { Min: Math.min(...v), Max: Math.max(...v), "Gem.": sum / v.length, Laatste: v[v.length - 1] };
    if (m.kind === "bar") s.Totaal = sum;
    return s;
  }
  function niceScale(max, ticks = 4) {
    if (max <= 0) return { top: 4, step: 1 };
    let best = null;
    for (let e = 1; e <= max * 10; e *= 10) {
      for (const k of [1, 2, 2.5, 5]) {
        const step = k * e;
        if (step !== Math.round(step)) continue;
        const n = Math.max(1, Math.ceil(max / step));
        if (n > ticks || (n < 2 && max > 1)) continue;
        const top = n * step;
        if (!best || top < best.top || (top === best.top && step > best.step)) best = { top, step };
      }
    }
    return best || { top: Math.ceil(max), step: Math.ceil(max) };
  }
  // vloeiende lijn zonder doorschieten (monotone cubic)
  function smoothPath(pts) {
    if (pts.length < 2) return pts.length ? `M${pts[0][0]},${pts[0][1]}` : "";
    const n = pts.length, dx = [], dy = [], m = [], t = [];
    for (let i = 0; i < n - 1; i++) { dx[i] = pts[i + 1][0] - pts[i][0]; dy[i] = pts[i + 1][1] - pts[i][1]; m[i] = dy[i] / dx[i]; }
    t[0] = m[0]; t[n - 1] = m[n - 2];
    for (let i = 1; i < n - 1; i++) t[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2;
    let d = `M${pts[0][0]},${pts[0][1]}`;
    for (let i = 0; i < n - 1; i++) {
      const h = dx[i] / 3;
      d += ` C${pts[i][0] + h},${pts[i][1] + t[i] * h} ${pts[i + 1][0] - h},${pts[i + 1][1] - t[i + 1] * h} ${pts[i + 1][0]},${pts[i + 1][1]}`;
    }
    return d;
  }

  // Grafiekkaarten onder elkaar met één gedeelde kruisdraad (zoals Homey Insights).
  function drawPanels(root, keys, compact) {
    root.replaceChildren();
    if (!stats) return;
    const { rows, step } = seriesRows();
    const list = METRICS.filter((m) => keys.includes(m.key));
    if (!list.length) { root.append(el("p", "acc-empty", "Kies links één of meer bronnen.")); return; }
    const panels = [];
    const highlight = (i) => panels.forEach((p) => p.show(i));
    const clear = () => panels.forEach((p) => p.hide());
    for (const m of list) panels.push(panel(root, rows, m, step, compact, highlight, clear));
  }

  function panel(root, rows, m, step, compact, highlight, clear) {
    const box = el("section", compact ? "panel" : "panel card");
    const head = el("div", "panel-h"), title = el("div", "panel-t"), sw = el("i", "sw " + m.kind);
    sw.style.setProperty("--c", m.color);
    title.append(sw, el("strong", null, m.label), el("span", "muted sm", " · " + m.detail + (step === "week" ? ", per week" : "")));
    head.append(title);
    const sums = summary(rows, m);
    const sumBox = el("div", "panel-sum");
    if (sums) for (const [k, v] of Object.entries(sums)) {
      const c = el("div"); c.append(el("small", null, k.toUpperCase()), el("b", null, k === "Gem." ? (Math.round(v * 10) / 10).toLocaleString("nl-NL") : num(v)));
      sumBox.append(c);
    }
    head.append(sumBox);
    const plot = el("div", "plot"), tip = el("div", "tip hidden");
    plot.append(tip);
    box.append(head, plot);
    root.append(box);

    const W = plot.clientWidth || 800, H = compact ? 150 : 190, L = 40, B = 22, T = 10;
    plot.style.height = H + "px";
    const vals = rows.map((r) => r[m.key]);
    const sc = niceScale(Math.max(0, ...vals.filter((v) => v != null)) * 1.05);
    const n = rows.length, cw = (W - L) / Math.max(n, 1);
    const x = (i) => L + i * cw + cw / 2, y = (v) => T + (H - T - B) * (1 - v / sc.top);
    const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": m.label });
    const grid = svgEl("g", { class: "grid" });
    for (let v = 0; v <= sc.top + 1e-9; v += sc.step) {
      grid.append(svgEl("line", { x1: L, x2: W, y1: y(v), y2: y(v), class: v === 0 ? "base" : "" }));
      const t = svgEl("text", { x: L - 8, y: y(v) + 4, "text-anchor": "end" }); t.textContent = num(v); grid.append(t);
    }
    svg.append(grid);
    const defs = svgEl("defs", {}), gid = "g" + Math.random().toString(36).slice(2);
    const lg = svgEl("linearGradient", { id: gid, x1: 0, x2: 0, y1: 0, y2: 1 });
    lg.append(svgEl("stop", { offset: "0", "stop-color": m.color, "stop-opacity": ".32" }), svgEl("stop", { offset: "1", "stop-color": m.color, "stop-opacity": "0" }));
    defs.append(lg); svg.append(defs);
    const bars = [];
    if (m.kind === "bar") {
      const bw = Math.max(1.5, Math.min(26, cw * (n > 120 ? 0.85 : 0.64)));
      rows.forEach((r, i) => {
        const v = r[m.key] || 0;
        const h = Math.max(v ? 2 : 0, (H - T - B) * (v / sc.top));
        const rect = svgEl("rect", { class: "bar", x: x(i) - bw / 2, y: H - B - h, width: bw, height: h, rx: Math.min(3, bw / 3), fill: m.color });
        bars.push(rect); svg.append(rect);
      });
    } else {
      // lijn met vlak eronder; ontbrekende dagen (nog niet gemeten) breken de lijn
      let seg = [];
      const flush = () => {
        if (seg.length) {
          const d = smoothPath(seg);
          svg.append(svgEl("path", { d: `${d} L${seg[seg.length - 1][0]},${H - B} L${seg[0][0]},${H - B} Z`, fill: `url(#${gid})` }));
          svg.append(svgEl("path", { d, class: "line", stroke: m.color }));
        }
        seg = [];
      };
      rows.forEach((r, i) => { const v = r[m.key]; if (v == null) flush(); else seg.push([x(i), y(v)]); });
      flush();
      if (vals.every((v) => v == null)) {
        const t = svgEl("text", { x: (W + L) / 2, y: H / 2, "text-anchor": "middle", class: "empty" });
        t.textContent = "Nog geen metingen in deze periode"; svg.append(t);
      }
    }
    const axis = svgEl("g", { class: "axis" });
    const every = Math.ceil(n / Math.max(1, Math.floor((W - L) / 70)));
    rows.forEach((r, i) => {
      if ((n - 1 - i) % every) return;
      const t = svgEl("text", { x: x(i), y: H - 5, "text-anchor": "middle" });
      t.textContent = range.days === 365 ? fmtDay(r.label, { month: "short" }) : fmtDay(r.label, range.days === 7 ? { weekday: "short", day: "numeric" } : { day: "numeric", month: "short" });
      axis.append(t);
    });
    svg.append(axis);
    const rule = svgEl("line", { class: "rule", y1: T, y2: H - B, x1: 0, x2: 0, visibility: "hidden" });
    const dot = svgEl("circle", { class: "dot", r: 5, cx: 0, cy: 0, fill: m.color, visibility: "hidden" });
    svg.append(rule, dot);
    plot.prepend(svg);

    const idx = (clientX) => {
      const b = plot.getBoundingClientRect();
      return Math.min(n - 1, Math.max(0, Math.floor(((clientX - b.left) * (W / b.width) - L) / cw)));
    };
    plot.addEventListener("pointermove", (e) => highlight(idx(e.clientX)));
    plot.addEventListener("pointerdown", (e) => highlight(idx(e.clientX)));
    plot.addEventListener("pointerleave", (e) => { if (e.pointerType === "mouse") clear(); });
    return {
      show(i) {
        const r = rows[i]; if (!r) return;
        rule.setAttribute("x1", x(i)); rule.setAttribute("x2", x(i)); rule.setAttribute("visibility", "visible");
        const v = r[m.key];
        if (m.kind === "line" && v != null) { dot.setAttribute("cx", x(i)); dot.setAttribute("cy", y(v)); dot.setAttribute("visibility", "visible"); }
        else dot.setAttribute("visibility", "hidden");
        bars.forEach((b, j) => b.classList.toggle("dim", j !== i));
        tip.replaceChildren(el("b", null, r.to ? `Week van ${fmtDay(r.label, { day: "numeric", month: "short" })}` : fmtDay(r.label, { weekday: "short", day: "numeric", month: "long" })),
          el("span", null, v == null ? "geen meting" : num(v)));
        tip.classList.remove("hidden");
        const b = plot.getBoundingClientRect(), px = x(i) * (b.width / W);
        tip.style.left = Math.min(Math.max(px - 70, 0), b.width - 140) + "px";
      },
      hide() { rule.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden"); bars.forEach((b) => b.classList.remove("dim")); tip.classList.add("hidden"); },
    };
  }

  function renderSources() {
    const box = $("insSources");
    box.replaceChildren();
    for (const m of METRICS) {
      const lab = el("label", "source"), cb = el("input"), sw = el("i", "sw " + m.kind), txt = el("span");
      cb.type = "checkbox"; cb.checked = sources.includes(m.key);
      cb.addEventListener("change", () => {
        sources = METRICS.map((x) => x.key).filter((k) => (k === m.key ? cb.checked : sources.includes(k)));
        remember();
        drawPanels($("insPanels"), sources, false);
      });
      sw.style.setProperty("--c", m.color);
      txt.append(el("strong", null, m.label), el("small", null, m.detail));
      lab.append(cb, sw, txt);
      box.append(lab);
    }
  }
  $("insCsv").addEventListener("click", () => {
    if (!stats) return;
    const list = METRICS.filter((m) => sources.includes(m.key));
    const lines = [["dag", ...list.map((m) => m.label)].join(";")];
    for (const d of stats.per_day || []) lines.push([d.day, ...list.map((m) => d[m.key] ?? "")].join(";"));
    const a = el("a");
    a.href = URL.createObjectURL(new Blob(["﻿" + lines.join("\n")], { type: "text/csv;charset=utf-8" }));
    a.download = `pasr-insights-${stats.range.from}-${stats.range.to}.csv`;
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  });
  let resizeTimer;
  window.addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(renderAll, 150); });

  // ---- verdelingen ----
  const REASONS = { honeypot: "Honeypot ingevuld", too_fast: "Te snel ingevuld", rate_limit: "Te veel vanaf één netwerk", disposable: "Wegwerpadres", other: "Overig" };
  const flag = (cc) => (/^[A-Z]{2}$/.test(cc) ? String.fromCodePoint(...[...cc].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65)) : "🌐");
  const countryName = (cc) => { if (cc === "?") return "Onbekend"; try { return new Intl.DisplayNames(["nl"], { type: "region" }).of(cc) || cc; } catch { return cc; } };
  function dist(box, entries, color, emptyText) {
    box.replaceChildren();
    const total = entries.reduce((a, [, n]) => a + n, 0);
    if (!total) { box.append(el("p", "empty", emptyText)); return; }
    const max = Math.max(...entries.map(([, n]) => n));
    for (const [label, n] of entries) {
      const row = el("div", "row"), bar = el("div", "bar"), fill = el("i");
      fill.style.setProperty("--c", color);
      bar.append(fill);
      row.append(el("span", null, label), el("span", "n", `${num(n)} · ${Math.round((n / total) * 100)}%`), bar);
      box.append(row);
      requestAnimationFrame(() => { fill.style.width = (n / max) * 100 + "%"; });
    }
  }
  // losse aantallen onder elkaar (geen percentages: het zijn verschillende dingen)
  function facts(box, entries, emptyText) {
    box.replaceChildren();
    if (!entries.some(([, n]) => n > 0)) { box.append(el("p", "empty", emptyText)); return; }
    for (const [label, n] of entries) {
      const row = el("div", "row fact");
      row.append(el("span", null, label), el("span", "n", typeof n === "string" ? n : num(n)));
      box.append(row);
    }
  }
  function renderDists() {
    const b = stats.bots_7d || {};
    dist($("bots"), Object.entries(b).sort((x, y) => y[1] - x[1]).map(([k, n]) => [REASONS[k] || k, n]), "#FFB547",
      `Geen bots deze week. ${num(stats.signups_allowed_7d)} gewone aanmeldingen.`);
    const order = ["0", "1-5", "6-15", "16-30", "31+"], c = stats.cards_per_account || {};
    dist($("perAccount"), order.filter((k) => c[k]).map((k) => [k === "0" ? "Nog geen kaarten" : `${k} kaarten`, c[k]]), "#6A5CFF", "Nog geen accounts.");
    const co = Object.entries(stats.countries || {}).sort((x, y) => (x[0] === "?") - (y[0] === "?") || y[1] - x[1]);
    dist($("countries"), co.slice(0, 12).map(([k, n]) => [`${flag(k)}  ${countryName(k)}`, n]), "#2ED3A6", "Nog geen accounts.");
    const pl = stats.platforms;
    const APPS = [["pasr", "Pasr"], ["zakelijk", "Pasr Zakelijk"]], OS = [["ios", "iOS"], ["android", "Android"]];
    dist($("platforms"), pl ? APPS.flatMap(([a, an]) => OS.map(([o, on]) => [`${an} · ${on}`, pl.apps?.[a]?.[o]?.active_30 || 0])) : [],
      "#2BB38A", pl ? "Nog geen toestellen gemeld (vanaf Pasr voor Android en nieuwe iOS-versies)." : "Niet beschikbaar: draai de workflow Backend.");
    const acc = pl?.accounts || {};
    facts($("platformFacts"), pl ? [
      ["Accounts aangemaakt op iOS", acc.ios || 0], ["Accounts aangemaakt op Android", acc.android || 0],
      ["Accounts aangemaakt op het web", acc.web || 0], ["Accounts van voor de platformtelling", acc.other || 0],
      ["Toestellen Pasr (iOS / Android)", `${num(pl.apps?.pasr?.ios?.devices)} / ${num(pl.apps?.pasr?.android?.devices)}`],
      ["Nieuwe installaties in de periode (iOS / Android)", `${num(pl.apps?.pasr?.ios?.new_period)} / ${num(pl.apps?.pasr?.android?.new_period)}`],
      ["Ingelogd op Android", pl.apps?.pasr?.android?.signed_in || 0],
      ["Google Wallet-passen (bijgewerkt in 30 dagen)", `${num(pl.gwallet?.objects)} (${num(pl.gwallet?.updated_30)})`],
      ["Google Wallet", pl.gwallet_ready ? "ingericht" : "nog niet ingericht (secrets ontbreken)"],
      ["Push aan: Pasr iOS / Android", `${num(pl.push?.ios)} / ${num(pl.push?.android)}`],
      ["Nieuws over mijn kaarten aan: iOS / Android", `${num(pl.push?.ios_news)} / ${num(pl.push?.android_news)}`],
      ["Push aan: Pasr Zakelijk Android", pl.push?.zakelijk_android || 0],
      ["Android-push (FCM)", pl.fcm_ready ? "ingericht" : "nog niet ingericht (FIREBASE_SERVICE_ACCOUNT_JSON)"],
    ] : [], "Nog geen gegevens.");
    const vers = (pl?.versions || []).slice().sort((x, y) => (y.active_30 || 0) - (x.active_30 || 0)).slice(0, 10);
    dist($("versions"), vers.map((v) => [`${v.app === "zakelijk" ? "Zakelijk" : "Pasr"} ${v.platform === "android" ? "Android" : "iOS"} ${v.version}${v.build ? ` (${v.build})` : ""}`, v.active_30 || v.devices || 0]),
      "#8A7FFF", "Nog geen versies gemeld.");
    const sh = stats.shared || {}, tp = stats.temp || {};
    facts($("sharing"), [
      ["Gedeelde Pasrs", sh.groups || 0], ["Personen in een gedeelde Pasr", sh.people || 0],
      ["Gedeelde kaarten", sh.cards || 0], ["Openstaande uitnodigingen", sh.invites || 0],
      ["Tijdelijk gedeeld, nu geldig", tp.active || 0], ["Tijdelijk: keren geopend (30 dagen)", tp.opens || 0],
      ["Tijdelijk: eerder gestopt (30 dagen)", tp.revoked_30d || 0],
      ["Winkelaanvragen open", stats.stores?.requests_open || 0], ["Winkels toegevoegd zonder update", stats.stores?.added || 0],
      ["Toestellen met pushmeldingen", stats.stores?.push_devices || 0], ["Waarvan 'Nieuwe winkels' aan", stats.stores?.new_store_push || 0],
    ], "Nog niets gedeeld.");
  }

  // ---- accounts ----
  let acc = { search: "", filter: "all", offset: 0, total: 0 }, searchTimer;
  const ago = (iso) => {
    if (!iso) return "nooit";
    const s = (Date.now() - Date.parse(iso)) / 1000;
    if (s < 60) return "zojuist";
    if (s < 3600) return `${Math.floor(s / 60)} min geleden`;
    if (s < 86400) return `${Math.floor(s / 3600)} uur geleden`;
    if (s < 86400 * 30) return `${Math.floor(s / 86400)} ${Math.floor(s / 86400) === 1 ? "dag" : "dagen"} geleden`;
    return new Date(iso).toLocaleDateString("nl-NL", { day: "numeric", month: "short", year: "numeric" });
  };
  async function loadUsers(reset) {
    if (reset) acc.offset = 0;
    document.querySelectorAll("#accFilter button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.filter === acc.filter)));
    $("accErr").classList.add("hidden");
    try {
      const r = await api("users", { search: acc.search, filter: acc.filter, limit: 50, offset: acc.offset });
      acc.total = r.total || 0;
      const list = $("accList");
      list.removeAttribute("aria-busy");
      if (reset) list.replaceChildren();
      for (const u of r.users || []) list.append(userRow(u));
      if (!acc.total) list.replaceChildren(el("p", "acc-empty", acc.search ? "Geen accounts gevonden." : "Nog geen accounts."));
      acc.offset += (r.users || []).length;
      $("accMore").classList.toggle("hidden", acc.offset >= acc.total);
      $("accCount").textContent = `${num(acc.total)} ${acc.total === 1 ? "account" : "accounts"}`;
    } catch (err) {
      if (err.status === 401) return;
      $("accErr").textContent = err.message;
      $("accErr").classList.remove("hidden");
    }
  }
  function userRow(u) {
    const row = el("div", "acc");
    const initial = (u.first_name || u.email || "?").trim().charAt(0).toUpperCase();
    const who = el("div", "who"), meta = el("div", "meta");
    who.append(el("div", "mail", u.email || "—"));
    const badge = el("span", "badge " + (u.email_confirmed_at ? "ok" : "wait"), u.email_confirmed_at ? "Bevestigd" : "Onbevestigd");
    meta.append(badge);
    if (u.first_name) meta.append(el("span", null, u.first_name));
    if (u.country) meta.append(el("span", null, `${flag(u.country)} ${countryName(u.country)}`));
    if (u.groups) meta.append(el("span", null, `${num(u.groups)} gedeelde ${u.groups === 1 ? "Pasr" : "Pasrs"}`));
    meta.append(el("span", null, `${num(u.cards)} ${u.cards === 1 ? "kaart" : "kaarten"}`),
      el("span", null, "Aangemaakt " + ago(u.created_at)), el("span", null, "Ingelogd " + ago(u.last_sign_in_at)));
    if (u.synced_at) meta.append(el("span", null, "Sync " + ago(u.synced_at)));
    who.append(meta);
    const acts = el("div", "acts");
    if (!u.email_confirmed_at) {
      const re = el("button", "btn ghost sm", "Mail opnieuw");
      re.type = "button";
      re.addEventListener("click", async () => {
        re.disabled = true;
        try { await api("user_resend", { id: u.id }); toast("Bevestigingsmail verstuurd naar " + u.email); }
        catch (err) { toast(err.message); }
        finally { re.disabled = false; }
      });
      const cf = el("button", "btn ghost sm", "E-mail bevestigen");
      cf.type = "button";
      cf.addEventListener("click", async () => {
        if (!(await ask("E-mailadres bevestigen?", `${u.email} wordt als bevestigd gemarkeerd, zonder bevestigingsmail. Doe dit alleen als je zeker weet dat dit adres klopt (bijvoorbeeld een review-account). Het wachtwoord blijft van de gebruiker.`, "Bevestigen"))) return;
        cf.disabled = true;
        try { await api("user_confirm", { id: u.id }); toast(`${u.email} is bevestigd`); loadUsers(true); }
        catch (err) { toast(err.message); cf.disabled = false; }
      });
      acts.append(re, cf);
    }
    const del = el("button", "btn danger sm", "Verwijder");
    del.type = "button";
    del.addEventListener("click", async () => {
      const ok = await ask("Account verwijderen?", `${u.email} en de ${num(u.cards)} kaarten in dit account worden van de server verwijderd. De kaarten op de apparaten van deze persoon blijven staan. Dit kan niet ongedaan worden.`, "Verwijder");
      if (!ok) return;
      try { await api("user_delete", { id: u.id }); row.remove(); acc.total--; $("accCount").textContent = `${num(acc.total)} accounts`; toast("Account verwijderd"); }
      catch (err) { toast(err.message); }
    });
    acts.append(del);
    const av = el("div", "avatar", initial);
    row.append(av, who, acts);
    return row;
  }
  $("accSearch").addEventListener("input", (e) => { clearTimeout(searchTimer); searchTimer = setTimeout(() => { acc.search = e.target.value.trim(); loadUsers(true); }, 250); });
  document.querySelectorAll("#accFilter button").forEach((b) => b.addEventListener("click", () => { acc.filter = b.dataset.filter; loadUsers(true); }));
  $("accMore").addEventListener("click", () => loadUsers(false));

  // ---- Review-account voor Apple ----
  $("revOpen").addEventListener("click", () => { $("revCard").classList.remove("hidden"); $("revPass").focus(); });
  $("revClose").addEventListener("click", () => { $("revCard").classList.add("hidden"); $("revPass").value = ""; $("revMsg").textContent = ""; });
  $("revShow").addEventListener("click", () => {
    const p = $("revPass"); p.type = p.type === "password" ? "text" : "password";
    $("revShow").textContent = p.type === "password" ? "Toon" : "Verberg";
  });
  $("revGen").addEventListener("click", () => {
    // 16 tekens zonder verwarrende tekens, altijd met hoofdletter, kleine letter en cijfer
    const sets = ["ABCDEFGHJKLMNPQRSTUVWXYZ", "abcdefghijkmnpqrstuvwxyz", "23456789"];
    const all = sets.join(""), r = new Uint32Array(16);
    crypto.getRandomValues(r);
    const chars = [...r].map((x, i) => (i < 3 ? sets[i] : all)[x % (i < 3 ? sets[i] : all).length]);
    for (let i = chars.length - 1; i > 0; i--) { const k = r[i] % (i + 1); [chars[i], chars[k]] = [chars[k], chars[i]]; }
    $("revPass").value = chars.join(""); $("revPass").type = "text"; $("revShow").textContent = "Verberg";
  });
  $("revCopy").addEventListener("click", async () => {
    try { await navigator.clipboard.writeText($("revPass").value); toast("Wachtwoord gekopieerd"); } catch { toast("Kopiëren lukt niet in deze browser"); }
  });
  $("revForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const msg = $("revMsg"); msg.className = "err"; msg.textContent = "";
    const btn = $("revGo"); btn.disabled = true;
    try {
      const r = await api("review_account", { email: $("revEmail").value, password: $("revPass").value,
        first_name: $("revName").value, reset: $("revReset").checked });
      msg.className = "err ok";
      msg.textContent = `${r.created ? "Account gemaakt" : "Wachtwoord vervangen"}: ${r.email}, met ${r.cards} kaarten en een gedeelde Pasr met ${r.group_cards} kaarten. Zet e-mail en wachtwoord nu in App Store Connect.`;
      loadUsers(true);
    } catch (err) { msg.textContent = err.message; }
    finally { btn.disabled = false; }
  });

  // ---- instellingen ----
  function showSettings() {
    $("sessionInfo").textContent = expires ? `Ingelogd tot ${new Date(expires).toLocaleString("nl-NL", { weekday: "short", hour: "2-digit", minute: "2-digit" })}.` : "";
    if (stats) {
      $("pushInfo").textContent = stats.push_ready
        ? `Klaar. ${num(stats.push_devices)} ${stats.push_devices === 1 ? "apparaat is" : "apparaten zijn"} aangemeld.`
        : "Nog niet ingericht: zet de APNs-sleutel als secrets PASR_APNS_KEY_P8 en PASR_APNS_KEY_ID en draai de workflow Backend.";
    }
  }
  $("logout").addEventListener("click", () => signOut());
  $("logoutAll").addEventListener("click", async () => {
    if (!(await ask("Overal uitloggen?", "Alle sessies vervallen, ook in de app PasrBeheer op je andere apparaten. Daar moet je opnieuw inloggen en pushmeldingen opnieuw aanzetten.", "Overal uitloggen"))) return;
    try { await api("logout_all"); signOut("Je bent overal uitgelogd."); }
    catch (err) { $("setMsg").textContent = err.message; }
  });

  // ---- winkels: aanvragen, kaart maken, publiceren ----
  const CATEGORIES = ["Supermarkt", "Drogist en beauty", "Warenhuis en wonen", "Mode en schoenen", "Elektronica", "Doe-het-zelf en tuin",
    "Sport en vrije tijd", "Tanken en reizen", "Eten en drinken", "Boeken en cadeaus", "Dieren", "Cadeaukaarten", "Overig"];
  const FORMATS = [["ean13", "EAN-13"], ["ean8", "EAN-8"], ["upcA", "UPC-A"], ["code128", "Code 128"], ["code39", "Code 39"], ["itf", "ITF"], ["qr", "QR"], ["pdf417", "PDF417"], ["aztec", "Aztec"]];
  let storeFilter = "open", editing = null;
  CATEGORIES.forEach((c) => $("seCategory").append(Object.assign(el("option", null, c), { value: c })));
  FORMATS.forEach(([v, l]) => $("seFormat").append(Object.assign(el("option", null, l), { value: v })));
  function badge(n) { const b = $("reqBadge"); b.textContent = n; b.classList.toggle("hidden", !n); }
  document.querySelectorAll("#reqFilter button").forEach((b) => b.addEventListener("click", () => { storeFilter = b.dataset.status; loadStores(); }));

  // Zoeken in de lijst: naam, id, website, categorie en andere namen; zonder hoofdletters en accenten.
  const fold = (t) => String(t || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  function applySearch() {
    const q = fold($("storeSearch").value.trim());
    const rows = [...$("reqList").querySelectorAll("[data-search]")];
    let shown = 0;
    for (const r of rows) { const hit = !q || r.dataset.search.includes(q); r.classList.toggle("hidden", !hit); if (hit) shown++; }
    const t = $("storeTally");
    if (storeFilter === "stores" && rows.length) {
      const vis = rows.filter((r) => !r.classList.contains("hidden"));
      const v = vis.filter((r) => r.dataset.kind === "voucher").length;
      t.textContent = `${vis.length - v} klantenkaarten en ${v} cadeaukaarten` + (q ? ` gevonden (van ${rows.length})` : "");
      t.classList.remove("hidden");
    } else if (q && rows.length) { t.textContent = `${shown} van ${rows.length} gevonden`; t.classList.remove("hidden"); }
    else t.classList.add("hidden");
  }
  $("storeSearch").addEventListener("input", applySearch);

  async function loadStores() {
    document.querySelectorAll("#reqFilter button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.status === storeFilter)));
    const list = $("reqList");
    list.setAttribute("aria-busy", "true");
    $("storeErr").classList.add("hidden");
    try {
      list.replaceChildren();
      $("bpForm").classList.toggle("hidden", storeFilter !== "balance");
      if (storeFilter === "balance") {
        await loadBuiltin();
        const r = await api("balance_pages");
        const pages = new Map((r.pages || []).map((p) => [p.store_id, p.url]));
        // alle cadeaukaarten en vouchers (ingevulde eerst onderaan per groep), daarna andere winkels met een adres
        const vouchers = (builtin || []).filter((s) => s.voucher);
        const todo = vouchers.filter((s) => !pages.has(s.id)).length;
        list.append(el("p", "muted sm", todo ? `${todo} van ${vouchers.length} cadeaukaarten hebben nog geen saldo-pagina.` : "Alle cadeaukaarten hebben een saldo-pagina."));
        for (const s of vouchers) list.append(balanceRow({ store_id: s.id, url: pages.get(s.id) || "" }));
        for (const [id, url] of pages) if (!vouchers.some((s) => s.id === id)) list.append(balanceRow({ store_id: id, url }));
      } else if (storeFilter === "stores") {
        const r = await api("stores");
        if (!(r.stores || []).length) list.append(el("p", "empty", "Nog geen winkels toegevoegd via het beheer."));
        for (const s of r.stores || []) list.append(storeRow(s));
      } else {
        const r = await api("store_requests", { status: storeFilter });
        if (storeFilter === "open") badge((r.groups || []).length);
        if (!(r.groups || []).length) list.append(el("p", "empty", storeFilter === "open" ? "Geen open aanvragen. Mooi zo." : "Niets afgewezen."));
        for (const g of r.groups || []) list.append(requestRow(g));
      }
    } catch (err) {
      if (err.status === 401) return;
      $("storeErr").textContent = err.message; $("storeErr").classList.remove("hidden");
    } finally { list.removeAttribute("aria-busy"); applySearch(); }
  }

  // ---- Saldo-pagina's ----
  let builtin = null;
  async function loadBuiltin() {
    if (builtin) return;
    try { builtin = await (await fetch("stores-builtin.json", { cache: "no-cache" })).json(); } catch { builtin = []; }
    let remote = [];
    try { remote = ((await api("stores")).stores || []).map((s) => ({ id: s.id, name: s.name, voucher: s.kind === "voucher" })); } catch {}
    builtin = [...builtin, ...remote.filter((r) => !builtin.some((b) => b.id === r.id))]
      .sort((a, b) => Number(b.voucher) - Number(a.voucher) || a.name.localeCompare(b.name, "nl"));
    const dl = $("bpStores");
    dl.replaceChildren(...builtin.map((s) => { const o = document.createElement("option"); o.value = s.id; o.label = s.name + (s.voucher ? " (cadeaukaart)" : ""); return o; }));
  }
  const storeName = (id) => (builtin || []).find((s) => s.id === id)?.name || id;
  function resolveStore(text) {
    const t = text.trim().toLowerCase();
    const hit = (builtin || []).find((s) => s.id === t || s.name.toLowerCase() === t);
    return hit ? hit.id : t;
  }
  function balanceRow(p) {
    const row = el("form", "acc bp-row");
    row.noValidate = true;
    row.dataset.search = fold([storeName(p.store_id), p.store_id, p.url].join(" "));
    const who = el("div", "who");
    who.append(el("div", "mail", storeName(p.store_id)));
    const input = document.createElement("input");
    input.type = "text"; input.inputMode = "url"; input.placeholder = "https://… (saldo-pagina)"; input.value = p.url; input.spellcheck = false;
    input.setAttribute("aria-label", `Saldo-pagina ${storeName(p.store_id)}`);
    who.append(input);
    const btns = el("div", "row-btns");
    const find = document.createElement("a");
    find.className = "btn ghost sm"; find.textContent = "Zoek"; find.target = "_blank"; find.rel = "noopener";
    find.href = "https://www.google.com/search?q=" + encodeURIComponent(storeName(p.store_id) + " saldo checken");
    const save = el("button", "btn sm", "Opslaan"); save.type = "submit";
    btns.append(find, save);
    if (p.url) {
      const del = el("button", "btn danger sm", "Wis"); del.type = "button";
      del.onclick = async () => {
        if (!(await ask("Saldo-pagina wissen?", `${storeName(p.store_id)}: ${p.url}`, "Wis"))) return;
        try { await api("balance_page_delete", { store_id: p.store_id }); input.value = ""; p.url = ""; del.remove(); row.classList.remove("done"); toast("Gewist"); } catch (e) { toast(e.message); }
      };
      btns.append(del);
      row.classList.add("done");
    }
    row.addEventListener("submit", async (e) => {
      e.preventDefault();
      let url = input.value.trim();
      if (!url) return;
      if (!/^https?:\/\//i.test(url)) url = "https://" + url;
      save.disabled = true;
      try { const r = await api("balance_page_save", { store_id: p.store_id, url }); input.value = r.url; row.classList.add("done"); toast(`${storeName(p.store_id)} opgeslagen`); }
      catch (err) { toast(err.message); }
      finally { save.disabled = false; }
    });
    row.append(el("div", "av", p.url ? "✓" : "€"), who, btns);
    return row;
  }
  $("bpForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const msg = $("bpMsg"); msg.textContent = "";
    let url = $("bpUrl").value.trim();
    if (url && !/^https?:\/\//i.test(url)) url = "https://" + url;
    try {
      const r = await api("balance_page_save", { store_id: resolveStore($("bpStore").value), url });
      toast(`Saldo-pagina voor ${storeName(r.store_id)} opgeslagen`);
      $("bpStore").value = ""; $("bpUrl").value = "";
      loadStores();
    } catch (err) { msg.textContent = err.message; }
  });

  function requestRow(g) {
    const row = el("div", "acc req");
    row.dataset.search = fold([g.name, g.website].join(" "));
    const av = el("div", "av", String(g.count));
    av.title = g.count === 1 ? "1 aanvraag" : `${g.count} aanvragen`;
    const who = el("div", "who"), meta = el("div", "meta");
    who.append(el("div", "mail", g.name));
    if (g.kind === "voucher") meta.append(el("span", "badge wait", "Cadeaukaart / voucher"));
    if (g.website) meta.append(el("span", null, g.website));
    meta.append(el("span", null, g.count === 1 ? "1 aanvraag" : `${num(g.count)} aanvragen`), el("span", null, "Laatste " + ago(g.last)));
    who.append(meta);
    if (g.notes.length) who.append(el("div", "note", "“" + g.notes.slice(0, 2).join("” · “") + "”"));
    const acts = el("div", "acts");
    if (storeFilter === "open") {
      const make = el("button", "btn sm", "Kaart maken");
      make.addEventListener("click", () => openEditor({ name: g.name, domain: g.website || "", kind: g.kind,
        category: g.kind === "voucher" ? "Cadeaukaarten" : undefined, format: g.kind === "voucher" ? "code128" : undefined }, g.ids, true));
      acts.append(make);
    }
    row.append(av, who, acts);
    return row;
  }

  function storeRow(s) {
    const row = el("div", "acc");
    row.dataset.search = fold([s.name, s.id, s.domain, s.category, ...(s.aliases || [])].join(" "));
    row.dataset.kind = s.kind === "voucher" ? "voucher" : "loyalty";
    const voucherCover = s.kind === "voucher" && s.cover;
    const av = el("div", voucherCover ? "av cover" : "av logo");
    av.style.background = s.card_hex;
    if (voucherCover) {
      const img = el("img"); img.loading = "lazy"; img.decoding = "async"; img.alt = "";
      img.src = (s.cover.startsWith("/9j/") ? "data:image/jpeg;base64," : "data:image/png;base64,") + s.cover; av.append(img);
    } else if (s.logo) { const img = el("img"); img.loading = "lazy"; img.decoding = "async"; img.src = "data:image/png;base64," + s.logo; img.alt = ""; av.append(img); }
    else av.textContent = s.name.charAt(0);
    const who = el("div", "who"), meta = el("div", "meta");
    who.append(el("div", "mail", s.name));
    meta.append(el("span", "badge " + (s.published ? "ok" : "wait"), s.published ? "Gepubliceerd" : "Concept"));
    if (s.domain) meta.append(el("span", null, s.domain));
    meta.append(el("span", null, s.category), el("span", null, "Gewijzigd " + ago(s.updated_at)));
    who.append(meta);
    const acts = el("div", "acts");
    const edit = el("button", "btn ghost sm", "Wijzig");
    edit.addEventListener("click", () => openEditor(s, [], false));
    acts.append(edit);
    row.append(av, who, acts);
    return row;
  }

  function openEditor(s, requestIds, fromRequest) {
    editing = { id: s.id || null, requestIds, logo: s.logo || null, cover: s.cover || null, coverChanged: false, published: !!s.published };
    $("seTitle").textContent = s.id ? s.name : (fromRequest ? "Kaart maken voor aanvraag" : "Nieuwe winkel");
    $("seDomain").value = s.domain || "";
    $("seName").value = s.name || "";
    $("seCategory").value = s.category || "Overig";
    $("seFormat").value = s.format || "ean13";
    $("seKind").value = s.kind || "loyalty";
    $("seColor").value = s.card_hex || "#2B2F3A";
    $("seAliases").value = (s.aliases || []).join(", ");
    const g = s.guide || {};
    $("seGValidity").value = g.validity || ""; $("seGHow").value = g.how || ""; $("seGShipping").value = g.shipping || "";
    $("seGTerms").value = g.terms_url || ""; $("seGChecked").value = g.checked || "";
    $("seGEarn").value = g.earn || ""; $("seGPerks").value = g.perks || ""; $("seGProgram").value = g.program_url || "";
    $("seGBirthday").value = g.birthday || "";
    $("seGOnline").value = typeof g.online === "boolean" ? String(g.online) : "";
    $("seGStore").value = typeof g.store === "boolean" ? String(g.store) : "";
    guideVisible();
    $("seSwatches").replaceChildren();
    $("seRequests").textContent = requestIds.length ? `Na publiceren worden ${requestIds.length === 1 ? "1 aanvraag" : requestIds.length + " aanvragen"} gesloten als toegevoegd.` : "";
    $("seReject").classList.toggle("hidden", !requestIds.length);
    $("seUnpublish").classList.toggle("hidden", !editing.published);
    $("sePublish").textContent = editing.published ? "Opslaan en bijwerken" : "Toevoegen en publiceren";
    $("seMsg").textContent = "";
    $("storeEditor").classList.remove("hidden");
    $("storeEditor").scrollIntoView({ behavior: "smooth", block: "start" });
    preview();
    if (fromRequest && s.domain && !s.logo) lookup();
  }
  $("storeNew").addEventListener("click", () => openEditor({}, [], false));
  new MutationObserver(() => $("storeEditor").parentElement.classList.toggle("editing", !$("storeEditor").classList.contains("hidden")))
    .observe($("storeEditor"), { attributes: true, attributeFilter: ["class"] });
  $("seClose").addEventListener("click", () => { $("storeEditor").classList.add("hidden"); editing = null; });
  ["seName", "seColor", "seKind"].forEach((id) => $(id).addEventListener("input", preview));
  $("seKind").addEventListener("change", preview);
  /** Gids: bij een cadeaukaart de cadeaubon-gids, bij een klantenkaart de programmagids (zo spaar je, voordelen). */
  function guideVisible() {
    const kind = $("seKind").value === "voucher" ? "voucher" : "loyalty";
    $("seGuide").classList.remove("hidden");
    $("seGTitle").textContent = kind === "voucher" ? "Cadeaubon-gids" : "Programmagids";
    $("seGHowLabel").textContent = kind === "voucher" ? "Zo wissel je hem in (1 tot 3 zinnen)" : "Zo kom je aan de kaart (1 zin)";
    document.querySelectorAll("#seGuide [data-gkind]").forEach((n) => n.classList.toggle("hidden", n.dataset.gkind !== kind));
  }
  $("seKind").addEventListener("change", guideVisible);
  /** Gids uit het formulier (alleen de velden van deze soort kaart); leeg = null (wissen). */
  function guideBody() {
    const g = {}, t = (id) => $(id).value.trim(), b = (id) => ($(id).value === "" ? undefined : $(id).value === "true");
    if ($("seKind").value === "voucher") {
      if (t("seGValidity")) g.validity = t("seGValidity");
      if (b("seGOnline") !== undefined) g.online = b("seGOnline");
      if (b("seGStore") !== undefined) g.store = b("seGStore");
      if (t("seGShipping")) g.shipping = t("seGShipping");
    } else {
      if (t("seGEarn")) g.earn = t("seGEarn");
      if (t("seGPerks")) g.perks = t("seGPerks");
      if (t("seGProgram")) g.program_url = t("seGProgram");
    }
    if (t("seGHow")) g.how = t("seGHow");
    if (t("seGBirthday")) g.birthday = t("seGBirthday");
    if (t("seGTerms")) g.terms_url = t("seGTerms");
    if (t("seGChecked")) g.checked = t("seGChecked");
    return Object.keys(g).length ? g : null;
  }

  function preview() {
    if (!editing) return;
    const p = $("sePreview"), color = $("seColor").value;
    p.style.background = color;
    p.classList.toggle("light", luminance(color) > 0.45);
    $("sePreviewName").textContent = editing.logo ? "" : ($("seName").value || "Winkel");
    $("sePreviewLogo").classList.toggle("hidden", !editing.logo);
    if (editing.logo) $("sePreviewLogo").src = "data:image/png;base64," + editing.logo;
    p.querySelector("small").textContent = $("seKind").value === "voucher" ? "Cadeaukaart" : "Klantenkaart";
    // Kaartontwerp: alleen bij een cadeaukaart; dan is dat de voorkant (zoals in de app en op pasr.nl/kaarten).
    const voucher = $("seKind").value === "voucher";
    $("seCoverRow").classList.toggle("hidden", !voucher);
    const cover = voucher && editing.cover;
    $("sePreviewCover").classList.toggle("hidden", !cover);
    p.classList.toggle("has-cover", !!cover);
    if (cover) { $("sePreviewCover").src = (editing.cover.startsWith("/9j/") ? "data:image/jpeg;base64," : "data:image/png;base64,") + editing.cover; }
    $("sePreview").setAttribute("aria-label", $("seName").value || "Winkel");
  }
  /** Kaartontwerp bijsnijden tot 1,586:1 en verkleinen tot 640 px breed (JPEG 0,8); zelfde als tools/make_covers.py. */
  function makeCover(file) {
    return new Promise((resolve, reject) => {
      // Via een data-URL (FileReader), niet blob: — de CSP staat alleen img-src 'self' data: toe.
      const img = new Image(), reader = new FileReader();
      img.onload = () => {
        const ratio = 1.586, W = 640, H = Math.round(W / ratio);
        let sw = img.naturalWidth, sh = img.naturalHeight, sx = 0, sy = 0;
        if (sw / sh > ratio) { const nw = Math.round(sh * ratio); sx = (sw - nw) / 2; sw = nw; }
        else { const nh = Math.round(sw / ratio); sy = (sh - nh) / 2; sh = nh; }
        const c = document.createElement("canvas"); c.width = W; c.height = H;
        const x = c.getContext("2d"); x.fillStyle = "#FFFFFF"; x.fillRect(0, 0, W, H);
        x.imageSmoothingQuality = "high"; x.drawImage(img, sx, sy, sw, sh, 0, 0, W, H);
        let q = 0.8, out = c.toDataURL("image/jpeg", q).split(",")[1];
        while (out.length > 200_000 && q > 0.4) { q -= 0.1; out = c.toDataURL("image/jpeg", q).split(",")[1]; }
        out.length > 200_000 ? reject(new Error("Het kaartontwerp is te groot.")) : resolve(out);
      };
      img.onerror = () => reject(new Error("Dit bestand is geen afbeelding."));
      reader.onload = () => { img.src = reader.result; };
      reader.onerror = () => reject(new Error("Dit bestand kan niet worden gelezen."));
      reader.readAsDataURL(file);
    });
  }
  function luminance(hex) {
    const v = parseInt(hex.slice(1), 16), c = [(v >> 16) & 255, (v >> 8) & 255, v & 255].map((x) => { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  }
  function swatches(colors) {
    const box = $("seSwatches");
    box.replaceChildren();
    for (const c of [...new Set(colors)].slice(0, 6)) {
      const b = el("button", "sw"); b.type = "button"; b.style.background = c; b.title = c; b.setAttribute("aria-label", "Kleur " + c);
      b.addEventListener("click", () => { $("seColor").value = c; preview(); });
      box.append(b);
    }
  }
  /** Merkkleur uit het logo: gemiddelde van de duidelijk gekleurde pixels (niet wit, zwart of doorzichtig). */
  function logoColor(b64) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const c = document.createElement("canvas"), n = 64; c.width = c.height = n;
        const x = c.getContext("2d"); x.drawImage(img, 0, 0, n, n);
        const d = x.getImageData(0, 0, n, n).data; let r = 0, g = 0, b = 0, k = 0;
        for (let i = 0; i < d.length; i += 4) {
          const [R, G, B, A] = [d[i], d[i + 1], d[i + 2], d[i + 3]];
          const max = Math.max(R, G, B), min = Math.min(R, G, B);
          if (A < 200 || max > 240 && min > 240 || max < 20 || max - min < 25) continue;
          r += R; g += G; b += B; k++;
        }
        resolve(k ? "#" + [r, g, b].map((v) => Math.round(v / k).toString(16).padStart(2, "0")).join("").toUpperCase() : null);
      };
      img.onerror = () => resolve(null);
      img.src = "data:image/png;base64," + b64;
    });
  }
  async function lookup() {
    const url = $("seDomain").value.trim();
    if (!url) return;
    $("seLookup").disabled = true; $("seMsg").textContent = "Website opzoeken…";
    try {
      const r = await api("store_lookup", { url });
      $("seDomain").value = r.domain;
      if (!$("seName").value && r.name) $("seName").value = r.name;
      if (r.logo) editing.logo = r.logo;
      const fromLogo = r.logo ? await logoColor(r.logo) : null;
      const colors = [fromLogo, ...(r.colors || [])].filter(Boolean);
      swatches(colors);
      if (colors[0] && $("seColor").value.toUpperCase() === "#2B2F3A") $("seColor").value = colors[0];
      $("seMsg").textContent = r.logo ? "Logo en kleuren gevonden. Controleer de kaart." : "Geen bruikbaar logo gevonden; upload er zelf een.";
      preview();
    } catch (err) { $("seMsg").textContent = err.code === "not_found" ? "Deze website kon niet worden geopend." : err.message; }
    finally { $("seLookup").disabled = false; }
  }
  $("seLookup").addEventListener("click", lookup);
  $("seLogoFile").addEventListener("change", () => {
    const f = $("seLogoFile").files[0];
    if (!f) return;
    if (f.size > 290_000) { $("seMsg").textContent = "Dit logo is groter dan 300 kB. Kies een kleiner bestand."; return; }
    const reader = new FileReader();
    reader.onload = async () => {
      editing.logo = String(reader.result).split(",")[1];
      const c = await logoColor(editing.logo);
      if (c) swatches([c]);
      preview();
    };
    reader.readAsDataURL(f);
  });
  $("seLogoClear").addEventListener("click", () => { editing.logo = null; $("seLogoFile").value = ""; preview(); });
  $("seCoverFile").addEventListener("change", async () => {
    const f = $("seCoverFile").files[0];
    if (!f) return;
    if (f.size > 8_000_000) { $("seMsg").textContent = "Dit bestand is te groot (hoogstens 8 MB)."; return; }
    try { editing.cover = await makeCover(f); editing.coverChanged = true; $("seMsg").textContent = ""; preview(); }
    catch (err) { $("seMsg").textContent = err.message; }
  });
  $("seCoverClear").addEventListener("click", () => { editing.cover = null; editing.coverChanged = true; $("seCoverFile").value = ""; preview(); });

  function storeBody() {
    return {
      id: editing.id || undefined, name: $("seName").value.trim(), domain: $("seDomain").value.trim(),
      category: $("seCategory").value, card_hex: $("seColor").value, format: $("seFormat").value, kind: $("seKind").value,
      aliases: $("seAliases").value.split(",").map((a) => a.trim()).filter(Boolean), logo: editing.logo,
      guide: guideBody(),
      // alleen meesturen als het ontwerp is gewijzigd (anders blijft het in de database staan)
      ...(editing.coverChanged ? { cover: editing.cover } : {}),
    };
  }
  async function saveStore(publish) {
    $("seMsg").textContent = "";
    if (publish && !editing.published && !(await ask("Winkel publiceren?", `${$("seName").value} komt meteen in Pasr, zonder app-update.` + ($("sePush").checked ? " De aanvragers en wie 'Nieuwe winkels' aan heeft, krijgen een pushmelding." : ""), "Publiceren"))) return;
    try {
      const r = await api("store_save", { store: storeBody() });
      editing.id = r.store.id;
      if (publish) {
        const p = await api("store_publish", { id: editing.id, request_ids: editing.requestIds, push: $("sePush").checked && !editing.published });
        toast(p.push_ready === false ? "Gepubliceerd. Pushmeldingen staan nog uit (APNs-sleutel ontbreekt)."
          : `Gepubliceerd${p.closed ? `, ${p.closed} ${p.closed === 1 ? "aanvraag" : "aanvragen"} gesloten` : ""}${p.sent ? `, ${p.sent} ${p.sent === 1 ? "melding" : "meldingen"} verstuurd` : ""}.`);
        $("storeEditor").classList.add("hidden"); editing = null;
      } else { toast("Opgeslagen als concept."); }
      loadStores();
    } catch (err) { $("seMsg").textContent = err.message; }
  }
  $("sePublish").addEventListener("click", () => saveStore(true));
  $("seSave").addEventListener("click", () => saveStore(false));
  $("seReject").addEventListener("click", async () => {
    if (!(await ask("Aanvraag afwijzen?", "De aanvraag wordt gesloten; in de app ziet de aanvrager 'Niet toegevoegd'.", "Afwijzen"))) return;
    try { await api("store_reject", { request_ids: editing.requestIds }); toast("Afgewezen."); $("storeEditor").classList.add("hidden"); editing = null; loadStores(); }
    catch (err) { $("seMsg").textContent = err.message; }
  });
  $("seUnpublish").addEventListener("click", async () => {
    if (!(await ask("Offline halen?", "De winkel verdwijnt uit de lijst in Pasr. Kaarten die mensen al hebben blijven gewoon werken.", "Offline halen"))) return;
    try { await api("store_unpublish", { id: editing.id }); toast("Offline gehaald."); $("storeEditor").classList.add("hidden"); editing = null; loadStores(); }
    catch (err) { $("seMsg").textContent = err.message; }
  });

  // ---- Berichten: push aan gebruikers met de opt-in "Nieuws over mijn kaarten", of aan iedereen met meldingen aan ----
  const AUD = { all: "Iedereen met opt-in", store: "Heeft kaart", new: "Nieuwe gebruikers (7 dagen)", inactive: "Inactief (30 dagen)",
    everyone: "Iedereen met meldingen aan" };
  const PLAT = { all: "Alles", ios: "Apple", android: "Android" };
  const APPN = { pasr: "Pasr", zakelijk: "Pasr Zakelijk", both: "Pasr en Pasr Zakelijk" };
  let newsData = null, countTimer, nPlatform = "all";
  // link: alleen https, hoogstens 500 tekens (de server controleert het ook)
  function newsUrl() {
    const v = $("nUrl").value.trim();
    if (!v) return { ok: true, url: null };
    try {
      const u = new URL(v);
      if (u.protocol !== "https:" || v.length > 500 || u.username || u.password || !u.hostname.includes(".")) return { ok: false };
      return { ok: true, url: u.toString() };
    } catch { return { ok: false }; }
  }
  async function loadNews() {
    $("newsErr").classList.add("hidden");
    try {
      await loadBuiltin();
      newsData = await api("news_overview");
      const ev = newsData.everyone;
      const evText = ev ? ` Meldingen aan: Pasr ${num(ev.pasr?.ios)} Apple / ${num(ev.pasr?.android)} Android, Pasr Zakelijk ${num(ev.zakelijk?.ios)} Apple / ${num(ev.zakelijk?.android)} Android.` : "";
      $("newsInfo").textContent = `${num(newsData.all)} ${newsData.all === 1 ? "apparaat" : "apparaten"} met de opt-in, ${num(newsData.new)} nieuw deze week, ${num(newsData.inactive)} inactief.` + evText +
        (newsData.push_ready ? "" : " Pushmeldingen zijn nog niet ingericht.")
        + (newsData.push_ready && newsData.fcm_ready === false ? " Android-push (FCM) is nog niet ingericht." : "");
      $("nStores").replaceChildren(...(newsData.stores || []).map((x) => { const o = document.createElement("option"); o.value = x.id; o.label = `${storeName(x.id)} (${num(x.count)})`; return o; }));
      const h = $("newsHistory");
      h.replaceChildren();
      if (!(newsData.history || []).length) h.append(el("p", "empty", "Nog geen berichten verstuurd."));
      for (const c of newsData.history || []) {
        const row = el("div", "hist");
        const left = el("div");
        const who = `${AUD[c.audience] || c.audience}${c.store_id ? " " + storeName(c.store_id) : ""}`
          + (c.audience === "everyone" ? ` · ${APPN[c.app] || c.app}` : "") + (c.platform && c.platform !== "all" ? ` · ${PLAT[c.platform]}` : "");
        left.append(el("b", null, c.title || (c.app === "zakelijk" ? "Pasr Zakelijk" : "Pasr")), el("p", null, c.body));
        if (c.url) {
          const a = el("a", "link", c.url);
          a.href = c.url; a.target = "_blank"; a.rel = "noopener noreferrer";
          left.append(a);
        }
        left.append(el("span", "muted sm", `${who} · ${new Date(c.created_at).toLocaleString("nl-NL", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}`));
        const n = el("div", "n");
        n.append(el("b", null, num(c.sent)), el("div", "muted sm", `van ${num(c.recipients)}${c.failed ? `, ${num(c.failed)} mislukt` : ""}`));
        row.append(left, n);
        h.append(row);
      }
      updateCount();
    } catch (err) {
      if (err.status === 401) return;
      $("newsErr").textContent = err.message; $("newsErr").classList.remove("hidden");
    }
  }
  function newsPreview() {
    const app = $("nAudience").value === "everyone" ? $("nApp").value : "pasr";
    $("pTitle").textContent = $("nTitle").value.trim() || (app === "zakelijk" ? "Pasr Zakelijk" : "Pasr");
    $("pBody").textContent = $("nBody").value.trim() || "Je bericht verschijnt hier.";
    $("nLeft").textContent = `${240 - $("nBody").value.length} tekens over`;
    const l = newsUrl();
    $("pUrl").textContent = l.url || "";
    $("pUrl").classList.toggle("hidden", !l.url);
    $("nUrlHint").textContent = l.ok ? "Alleen https. Een tik op de melding opent deze link." : "Geen geldige https-link.";
    $("nUrlHint").className = l.ok ? "muted sm" : "err sm";
    $("pNote").textContent = l.url ? "Een tik op de melding opent deze link (in de app; links van pasr.nl openen de juiste plek in Pasr)."
      : "Een tik opent de app; bij de doelgroep \u201Cheeft een kaart van\u201D opent de kaart van die winkel. Er gaan geen kaartnummers of namen mee.";
  }
  function audienceParams() {
    const audience = $("nAudience").value, p = { audience, platform: nPlatform };
    if (audience === "store") p.store = resolveStore($("nStore").value);
    if (audience === "everyone") p.app = $("nApp").value;
    return p;
  }
  const countText = (c) => num(c.count);
  const splitText = (c) => c.ios !== undefined ? `Apple ${num(c.ios)} · Android ${num(c.android || 0)}` : "";
  function updateCount() {
    clearTimeout(countTimer);
    const p = audienceParams();
    $("nStoreRow").classList.toggle("hidden", p.audience !== "store");
    $("nAppRow").classList.toggle("hidden", p.audience !== "everyone");
    $("nWarn").classList.toggle("hidden", p.audience !== "everyone");
    newsPreview();
    if (p.audience === "store" && !p.store) { $("nCount").textContent = "–"; $("nSplit").textContent = ""; return; }
    // ontvangers per platform: Apple (APNs) en Android (FCM)
    countTimer = setTimeout(async () => {
      try { const c = await api("news_count", p); $("nCount").textContent = countText(c); $("nSplit").textContent = splitText(c); }
      catch { $("nCount").textContent = "–"; $("nSplit").textContent = ""; }
    }, 250);
  }
  ["nTitle", "nBody", "nUrl"].forEach((id) => $(id).addEventListener("input", newsPreview));
  $("nAudience").addEventListener("change", updateCount);
  $("nApp").addEventListener("change", updateCount);
  $("nStore").addEventListener("input", updateCount);
  document.querySelectorAll("#nPlatform button").forEach((b) => b.addEventListener("click", () => {
    nPlatform = b.dataset.v;
    document.querySelectorAll("#nPlatform button").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
    updateCount();
  }));
  let newsSending = false;
  $("newsForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    if (newsSending) return;
    const msg = $("nMsg"); msg.className = "err"; msg.textContent = "";
    const body = $("nBody").value.trim();
    if (!body) { msg.textContent = "Schrijf een bericht."; return; }
    const link = newsUrl();
    if (!link.ok) { msg.textContent = "De link moet een geldige https-link zijn (hoogstens 500 tekens)."; return; }
    const p = audienceParams();
    let n, c;
    try { c = await api("news_count", p); n = c.count; } catch (err) { msg.textContent = err.message; return; }
    if (!n) { msg.textContent = "Er zijn geen ontvangers in deze doelgroep."; return; }
    const who = p.audience === "store" ? `iedereen met een kaart van ${storeName(p.store)}`
      : p.audience === "everyone" ? `iedereen met meldingen aan in ${APPN[p.app]}` : AUD[p.audience].toLowerCase();
    const warn = p.audience === "everyone" ? " Alleen voor belangrijke berichten, geen reclame." : "";
    if (!(await ask("Bericht versturen?", `Naar ${num(n)} ${n === 1 ? "apparaat" : "apparaten"} (${who}): ${num(c.ios ?? n)} Apple en ${num(c.android ?? 0)} Android.`
      + (link.url ? ` Met link ${link.url}.` : "") + warn + " Dit kan niet worden teruggedraaid.", "Versturen"))) return;
    newsSending = true; $("nSend").disabled = true;
    try {
      const r = await api("news_send", { title: $("nTitle").value.trim() || null, body, url: link.url, ...p });
      msg.className = "err ok";
      msg.textContent = `Verstuurd naar ${num(r.sent)} van ${num(r.recipients)} apparaten${r.failed ? ` (${num(r.failed)} mislukt)` : ""}.`
        + (r.android ? ` Apple ${num(r.ios.sent)} van ${num(r.ios.recipients)}, Android ${num(r.android.sent)} van ${num(r.android.recipients)}.` : "");
      $("nBody").value = ""; $("nTitle").value = ""; $("nUrl").value = ""; newsPreview(); loadNews();
    } catch (err) {
      msg.textContent = err.message;
    }
    finally { newsSending = false; $("nSend").disabled = false; }
  });

  // ---- Ondernemers (Pasr voor ondernemers) ----
  let bizFilter = "pending";
  function bizBadge(n) { const b = $("bizBadge"); b.textContent = n; b.classList.toggle("hidden", !n); }
  document.querySelectorAll("#bizFilter button").forEach((b) => b.addEventListener("click", () => { bizFilter = b.dataset.status; loadBusinesses(); }));
  const BIZ = { pending: ["Wacht op goedkeuring", "wait"], approved: ["Goedgekeurd", "ok"], blocked: ["Geblokkeerd", "wait"] };
  async function loadBusinesses() {
    document.querySelectorAll("#bizFilter button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.status === bizFilter)));
    const list = $("bizList");
    list.setAttribute("aria-busy", "true");
    $("bizErr").classList.add("hidden");
    try {
      const all = (await api("businesses")).businesses || [];
      bizBadge(all.filter((b) => b.status === "pending").length);
      const shown = bizFilter === "all" ? all : all.filter((b) => b.status === bizFilter);
      $("bizCount").textContent = `${num(all.length)} ${all.length === 1 ? "zaak" : "zaken"}, ${num(all.filter((b) => b.status === "pending").length)} wachten op goedkeuring.`;
      list.replaceChildren();
      if (!shown.length) list.append(el("p", "empty", bizFilter === "pending" ? "Geen aanmeldingen die wachten." : "Geen zaken in deze lijst."));
      for (const b of shown) list.append(bizRow(b));
    } catch (err) {
      if (err.status === 401) return;
      $("bizErr").textContent = err.message; $("bizErr").classList.remove("hidden");
    } finally { list.removeAttribute("aria-busy"); }
  }
  function bizRow(b) {
    const row = el("div", "acc");
    const who = el("div", "who"), meta = el("div", "meta");
    who.append(el("div", "mail", b.name + (b.city ? ` · ${b.city}` : "")));
    const st = BIZ[b.status] || BIZ.pending;
    meta.append(el("span", "badge " + st[1], st[0]), el("span", null, b.email || "—"));
    if (b.has_owner === false) meta.append(el("span", "badge wait", b.owner_invite ? (b.owner_invite.expired ? "Eigenaarslink verlopen" : "Eigenaarslink open") : "Zonder eigenaar"));
    if (b.created_by === "beheer") meta.append(el("span", null, "Aangemaakt door het beheer"));
    if (b.website) meta.append(el("span", null, b.website));
    meta.append(el("span", null, "Aangemeld " + ago(b.created_at)));
    meta.append(el("span", null, `${num(b.staff_count || 0)} ${b.staff_count === 1 ? "medewerker" : "medewerkers"}`));
    if (b.last_event_at) meta.append(el("span", null, "Laatste stempel/actie " + ago(b.last_event_at)));
    meta.append(el("span", "badge " + (b.listed === false ? "wait" : "ok"), b.listed === false ? "Niet vindbaar in Pasr" : "Vindbaar in Pasr"));
    who.append(meta);
    if (b.note) who.append(el("p", "muted sm", b.note));
    const cards = el("div", "biz-cards");
    for (const c of b.cards || []) {
      const chip = el("button", "biz-card click"); chip.type = "button"; chip.title = "Stempelkaart bewerken";
      chip.addEventListener("click", () => openCardEditor(b, c));
      chip.style.background = c.color;
      if (luminance(c.color) > 0.45) chip.classList.add("light");
      if (c.logo) { const i = document.createElement("img"); i.alt = ""; i.src = "data:image/" + (c.logo.startsWith("/9j/") ? "jpeg" : "png") + ";base64," + c.logo; chip.append(i); }
      else chip.append(el("span", "mono", (c.name || "?").charAt(0).toUpperCase()));
      chip.append(el("span", null, `${c.name}: ${c.stamps_total} stempels, ${c.reward} · ${c.published ? "online" : "concept"} · ${num(c.members)} leden, ${num(c.stamps)} stempels, ${num(c.rewards)} beloningen`));
      cards.append(chip);
    }
    if ((b.cards || []).length) who.append(cards);
    const acts = el("div", "acts");
    const btn = (label, cls, status, q, t) => {
      const x = el("button", "btn sm " + cls, label); x.type = "button";
      x.addEventListener("click", async () => {
        if (q && !(await ask(q, t, label))) return;
        x.disabled = true;
        try { await api("business_status", { id: b.id, status }); toast(`${b.name}: ${BIZ[status][0].toLowerCase()}`); loadBusinesses(); }
        catch (err) { toast(err.message); x.disabled = false; }
      });
      return x;
    };
    const det = el("button", "btn sm ghost", "Details"); det.type = "button";
    det.addEventListener("click", () => toggleBizDetail(row, b, det));
    const edit = el("button", "btn sm ghost", "Bewerken"); edit.type = "button";
    edit.addEventListener("click", () => openBizForm(b));
    const newCard = el("button", "btn sm ghost", "Nieuwe stempelkaart"); newCard.type = "button";
    newCard.disabled = (b.cards || []).length >= 5; if (newCard.disabled) newCard.title = "Hoogstens 5 stempelkaarten per zaak";
    newCard.addEventListener("click", () => openCardEditor(b, null));
    acts.append(det, edit, newCard);
    if (b.status !== "approved") acts.append(btn("Goedkeuren", "", "approved"));
    if (b.status !== "blocked") acts.append(btn("Blokkeren", "danger", "blocked", "Zaak blokkeren?", `${b.name} kan niet meer scannen en de kaarten gaan offline. Leden zien dat de kaart niet meer actief is.`));
    if (b.status === "blocked") acts.append(btn("Terug naar wachten", "ghost", "pending"));
    acts.classList.add("wrap-acts");
    row.append(el("div", "avatar", b.name.charAt(0).toUpperCase()), who, acts);
    return row;
  }

  // ---- Ondernemers: details per zaak (medewerkers, instellingen, stats, log) ----
  const LOGKIND = { join: "Nieuw lid", claim: "Kaart naar de app", stamp: "Stempel", redeem: "Beloning", undo: "Ongedaan", admin: "Beheer" };
  async function toggleBizDetail(row, b, btn) {
    const open = row.nextElementSibling && row.nextElementSibling.classList.contains("biz-detail");
    if (open) { row.nextElementSibling.remove(); btn.textContent = "Details"; return; }
    btn.textContent = "Sluiten";
    const box = el("div", "biz-detail");
    box.append(el("p", "muted", "Laden…"));
    row.after(box);
    let d;
    try { d = await api("business_detail", { id: b.id, limit: 200, days: 30 }); }
    catch (err) { box.replaceChildren(el("p", "err", err.message)); return; }
    box.replaceChildren();
    const z = d.business || b;
    // instellingen
    const set = el("form", "biz-set");
    const field = (label, input) => { const l = el("label", null, label); l.append(input); return l; };
    const cool = Object.assign(document.createElement("input"), { type: "number", min: 0, max: 1440, value: z.cooldown_minutes ?? 5 });
    const max = Object.assign(document.createElement("input"), { type: "number", min: 1, max: 30, value: z.max_per_scan ?? 10 });
    const listed = Object.assign(document.createElement("input"), { type: "checkbox", checked: z.listed !== false });
    const addr = Object.assign(document.createElement("input"), { type: "text", maxLength: 200, value: z.address || "", placeholder: "Adres (optioneel)" });
    const lc = el("label", "check"); lc.append(listed, document.createTextNode(" Vindbaar in Pasr (Kaart toevoegen › Stempelkaart)"));
    const save = el("button", "btn sm", "Instellingen opslaan"); save.type = "submit";
    const msg = el("span", "muted sm");
    set.append(el("h3", null, "Instellingen"), field("Afkoeltijd (minuten, 0 = uit)", cool), field("Max stempels per scan (1–30)", max), field("Adres", addr), lc,
      el("p", "muted sm", z.lat != null ? `Locatie: ${Number(z.lat).toFixed(4)}, ${Number(z.lng).toFixed(4)}` : "Geen locatie (alleen via de app Pasr Zakelijk)."), save, msg);
    set.addEventListener("submit", async (e) => {
      e.preventDefault();
      const p = { id: b.id, cooldown_minutes: Number(cool.value), max_per_scan: Number(max.value), listed: listed.checked };
      if (addr.value.trim() !== (z.address || "")) p.address = addr.value.trim() || null;
      save.disabled = true;
      try { await api("business_settings", p); msg.textContent = "Opgeslagen."; toast(`${b.name}: instellingen opgeslagen`); }
      catch (err) { msg.textContent = err.message; }
      finally { save.disabled = false; }
    });
    // stats
    const st = d.stats || { days: [], totals: {} };
    const stats = el("div", "biz-stats");
    const t = st.totals || {};
    stats.append(el("h3", null, "Laatste 30 dagen"),
      el("p", null, `${num(t.stamps)} stempels · ${num(t.rewards)} beloningen · ${num(t.new_members)} nieuwe leden · ${num(t.members)} leden totaal`));
    const bars = el("div", "biz-bars"), mx = Math.max(1, ...(st.days || []).map((x) => x.stamps));
    for (const x of st.days || []) { const i = el("i"); i.style.height = Math.max(2, Math.round(x.stamps / mx * 100)) + "%"; i.title = `${x.day}: ${x.stamps}`; bars.append(i); }
    stats.append(bars);
    // medewerkers
    const staff = el("div", "biz-staff");
    staff.append(el("h3", null, "Medewerkers"));
    for (const m of d.staff || []) {
      const r = el("div", "biz-line");
      const status = m.revoked ? "ingetrokken" : m.pending ? (m.expired ? "uitnodiging verlopen" : "uitnodiging open") : "actief";
      r.append(el("span", null, `${m.name || (m.role === "owner" ? "Eigenaar" : "—")}${m.email ? " · " + m.email : ""}`), el("span", "muted sm", `${m.role === "owner" ? "eigenaar" : "medewerker"}, ${status}`));
      if (m.role !== "owner" && !m.revoked) {
        const x = el("button", "btn sm danger", "Intrekken"); x.type = "button";
        x.addEventListener("click", async () => {
          if (!(await ask("Medewerker intrekken?", `${m.name || "Deze medewerker"} kan dan niet meer scannen bij ${b.name}.`, "Intrekken"))) return;
          x.disabled = true;
          try { await api("business_staff_revoke", { id: m.id }); toast("Ingetrokken"); box.remove(); toggleBizDetail(row, b, btn); }
          catch (err) { toast(err.message); x.disabled = false; }
        });
        r.append(x);
      }
      staff.append(r);
    }
    // log
    const log = el("div", "biz-log");
    log.append(el("h3", null, "Log (laatste 200)"));
    if (!(d.log || []).length) log.append(el("p", "muted", "Nog niets gebeurd."));
    for (const x of d.log || []) {
      const r = el("div", "biz-line" + (x.undone ? " undone" : ""));
      if (x.kind === "admin") {
        r.append(el("span", null, `${new Date(x.at).toLocaleString("nl-NL", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })} · ${x.note || "Beheer"}`),
          el("span", "muted sm", `${x.card_name ? x.card_name + " · " : ""}${x.by_role === "beheer" ? "beheer" : (x.by_name || "?")}`));
        log.append(r); continue;
      }
      const what = x.kind === "stamp" ? `${x.amount} ${x.amount === 1 ? "stempel" : "stempels"}` : (LOGKIND[x.kind] || x.kind);
      r.append(el("span", null, `${new Date(x.at).toLocaleString("nl-NL", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })} · ${what}${x.stamps_after != null && x.kind !== "join" && x.kind !== "claim" ? ` (${x.stamps_before} → ${x.stamps_after})` : ""}`),
        el("span", "muted sm", `${x.card_name || "verwijderde kaart"} · …${x.member_suffix || ""} · ${x.by_role === "customer" ? "klant" : (x.by_name || "?") + (x.by_role === "staff" ? " (medewerker)" : "")}${x.device ? " · " + x.device : ""}`));
      log.append(r);
    }
    box.prepend(ownerBox(z, () => { box.remove(); toggleBizDetail(row, b, btn); loadBusinesses(); }));
    box.append(set, stats, staff, log);
  }

  /** Eigenaar: wie het is, of de open eigenaarslink (kopiëren, QR, opnieuw versturen). */
  function ownerBox(z, refresh) {
    const box = el("div", "owner-box");
    box.append(el("h3", null, "Eigenaar"));
    if (z.has_owner !== false) { box.append(el("p", "muted sm", z.owner_email ? `${z.owner_email} (Pasr-account)` : "Pasr-account")); return box; }
    const inv = z.owner_invite;
    box.append(el("p", "muted sm", inv ? `Nog geen eigenaar. Eigenaarslink voor ${inv.email || "—"}, ${inv.expired ? "verlopen" : "geldig tot " + new Date(inv.expires_at).toLocaleDateString("nl-NL", { day: "numeric", month: "long" })}.`
      : "Geen eigenaar: jij beheert deze zaak. Vul bij Bewerken een e-mailadres in om een eigenaar uit te nodigen."));
    if (inv && !inv.expired) box.append(inviteLinkBlock(inv));
    if (z.unconfirmed_account) {
      box.append(el("p", "muted sm", "Er bestaat al een Pasr-account met dit adres, maar het e-mailadres is niet bevestigd."));
      box.append(confirmOwnerButton(z, refresh));
    }
    if (inv || z.email) {
      const again = el("button", "btn sm ghost", inv ? "Nieuwe link maken en mailen" : "Eigenaarslink maken en mailen"); again.type = "button";
      again.addEventListener("click", async () => {
        if (!(await ask(inv ? "Nieuwe eigenaarslink?" : "Eigenaarslink maken?", `De oude link werkt dan niet meer. De nieuwe gaat naar ${inv?.email || z.email} (30 dagen geldig).`, "Versturen"))) return;
        again.disabled = true;
        try {
          const r = await api("business_owner_invite", { id: z.id, send: true });
          toast(r.owner === "account" ? "Bestaand Pasr-account is nu eigenaar." : r.mailed ? "Nieuwe link gemaild." : "Nieuwe link gemaakt (niet gemaild: geen SMTP). Kopieer hem.");
          refresh();
        } catch (err) { toast(err.message); again.disabled = false; }
      });
      box.append(el("div", "se-row")); box.lastChild.append(again);
    }
    return box;
  }
  /** Onbevestigd Pasr-account met het adres van de zaak: bevestigen en eigenaar maken (nooit wachtwoorden). */
  function confirmOwnerButton(z, done) {
    const x = el("button", "btn sm", "Account bevestigen en eigenaar maken"); x.type = "button";
    x.addEventListener("click", async () => {
      if (!(await ask("Account bevestigen en eigenaar maken?", `Er is al een Pasr-account met ${z.email || "dit adres"}, maar het e-mailadres is nog niet bevestigd. Bevestig het alleen als je zeker weet dat het adres klopt. Het account wordt dan eigenaar van ${z.name}; het wachtwoord blijft van de gebruiker.`, "Bevestigen"))) return;
      x.disabled = true;
      try { const r = await api("business_owner_confirm", { id: z.id }); toast(`${z.email || "Account"} bevestigd en eigenaar`); done(r); }
      catch (err) { toast(err.message); x.disabled = false; }
    });
    return x;
  }
  function qrData(text, cell) {
    if (typeof qrcode !== "function") return "";
    const q = qrcode(0, "M"); q.addData(text); q.make();
    return q.createDataURL(cell || 4, 2);
  }
  function copyText(text) {
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(() => toast("Gekopieerd"), () => window.prompt("Kopieer de link", text));
    else window.prompt("Kopieer de link", text);
  }
  function inviteLinkBlock(inv) {
    const wrap = el("div", "owner-link");
    const img = el("img"); img.alt = "QR-code van de eigenaarslink"; img.width = 96; img.height = 96; img.src = qrData(inv.link, 3);
    const right = el("div");
    right.append(el("div", "mono-link", inv.link));
    const copy = el("button", "btn sm ghost", "Kopieer link"); copy.type = "button";
    copy.addEventListener("click", () => copyText(inv.link));
    right.append(copy);
    wrap.append(img, right);
    return wrap;
  }

  // ---- Ondernemer aanmaken of bewerken (zakelijk 1.1) ----
  let bizEditing = null;   // null = nieuw, anders de zaak
  function openBizForm(b) {
    bizEditing = b || null;
    $("bfTitle").textContent = b ? `${b.name} bewerken` : "Nieuwe ondernemer";
    $("bfName").value = b?.name || ""; $("bfCity").value = b?.city || ""; $("bfAddress").value = b?.address || "";
    $("bfWebsite").value = b?.website || ""; $("bfEmail").value = b?.email || "";
    $("bfCooldown").value = b?.cooldown_minutes ?? 5; $("bfMax").value = b?.max_per_scan ?? 10; $("bfListed").checked = b ? b.listed !== false : true;
    $("bfSend").checked = true;
    const owned = b && b.has_owner !== false;
    $("bfEmail").closest("label").firstChild.textContent = owned ? "E-mail (contact)" : "E-mail van de eigenaar";
    $("bfEmailHint").textContent = owned ? "Deze zaak heeft een eigenaar met een Pasr-account; dit is alleen het contactadres."
      : "Heeft dit adres al een Pasr-account, dan wordt dat account eigenaar. Anders maken we een eigenaarslink (30 dagen geldig). Leeg = geen eigenaar: dan beheer jij de zaak.";
    $("bfSend").closest("label").classList.toggle("hidden", !!owned);
    $("bfStatus").textContent = b ? `Status: ${(BIZ[b.status] || BIZ.pending)[0].toLowerCase()}.` : "Een zaak die je hier aanmaakt is meteen goedgekeurd.";
    $("bfSave").textContent = b ? "Opslaan" : "Aanmaken";
    $("bfResult").classList.add("hidden"); $("bfResult").replaceChildren();
    $("bfCard").classList.add("hidden");
    $("bfMsg").textContent = "";
    $("bizSheet").classList.remove("hidden");
    setTimeout(() => $("bfName").focus(), 30);
  }
  function closeSheet(id) { $(id).classList.add("hidden"); }
  $("bizNew").addEventListener("click", () => openBizForm(null));
  $("bfClose").addEventListener("click", () => closeSheet("bizSheet"));
  $("bizSheet").addEventListener("click", (e) => { if (e.target === $("bizSheet")) closeSheet("bizSheet"); });
  $("bizForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    $("bfMsg").textContent = "";
    const name = $("bfName").value.trim();
    if (name.length < 2) { $("bfMsg").textContent = "Vul de naam van de zaak in (minstens 2 tekens)."; return; }
    const business = { name, city: $("bfCity").value.trim(), address: $("bfAddress").value.trim() || null, website: $("bfWebsite").value.trim() || null,
      email: $("bfEmail").value.trim(), listed: $("bfListed").checked, cooldown_minutes: Number($("bfCooldown").value), max_per_scan: Number($("bfMax").value) };
    if (bizEditing && (bizEditing.address || "") === (business.address || "")) delete business.address;   // locatie laten staan
    $("bfSave").disabled = true;
    try {
      const r = bizEditing ? await api("business_update", { id: bizEditing.id, business, send: $("bfSend").checked })
                           : await api("business_create", { business, send: $("bfSend").checked });
      bizEditing = r.business;
      showBizResult(r);
      $("bfTitle").textContent = `${r.business.name} bewerken`;
      $("bfSave").textContent = "Opslaan";
      $("bfCard").classList.toggle("hidden", (r.business.cards || []).length >= 5);
      toast(`${r.business.name} opgeslagen`);
      if (bizFilter === "pending") bizFilter = "approved";
      loadBusinesses();
    } catch (err) { $("bfMsg").textContent = err.message; }
    finally { $("bfSave").disabled = false; }
  });
  function showBizResult(r) {
    const box = $("bfResult");
    box.replaceChildren();
    if (r.owner === "account") box.append(el("p", null, "Eigenaar gekoppeld: het Pasr-account met dit e-mailadres is nu eigenaar. Die ziet de zaak meteen in Pasr Zakelijk en op pasr.nl/zakelijk."));
    else if (r.owner === "invite" && r.invite) {
      box.append(el("p", null, r.mailed ? `Eigenaarslink gemaild naar ${r.invite.email}. Je kunt hem ook kopiëren:`
        : `Eigenaarslink gemaakt voor ${r.invite.email}${r.mail_ready === false ? " (mailen staat uit: geen SMTP)" : ""}. Kopieer hem en stuur hem zelf:`));
      box.append(inviteLinkBlock(r.invite));
      if (r.unconfirmed_account) {
        box.append(el("p", null, "Er bestaat al een Pasr-account met dit adres, maar het e-mailadres is niet bevestigd (bijvoorbeeld een review-adres zonder mailbox)."));
        box.append(confirmOwnerButton(r.business, (x) => { bizEditing = x.business; showBizResult({ ...x, owner: "account" }); loadBusinesses(); }));
      }
    } else if (r.owner === "none") box.append(el("p", null, r.invite ? "Nog geen eigenaar; de eigenaarslink staat open (zie Details)." : "Zonder eigenaar: jij beheert deze zaak. Maak nu de stempelkaart."));
    else box.append(el("p", null, "Opgeslagen."));
    box.classList.remove("hidden");
  }
  $("bfCard").addEventListener("click", () => { const b = bizEditing; closeSheet("bizSheet"); if (b) openCardEditor(b, null); });

  // ---- Stempelkaart aanmaken of bewerken: live voorbeeld, huisstijl ophalen, QR, link en flyer ----
  const SC_ICON = {
    stamp: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>',
    gift: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="8" width="18" height="13" rx="2"/><path d="M12 8v13M3 12h18M12 8S10.5 3 7.5 4.5 9 8 12 8zm0 0s1.5-5 4.5-3.5S15 8 12 8z"/></svg>',
  };
  const CARD_SWATCHES = ["#6A5CFF", "#17162A", "#E30613", "#FF6B57", "#E2683C", "#F2B705", "#2ED3A6", "#12A77E", "#0A84FF", "#7B4B2A", "#AF52DE", "#FF375F"];
  function mixHex(hex, to, part) {
    let out = "#";
    for (let i = 1; i < 7; i += 2) { const v = Math.round(parseInt(hex.substr(i, 2), 16) * (1 - part) + to * part); out += v.toString(16).padStart(2, "0"); }
    return out;
  }
  /** De stempelkaart zoals op pasr.nl/zakelijk (DOM, geen inline styles in HTML vanwege de CSP). */
  function stampCardEl(card, count) {
    const color = /^#[0-9a-f]{6}$/i.test(card.color || "") ? card.color : "#6A5CFF";
    const total = Math.max(2, Math.min(30, Number(card.stamps_total) || 10));
    const n = Math.max(0, Number(count) || 0), shown = n % total === 0 && n > 0 ? total : n % total;
    const cols = total <= 5 ? total : total <= 10 ? 5 : total <= 12 ? 6 : total <= 21 ? 7 : 8;
    const ink = /^#000000$/i.test(card.text_color || "") ? true : /^#FFFFFF$/i.test(card.text_color || "") ? false : luminance(color) > 0.45;
    const sc = el("div", "sc" + (ink ? " ink" : ""));
    sc.style.setProperty("--c", color); sc.style.setProperty("--cols", String(cols));
    sc.style.background = `linear-gradient(135deg, ${mixHex(color, 255, 0.16)}, ${color} 55%, ${mixHex(color, 0, 0.22)})`;
    const head = el("div", "sc-head"), logo = el("span", "sc-logo");
    if (card.logo) { const i = el("img"); i.alt = ""; i.src = "data:image/" + (card.logo.startsWith("/9j/") ? "jpeg" : "png") + ";base64," + card.logo; logo.append(i); }
    else logo.textContent = String(card.name || "?").split(" ").slice(0, 2).map((w) => w[0] || "").join("").toUpperCase();
    const title = el("span", "sc-title");
    title.append(el("span", "sc-name", card.name || "Naam van de kaart"), el("span", "sc-biz", [card.business, card.city].filter(Boolean).join(" · ")));
    head.append(logo, title, el("span", "sc-kind", "Stempelkaart"));
    const stamps = el("div", "sc-stamps"); stamps.setAttribute("role", "img"); stamps.setAttribute("aria-label", `${shown} van ${total} stempels`);
    for (let i = 0; i < total; i++) {
      const on = i < shown, last = i === total - 1;
      const s = el("span", "sc-stamp" + (on ? " on" : "") + (last && !on ? " gift" : "")); s.style.setProperty("--i", String(i));
      if (on || last) s.innerHTML = on ? SC_ICON.stamp : SC_ICON.gift;
      stamps.append(s);
    }
    const reward = el("div", "sc-reward");
    reward.append(el("span", null, card.reward || "Beloning"), el("span", null, n >= total ? "Beloning klaar" : `${total - shown} te gaan`));
    sc.append(head, stamps, reward);
    return sc;
  }

  let cardEditing = null;   // {biz, card, logo, demo}
  function openCardEditor(biz, card) {
    const c = card || { name: "", reward: "", stamps_total: 10, color: "#6A5CFF", logo: null, text_color: null, published: false };
    cardEditing = { biz, card: card || null, logo: c.logo || null, demo: "0", logoChanged: false };
    $("ceTitle").textContent = card ? "Stempelkaart bewerken" : "Nieuwe stempelkaart";
    $("ceBiz").textContent = [biz.name, biz.city].filter(Boolean).join(" · ") + (biz.status !== "approved" ? " · nog niet goedgekeurd" : "");
    $("ceName").value = c.name || ""; $("ceReward").value = c.reward || "";
    $("ceTotal").value = c.stamps_total || 10; $("ceTotalOut").textContent = $("ceTotal").value;
    $("ceColor").value = (c.color || "#6A5CFF").toLowerCase();
    $("ceInk").value = /^#(FFFFFF|000000)$/i.test(c.text_color || "") ? c.text_color.toUpperCase() : "";
    $("ceSite").value = biz.website || "";
    $("ceBrandMsg").textContent = "";
    $("cePub").checked = !!c.published && biz.status === "approved";
    $("cePub").disabled = biz.status !== "approved";
    $("cePub").closest("label").lastChild.textContent = biz.status === "approved" ? " Online: klanten kunnen aansluiten" : " Online (kan na goedkeuring van de zaak)";
    $("ceLogo").value = "";
    $("ceMsg").textContent = "";
    document.querySelectorAll("#ceDemo button").forEach((x) => x.setAttribute("aria-pressed", String(x.dataset.n === "0")));
    swatchesCard([]);
    cardButtons();
    cardPreview();
    $("cardSheet").classList.remove("hidden");
    // nieuwe kaart: huisstijl van de website meteen ophalen (zoals in Pasr Zakelijk en het dashboard)
    if (!card && biz.website) fetchBrand(true);
    setTimeout(() => $("ceName").focus(), 30);
  }
  function swatchesCard(extra) {
    const box = $("ceSwatches"); box.replaceChildren();
    for (const c of [...new Set([...extra, ...CARD_SWATCHES].map((x) => x.toUpperCase()))].slice(0, 14)) {
      const b = el("button", "sw"); b.type = "button"; b.style.background = c; b.title = c; b.setAttribute("aria-label", "Kleur " + c);
      b.addEventListener("click", () => { $("ceColor").value = c.toLowerCase(); cardPreview(); });
      box.append(b);
    }
  }
  function cardState() {
    return { name: $("ceName").value.trim(), reward: $("ceReward").value.trim(), stamps_total: Number($("ceTotal").value),
      color: $("ceColor").value.toUpperCase(), text_color: $("ceInk").value || null, logo: cardEditing.logo,
      business: cardEditing.biz.name, city: cardEditing.biz.city };
  }
  function cardPreview() {
    if (!cardEditing) return;
    const s = cardState(), d = cardEditing.demo;
    const count = d === "full" ? s.stamps_total : d === "half" ? Math.ceil(s.stamps_total / 2) : 0;
    $("cePreview").replaceChildren(stampCardEl(s, count));
  }
  function cardButtons() {
    const c = cardEditing.card;
    $("ceDelete").classList.toggle("hidden", !c);
    $("cePublish").classList.toggle("hidden", !c || cardEditing.biz.status !== "approved");
    if (c) $("cePublish").textContent = c.published ? "Offline halen" : "Publiceren";
    $("ceShare").classList.toggle("hidden", !c);
    testMembers();
    if (c) {
      const url = "https://pasr.nl/zakelijk/kaart/#" + c.id;
      $("ceLink").textContent = url;
      const big = qrData(url, 8);
      $("ceQr").src = qrData(url, 4); $("ceQrDl").href = big || "#";
      $("ceQrDl").download = "pasr-qr-" + (c.name || "kaart").toLowerCase().replace(/[^a-z0-9]+/g, "-") + ".gif";
      $("ceFlyer").href = "https://pasr.nl/zakelijk/flyer/#" + c.id;
      $("ceShareNote").textContent = c.published ? "Hang de QR-code bij de kassa of deel de link. De flyer is een A4 om te printen."
        : "De kaart is nog een concept: link, QR-code en flyer werken zodra hij online staat.";
    }
  }
  // ---- testklant (App Review): lid met label, klantcode als tekst en grote QR-code (PNG of afdrukken) ----
  function qrCanvas(text, px) {
    const q = qrcode(0, "M"); q.addData(text); q.make();
    const n = q.getModuleCount(), margin = 4, cell = Math.max(1, Math.floor(px / (n + margin * 2)));
    const c = document.createElement("canvas"); c.width = c.height = (n + margin * 2) * cell;
    const x = c.getContext("2d"); x.fillStyle = "#FFFFFF"; x.fillRect(0, 0, c.width, c.height); x.fillStyle = "#000000";
    for (let r = 0; r < n; r++) for (let k = 0; k < n; k++) if (q.isDark(r, k)) x.fillRect((k + margin) * cell, (r + margin) * cell, cell, cell);
    return c;
  }
  const spaced = (code) => code.replace(/(.{4})(?=.)/g, "$1 ");
  function testMembers() {
    const c = cardEditing?.card;
    $("ceTest").classList.toggle("hidden", !c);
    if (!c) return;
    const list = $("ceTestList"); list.replaceChildren();
    const members = c.test_members || [];
    if (!members.length) list.append(el("p", "muted sm", "Nog geen testklant."));
    for (const m of members) {
      const row = el("div", "test-member");
      const img = el("img"); img.alt = "QR-code met klantcode " + m.member_code; img.src = qrCanvas(m.member_code, 600).toDataURL("image/png");
      const info = el("div");
      info.append(el("div", "muted sm", m.label || "Testklant"), el("div", "test-code", spaced(m.member_code)),
        el("div", "muted sm", `${m.stamps_count} van ${c.stamps_total} stempels${m.rewards_redeemed ? ` · ${m.rewards_redeemed} beloningen` : ""}`));
      const btns = el("div", "se-row");
      const dl = el("a", "btn ghost sm", "PNG downloaden"); dl.href = img.src; dl.download = `pasr-testklant-${m.member_code}.png`;
      const pr = el("button", "btn ghost sm", "Afdrukken"); pr.type = "button";
      pr.addEventListener("click", () => {
        const area = $("printArea"), big = el("img"); big.alt = ""; big.src = img.src;
        area.replaceChildren(el("h2", null, `${c.business || cardEditing.biz.name} · ${c.name}`), big, el("div", "test-code", spaced(m.member_code)),
          el("p", null, "Testklant (App Review): scan deze code met Pasr Zakelijk of typ hem in."));
        document.body.classList.add("print-qr");
        const done = () => { document.body.classList.remove("print-qr"); window.removeEventListener("afterprint", done); };
        window.addEventListener("afterprint", done);
        setTimeout(() => { window.print(); setTimeout(done, 1000); }, 50);
      });
      const cp = el("button", "btn ghost sm", "Kopieer code"); cp.type = "button"; cp.addEventListener("click", () => copyText(m.member_code));
      const rs = el("button", "btn ghost sm", "Resetten"); rs.type = "button";
      rs.addEventListener("click", () => testAction(m, "reset"));
      const del = el("button", "btn danger sm", "Verwijderen"); del.type = "button";
      del.addEventListener("click", () => testAction(m, "delete"));
      btns.append(dl, pr, cp, rs, del);
      info.append(btns);
      row.append(img, info);
      list.append(row);
    }
  }
  async function testAction(m, what) {
    const c = cardEditing?.card; if (!c) return;
    if (!(await ask(what === "reset" ? "Testklant resetten?" : "Testklant verwijderen?",
      what === "reset" ? "Stempels en beloningen van deze testklant gaan terug naar 0." : "De klantcode werkt daarna niet meer.", what === "reset" ? "Resetten" : "Verwijderen"))) return;
    try {
      await api(what === "reset" ? "business_test_member_reset" : "business_test_member_delete", { id: m.id });
      c.test_members = what === "reset" ? (c.test_members || []).map((x) => x.id === m.id ? { ...x, stamps_count: 0, rewards_redeemed: 0 } : x)
        : (c.test_members || []).filter((x) => x.id !== m.id);
      testMembers(); toast(what === "reset" ? "Gereset." : "Verwijderd."); loadBusinesses();
    } catch (err) { $("ceMsg").textContent = err.message; }
  }
  $("ceTestNew").addEventListener("click", async () => {
    const c = cardEditing?.card; if (!c) return;
    $("ceTestNew").disabled = true;
    try {
      const r = await api("business_test_member", { card_id: c.id });
      c.test_members = [...(c.test_members || []), r.member];
      testMembers();
      toast(c.published ? "Testklant gemaakt." : "Testklant gemaakt. Zet de kaart online, anders kan de reviewer niet scannen.");
      loadBusinesses();
    } catch (err) { $("ceMsg").textContent = err.message; }
    finally { $("ceTestNew").disabled = false; }
  });

  ["ceName", "ceReward", "ceColor", "ceInk"].forEach((id) => $(id).addEventListener("input", cardPreview));
  $("ceInk").addEventListener("change", cardPreview);
  $("ceTotal").addEventListener("input", () => { $("ceTotalOut").textContent = $("ceTotal").value; cardPreview(); });
  document.querySelectorAll("#ceDemo button").forEach((b) => b.addEventListener("click", () => {
    document.querySelectorAll("#ceDemo button").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
    cardEditing.demo = b.dataset.n; cardPreview();
  }));
  $("ceClose").addEventListener("click", () => { closeSheet("cardSheet"); cardEditing = null; });
  $("cardSheet").addEventListener("click", (e) => { if (e.target === $("cardSheet")) { closeSheet("cardSheet"); cardEditing = null; } });
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape" || !$("modal").classList.contains("hidden")) return;
    if (!$("cardSheet").classList.contains("hidden")) { closeSheet("cardSheet"); cardEditing = null; }
    else if (!$("bizSheet").classList.contains("hidden")) closeSheet("bizSheet");
  });
  /** Logo verkleinen tot hoogstens 512 px PNG (zoals business-brand), zodat hij onder de limiet blijft. */
  function shrinkLogo(file) {
    return new Promise((resolve, reject) => {
      const img = new Image(), reader = new FileReader();
      img.onload = () => {
        const side = Math.min(512, Math.max(img.naturalWidth, img.naturalHeight));
        const scale = side / Math.max(img.naturalWidth, img.naturalHeight);
        const c = document.createElement("canvas"); c.width = Math.round(img.naturalWidth * scale); c.height = Math.round(img.naturalHeight * scale);
        const x = c.getContext("2d"); x.imageSmoothingQuality = "high"; x.drawImage(img, 0, 0, c.width, c.height);
        let out = c.toDataURL("image/png").split(",")[1];
        if (out.length > 200_000) out = c.toDataURL("image/jpeg", 0.85).split(",")[1];
        out.length > 205_000 ? reject(new Error("Het logo is te groot. Kies een kleiner bestand.")) : resolve(out);
      };
      img.onerror = () => reject(new Error("Dit bestand is geen afbeelding."));
      reader.onload = () => { img.src = reader.result; };
      reader.onerror = () => reject(new Error("Dit bestand kan niet worden gelezen."));
      reader.readAsDataURL(file);
    });
  }
  $("ceLogo").addEventListener("change", async () => {
    const f = $("ceLogo").files[0];
    if (!f) return;
    if (f.size > 8_000_000) { $("ceMsg").textContent = "Dit bestand is te groot (hoogstens 8 MB)."; return; }
    try {
      cardEditing.logo = await shrinkLogo(f); cardEditing.logoChanged = true; $("ceMsg").textContent = "";
      const c = await logoColor(cardEditing.logo); if (c) swatchesCard([c]);
      cardPreview();
    } catch (err) { $("ceMsg").textContent = err.message; }
  });
  $("ceNoLogo").addEventListener("click", () => { cardEditing.logo = null; cardEditing.logoChanged = true; $("ceLogo").value = ""; cardPreview(); });
  /** Huisstijl ophalen: zelfde logica als de functie business-brand (logo, kleur, tekstkleur van de website). */
  async function fetchBrand(auto) {
    if (!cardEditing) return;
    const url = $("ceSite").value.trim();
    if (!url) { $("ceBrandMsg").textContent = "Vul de website van de zaak in."; return; }
    const forCard = cardEditing;
    $("ceBrand").disabled = true; $("ceBrandMsg").textContent = "Huisstijl ophalen…";
    try {
      const params = { business_id: forCard.biz.id };
      if (url.replace(/^https?:\/\//i, "").replace(/\/$/, "") !== String(forCard.biz.website || "").replace(/^https?:\/\//i, "").replace(/\/$/, "")) params.url = url;
      const r = await api("business_brand", params);
      if (cardEditing !== forCard) return;
      if (r.logo) { forCard.logo = r.logo; forCard.logoChanged = true; }
      if (r.color) { $("ceColor").value = r.color.toLowerCase(); swatchesCard([r.color]); }
      if (r.text_color && r.color) $("ceInk").value = r.text_color.toUpperCase();
      if (!$("ceName").value.trim() && auto) $("ceName").value = "Stempelkaart";
      $("ceBrandMsg").textContent = `Overgenomen van ${r.domain}. Pas gerust aan.`;
      cardPreview();
    } catch (err) {
      if (cardEditing === forCard) $("ceBrandMsg").textContent = auto ? "Geen huisstijl gevonden; kies zelf een kleur en logo." : err.message;
    } finally { $("ceBrand").disabled = false; }
  }
  $("ceBrand").addEventListener("click", () => fetchBrand(false));
  async function saveCard() {
    const s = cardState();
    $("ceMsg").textContent = "";
    if (!s.name) { $("ceMsg").textContent = "Vul de naam van de kaart in."; return; }
    if (!s.reward) { $("ceMsg").textContent = "Vul de beloning in."; return; }
    const card = { name: s.name, reward: s.reward, stamps_total: s.stamps_total, color: s.color, text_color: s.text_color || "",
      published: $("cePub").checked };
    if (cardEditing.card) card.id = cardEditing.card.id;
    if (!cardEditing.card || cardEditing.logoChanged) card.logo = cardEditing.logo;
    $("ceSave").disabled = true;
    try {
      const r = await api("business_card_save", { business_id: cardEditing.biz.id, card });
      cardEditing.card = r.card; cardEditing.logoChanged = false;
      $("ceTitle").textContent = "Stempelkaart bewerken";
      cardButtons();
      toast(r.card.published ? "Opgeslagen en online." : "Opgeslagen als concept.");
      loadBusinesses();
    } catch (err) { $("ceMsg").textContent = err.message; }
    finally { $("ceSave").disabled = false; }
  }
  $("ceSave").addEventListener("click", saveCard);
  $("cardForm").addEventListener("submit", (e) => { e.preventDefault(); saveCard(); });
  $("cePublish").addEventListener("click", async () => {
    const c = cardEditing?.card; if (!c) return;
    const on = !c.published;
    if (!on && !(await ask("Offline halen?", "Nieuwe klanten kunnen niet meer aansluiten en bestaande leden zien dat de kaart niet actief is.", "Offline halen"))) return;
    $("cePublish").disabled = true;
    try {
      const r = await api("business_card_publish", { id: c.id, published: on });
      cardEditing.card = r.card; $("cePub").checked = !!r.card.published; cardButtons();
      toast(on ? "Kaart staat online." : "Kaart is offline."); loadBusinesses();
    } catch (err) { $("ceMsg").textContent = err.message; }
    finally { $("cePublish").disabled = false; }
  });
  $("ceDelete").addEventListener("click", async () => {
    const c = cardEditing?.card; if (!c) return;
    if (!(await ask("Stempelkaart verwijderen?", `${c.name} en alle leden met hun stempels gaan weg. Dit kan niet ongedaan worden gemaakt. De log blijft.`, "Verwijderen"))) return;
    try {
      const r = await api("business_card_delete", { id: c.id });
      toast(`Verwijderd (${r.members === 1 ? "1 lid" : (r.members || 0) + " leden"}).`);
      closeSheet("cardSheet"); cardEditing = null; loadBusinesses();
    } catch (err) { $("ceMsg").textContent = err.message; }
  });

  // ---- start ----
  function start() {
    $("login").classList.add("hidden");
    $("app").classList.remove("hidden");
    const want = (location.hash || "").slice(1);
    setTab(["overview", "insights", "accounts", "stores", "news", "business", "settings"].includes(want) ? want : "overview");
    api("store_requests", { status: "open" }).then((r) => badge((r.groups || []).length)).catch(() => {});
    api("businesses").then((r) => bizBadge((r.businesses || []).filter((b) => b.status === "pending").length)).catch(() => {});
  }
  if (token && expires > Date.now() && URL_ADMIN) start(); else signOut();
  // sessie verloopt: terug naar inloggen
  setInterval(() => { if (token && expires && expires <= Date.now()) signOut("Je sessie is verlopen. Log opnieuw in."); }, 60_000);
})();
