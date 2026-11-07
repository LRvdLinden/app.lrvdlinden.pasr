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
      case "bad_logo": return "Dit logo kan niet worden gebruikt (PNG, JPEG of WebP, kleiner dan 300 kB).";
      case "too_large": return "Het logo is te groot. Kies een kleiner bestand.";
      case "bad_email": return "Dit is geen geldig e-mailadres.";
      case "bad_url": return "Vul een geldig https-adres in.";
      case "bad_id": return "Kies een winkel uit de lijst (of typ het winkel-id).";
      case "weak_password": return "Kies een wachtwoord van minimaal 10 tekens met letters en cijfers.";
      case "exists": return "Dit account bestaat al. Vink aan dat je het wachtwoord wilt vervangen.";
      case "group_limit": return "Dit account zit al in 2 gedeelde Pasrs.";
      case "create_failed": case "update_failed": case "seed_failed": return "Het review-account kon niet worden gemaakt. Probeer het opnieuw.";
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
    { key: "wallet", label: "Wallet-passen", detail: "gemaakt", kind: "bar", color: "#4FB3FF" },
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
      const s = await api("stats", range);
      if (loading !== key) return;
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
      kpi("Wallet-passen", num(s.wallet_total), txt("gemaakt, totaal"), "#4FB3FF"),
      kpi("Landen", num(Object.keys(s.countries || {}).filter((c) => c !== "?").length), txt("waar accounts vandaan komen"), "#FFB547"),
      kpi("Gedeelde Pasrs", num(s.shared?.groups), txt(`${num(s.shared?.people)} personen · ${num(s.shared?.cards)} kaarten`), "#2ED3A6"),
      kpi("Tijdelijk gedeeld", num(s.temp?.active), txt(`nu geldig · +${num(s.temp?.new_7d)} deze week`), "#C77DFF"),
    );
  }
  function skeleton() {
    const box = $("kpis");
    if (box.children.length) return;
    for (let i = 0; i < 8; i++) { const k = kpi("……", "000", null, "#262A37"); k.classList.add("skel"); box.append(k); }
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
      row.append(el("span", null, label), el("span", "n", num(n)));
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
      acts.append(re);
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
    } finally { list.removeAttribute("aria-busy"); }
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
    const av = el("div", "av logo");
    av.style.background = s.card_hex;
    if (s.logo) { const img = el("img"); img.src = "data:image/png;base64," + s.logo; img.alt = ""; av.append(img); } else av.textContent = s.name.charAt(0);
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
    editing = { id: s.id || null, requestIds, logo: s.logo || null, published: !!s.published };
    $("seTitle").textContent = s.id ? s.name : (fromRequest ? "Kaart maken voor aanvraag" : "Nieuwe winkel");
    $("seDomain").value = s.domain || "";
    $("seName").value = s.name || "";
    $("seCategory").value = s.category || "Overig";
    $("seFormat").value = s.format || "ean13";
    $("seKind").value = s.kind || "loyalty";
    $("seColor").value = s.card_hex || "#2B2F3A";
    $("seAliases").value = (s.aliases || []).join(", ");
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

  function preview() {
    if (!editing) return;
    const p = $("sePreview"), color = $("seColor").value;
    p.style.background = color;
    p.classList.toggle("light", luminance(color) > 0.45);
    $("sePreviewName").textContent = editing.logo ? "" : ($("seName").value || "Winkel");
    $("sePreviewLogo").classList.toggle("hidden", !editing.logo);
    if (editing.logo) $("sePreviewLogo").src = "data:image/png;base64," + editing.logo;
    p.querySelector("small").textContent = $("seKind").value === "voucher" ? "Cadeaukaart" : "Klantenkaart";
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

  function storeBody() {
    return {
      id: editing.id || undefined, name: $("seName").value.trim(), domain: $("seDomain").value.trim(),
      category: $("seCategory").value, card_hex: $("seColor").value, format: $("seFormat").value, kind: $("seKind").value,
      aliases: $("seAliases").value.split(",").map((a) => a.trim()).filter(Boolean), logo: editing.logo,
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

  // ---- start ----
  function start() {
    $("login").classList.add("hidden");
    $("app").classList.remove("hidden");
    const want = (location.hash || "").slice(1);
    setTab(["overview", "insights", "accounts", "stores", "settings"].includes(want) ? want : "overview");
    api("store_requests", { status: "open" }).then((r) => badge((r.groups || []).length)).catch(() => {});
  }
  if (token && expires > Date.now() && URL_ADMIN) start(); else signOut();
  // sessie verloopt: terug naar inloggen
  setInterval(() => { if (token && expires && expires <= Date.now()) signOut("Je sessie is verlopen. Log opnieuw in."); }, 60_000);
})();
