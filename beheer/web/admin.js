// Pasr Beheer (beheer.pasr.nl). Praat alleen met de functie admin; token in sessionStorage (weg als het tabblad dicht gaat).
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
      case "not_found": return "Dit account bestaat niet meer.";
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
    if (t === "overview") loadStats();
    if (t === "accounts") loadUsers(true);
    if (t === "settings") showSettings();
    try { history.replaceState(null, "", "#" + t); } catch {}
  }
  document.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => setTab(b.dataset.tab)));

  // ---- overzicht ----
  const SERIES = [
    { key: "signups", label: "Nieuwe accounts", color: "#6A5CFF" },
    { key: "confirmed", label: "Bevestigd", color: "#2ED3A6" },
    { key: "deleted", label: "Verwijderd", color: "#FF6B57" },
    { key: "wallet", label: "Wallet-passen", color: "#4FB3FF" },
    { key: "bots", label: "Bots", color: "#FFB547" },
  ];
  const on = new Set(["signups", "confirmed", "wallet"]);
  let range = { days: 30, offset: 0 }, stats = null;

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
    const plus = (n, word) => { const b = el("b", null, "+" + num(n)); return [b, document.createTextNode(" " + word)]; };
    box.append(
      kpi("Accounts", num(t.accounts), plus(t.new_7d, "deze week"), "#6A5CFF"),
      kpi("Bevestigd", num(t.confirmed), [document.createTextNode(`${num(t.unconfirmed)} wachten nog`)], "#2ED3A6"),
      kpi("Kaarten in accounts", num(t.cards), [document.createTextNode(`${num(t.with_cards)} accounts met kaarten`)], "#FF6B57"),
      kpi("Actief", num(t.active_30d), [document.createTextNode("ingelogd, 30 dagen")], "#8A7FFF"),
      kpi("Wallet-passen", num(s.wallet_total), [document.createTextNode("gemaakt, totaal")], "#4FB3FF"),
      kpi("Nieuw vandaag", num(t.new_today), [document.createTextNode(`${num(t.new_30d)} in 30 dagen`)], "#FFB547"),
    );
  }
  function skeleton() {
    const box = $("kpis");
    if (box.children.length) return;
    for (let i = 0; i < 6; i++) { const k = kpi("……", "000", null, "#262A37"); k.classList.add("skel"); box.append(k); }
  }

  async function loadStats() {
    skeleton();
    $("ovErr").classList.add("hidden");
    try {
      stats = await api("stats", range);
      renderKpis(stats);
      renderChart();
      renderDists();
      $("updated").textContent = "Bijgewerkt om " + new Date(stats.generated || Date.now()).toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" });
    } catch (err) {
      if (err.status === 401) return;
      $("ovErr").textContent = err.message;
      $("ovErr").classList.remove("hidden");
    }
  }
  $("refresh").addEventListener("click", loadStats);

  // periode
  document.querySelectorAll("#chSeg button").forEach((b) => b.addEventListener("click", () => {
    range = { days: Number(b.dataset.days), offset: 0 };
    loadStats();
  }));
  $("chPrev").addEventListener("click", () => { range.offset++; loadStats(); });
  $("chNext").addEventListener("click", () => { if (range.offset > 0) { range.offset--; loadStats(); } });

  function renderChips() {
    const box = $("chChips");
    box.replaceChildren();
    for (const s of SERIES) {
      const c = el("button", "chip");
      c.type = "button";
      c.style.setProperty("--c", s.color);
      c.setAttribute("aria-pressed", String(on.has(s.key)));
      c.append(el("i"), document.createTextNode(s.label));
      c.addEventListener("click", () => { on.has(s.key) ? on.delete(s.key) : on.add(s.key); if (!on.size) on.add(s.key); renderChart(); });
      box.append(c);
    }
  }

  const fmtDay = (d, opts) => new Date(d + "T00:00:00Z").toLocaleDateString("nl-NL", { timeZone: "UTC", ...opts });
  function renderChart() {
    if (!stats) return;
    renderChips();
    document.querySelectorAll("#chSeg button").forEach((b) => b.setAttribute("aria-pressed", String(Number(b.dataset.days) === range.days)));
    const r = stats.range || {};
    $("chPeriod").textContent = r.from ? `${fmtDay(r.from, { day: "numeric", month: "short" })} – ${fmtDay(r.to, { day: "numeric", month: "short", year: "numeric" })}` : "";
    $("chNext").disabled = range.offset === 0;
    $("chPrev").disabled = (range.offset + 1) * range.days > 1100;

    // per dag, bij een jaar per week (52 staven blijven leesbaar)
    let rows = (stats.per_day || []).map((d) => ({ ...d, label: d.day }));
    if (range.days === 365) {
      const weeks = [];
      for (let i = 0; i < rows.length; i += 7) {
        const chunk = rows.slice(i, i + 7), w = { label: chunk[0].day, to: chunk[chunk.length - 1].day };
        for (const s of SERIES) w[s.key] = chunk.reduce((a, x) => a + (x[s.key] || 0), 0);
        weeks.push(w);
      }
      rows = weeks;
    }
    const active = SERIES.filter((s) => on.has(s.key));
    const plot = $("chPlot");
    plot.querySelector("svg")?.remove();
    const W = plot.clientWidth || 800, H = plot.clientHeight || 260, L = 34, B = 24, T = 8;
    const max = Math.max(1, ...rows.map((d) => active.reduce((a, s) => a + (d[s.key] || 0), 0)));
    const step = niceStep(max), top = Math.ceil(max / step) * step;
    const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Grafiek per dag" });
    const grid = svgEl("g", { class: "grid" });
    for (let v = 0; v <= top; v += step) {
      const y = T + (H - T - B) * (1 - v / top);
      grid.append(svgEl("line", { x1: L, x2: W, y1: y, y2: y }));
      const tx = svgEl("text", { x: L - 8, y: y + 4, "text-anchor": "end" }); tx.textContent = num(v); grid.append(tx);
    }
    svg.append(grid);
    const n = rows.length, cw = (W - L) / Math.max(n, 1), bw = Math.max(2, Math.min(28, cw * 0.62));
    const hover = svgEl("rect", { class: "hover-col", y: T, height: H - T - B, width: cw, x: -999 });
    svg.append(hover);
    const axis = svgEl("g", { class: "axis" });
    const every = Math.ceil(n / Math.max(1, Math.floor((W - L) / 64)));
    rows.forEach((d, i) => {
      let y = H - B;
      const x = L + i * cw + (cw - bw) / 2;
      for (const s of active) {
        const v = d[s.key] || 0;
        if (!v) continue;
        const h = (H - T - B) * (v / top);
        y -= h;
        svg.append(svgEl("rect", { class: "bar", x, y, width: bw, height: Math.max(h - 1, 1), rx: Math.min(4, bw / 3), fill: s.color }));
      }
      if (i % every === 0) {
        const t = svgEl("text", { x: L + i * cw + cw / 2, y: H - 6, "text-anchor": "middle" });
        t.textContent = range.days === 365 ? fmtDay(d.label, { month: "short" }) : fmtDay(d.label, { day: "numeric", month: range.days === 7 ? "short" : undefined }).replace(/\s+$/, "");
        axis.append(t);
      }
    });
    svg.append(axis);
    plot.prepend(svg);

    // tooltip
    const tip = $("chTip");
    const show = (clientX) => {
      const box = plot.getBoundingClientRect();
      const i = Math.min(n - 1, Math.max(0, Math.floor(((clientX - box.left) * (W / box.width) - L) / cw)));
      const d = rows[i];
      if (!d) return;
      hover.setAttribute("x", L + i * cw);
      tip.replaceChildren(el("b", null, d.to ? `Week van ${fmtDay(d.label, { day: "numeric", month: "short" })}` : fmtDay(d.label, { weekday: "short", day: "numeric", month: "long" })));
      for (const s of SERIES) {
        const row = el("div"), name = el("span"), dot = el("i");
        dot.style.setProperty("--c", s.color);
        name.append(dot, document.createTextNode(s.label));
        row.append(name, el("strong", null, num(d[s.key])));
        tip.append(row);
      }
      tip.classList.remove("hidden");
      const px = (L + i * cw + cw / 2) * (box.width / W);
      tip.style.left = Math.min(Math.max(px - 80, 0), box.width - 170) + "px";
    };
    plot.onmousemove = (e) => show(e.clientX);
    plot.ontouchstart = plot.ontouchmove = (e) => show(e.touches[0].clientX);
    plot.onmouseleave = () => { tip.classList.add("hidden"); hover.setAttribute("x", -999); };

    // totalen van de periode
    const sums = $("chSum");
    sums.replaceChildren();
    for (const s of SERIES) {
      const box = el("div");
      box.append(el("b", null, num((stats.per_day || []).reduce((a, x) => a + (x[s.key] || 0), 0))), document.createTextNode(s.label));
      sums.append(box);
    }
  }
  function niceStep(max) {
    const raw = max / 4, pow = Math.pow(10, Math.floor(Math.log10(raw)));
    const n = raw / pow;
    return Math.max(1, (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * pow);
  }
  let resizeTimer;
  window.addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(renderChart, 120); });

  const REASONS = { honeypot: "Honeypot ingevuld", too_fast: "Te snel ingevuld", rate_limit: "Te veel vanaf één netwerk", disposable: "Wegwerpadres", other: "Overig" };
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
  function renderDists() {
    const b = stats.bots_7d || {};
    dist($("bots"), Object.entries(b).sort((x, y) => y[1] - x[1]).map(([k, n]) => [REASONS[k] || k, n]), "#FFB547",
      `Geen bots deze week. ${num(stats.signups_allowed_7d)} gewone aanmeldingen.`);
    const order = ["0", "1-5", "6-15", "16-30", "31+"], c = stats.cards_per_account || {};
    dist($("perAccount"), order.filter((k) => c[k]).map((k) => [k === "0" ? "Nog geen kaarten" : `${k} kaarten`, c[k]]), "#6A5CFF", "Nog geen accounts.");
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
    if (!(await ask("Overal uitloggen?", "Alle sessies vervallen, ook in de app Pasr Beheer op je andere apparaten. Daar moet je opnieuw inloggen en pushmeldingen opnieuw aanzetten.", "Overal uitloggen"))) return;
    try { await api("logout_all"); signOut("Je bent overal uitgelogd."); }
    catch (err) { $("setMsg").textContent = err.message; }
  });

  // ---- start ----
  function start() {
    $("login").classList.add("hidden");
    $("app").classList.remove("hidden");
    const want = (location.hash || "").slice(1);
    setTab(["overview", "accounts", "settings"].includes(want) ? want : "overview");
  }
  if (token && expires > Date.now() && URL_ADMIN) start(); else signOut();
  // sessie verloopt: terug naar inloggen
  setInterval(() => { if (token && expires && expires <= Date.now()) signOut("Je sessie is verlopen. Log opnieuw in."); }, 60_000);
})();
