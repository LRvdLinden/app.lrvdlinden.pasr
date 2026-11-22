// Pasr voor ondernemers op pasr.nl/zakelijk: dashboard (kaarten, medewerkers, instellingen, log), join-pagina,
// web-scanner (eigenaar en medewerkers, aantal-kiezer, afkoeltijd, ongedaan maken), uitnodiging en flyer.
// Gewone fetch naar de Pasr-server (geen SDK). Alles via databasefuncties (pasr_business_*); de tabellen zelf zijn dicht.
(function () {
  "use strict";
  var cfg = window.PASR_ACCOUNT || {};
  var ready = !!(cfg.url && cfg.key);
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var APP_STORE = "https://apps.apple.com/nl/app/pasr-klantenkaarten/id6829229123";
  var SESSION_KEY = "pasr.zakelijk.session";
  var ICON = {
    stamp: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>',
    gift: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="8" width="18" height="13" rx="2"/><path d="M12 8v13M3 12h18M12 8S10.5 3 7.5 4.5 9 8 12 8zm0 0s1.5-5 4.5-3.5S15 8 12 8z"/></svg>',
    qr: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 20h4v-3"/></svg>',
    link: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/></svg>',
    edit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg>',
    print: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 9V3h10v6M7 18H4v-7h16v7h-3M7 14h10v7H7z"/></svg>',
    users: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5M16 4.8a3.5 3.5 0 0 1 0 6.4M18.5 14.8c1.6.9 2.6 2.6 3 5.2"/></svg>',
    scan: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M7 12h10"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    download: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 4v11M7 10.5l5 5 5-5M4 20h16"/></svg>',
  };

  // ---------------------------------------------------------------- hulpjes
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function mixHex(hex, to, part) {
    var out = "#";
    for (var i = 1; i < 7; i += 2) { var v = Math.round(parseInt(hex.substr(i, 2), 16) * (1 - part) + to * part); out += (v < 16 ? "0" : "") + v.toString(16); }
    return out;
  }
  function luminance(hex) {
    var v = parseInt(hex.replace("#", ""), 16);
    var ch = [(v >> 16) & 255, (v >> 8) & 255, v & 255].map(function (x) { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); });
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
  }
  function imgSrc(b64) { return b64 ? "data:image/" + (b64.indexOf("/9j/") === 0 ? "jpeg" : "png") + ";base64," + b64 : ""; }
  function qrSvg(text) {
    var q = qrcode(0, "M"); q.addData(text); q.make();
    return q.createSvgTag({ cellSize: 6, margin: 2, scalable: true });
  }
  function joinUrl(id) { return "https://pasr.nl/zakelijk/kaart/#" + id; }
  function nlDate(iso) { return iso ? new Date(iso).toLocaleDateString("nl-NL", { day: "numeric", month: "short", year: "numeric" }) : "—"; }
  function setMsg(el, text, good) { if (el) { el.textContent = text || ""; el.className = "zk-msg " + (text ? (good ? "good" : "bad") : ""); } }
  function toast(text) { var t = document.createElement("div"); t.className = "zk-modal"; t.style.background = "transparent"; t.style.pointerEvents = "none"; t.innerHTML = '<div style="width:auto;background:#17162A;color:#fff;align-self:end;margin-bottom:30px;padding:12px 18px">' + esc(text) + "</div>"; document.body.appendChild(t); setTimeout(function () { t.remove(); }, 2200); }
  function copy(text) {
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(function () { toast("Gekopieerd"); }, function () { prompt("Kopieer de link", text); });
    else prompt("Kopieer de link", text);
  }

  /** De stempelkaart als HTML. card = {name, business, city, logo, color, stamps_total, reward}; count = gezette stempels of null. */
  function stampCard(card, count, extraClass) {
    var color = /^#[0-9a-f]{6}$/i.test(card.color || "") ? card.color : "#6A5CFF";
    var total = Math.max(2, Math.min(30, Number(card.stamps_total) || 10));
    var n = count == null ? 0 : Math.max(0, Number(count) || 0);
    var shown = n % total === 0 && n > 0 ? total : n % total;
    var cols = total <= 5 ? total : total <= 10 ? 5 : total <= 12 ? 6 : total <= 21 ? 7 : 8;
    // tekstkleur van de zaak (huisstijl van de website) als die er is, anders op contrast
    var ink = /^#000000$/i.test(card.text_color || "") ? true : /^#FFFFFF$/i.test(card.text_color || "") ? false : luminance(color) > 0.45;
    var mono = String(card.name || "?").split(" ").slice(0, 2).map(function (w) { return w[0] || ""; }).join("").toUpperCase();
    var stamps = "";
    for (var i = 0; i < total; i++) {
      var on = i < shown, last = i === total - 1;
      stamps += '<span class="sc-stamp' + (on ? " on" : "") + (last && !on ? " gift" : "") + '" style="--i:' + i + '">' + (on ? ICON.stamp : last ? ICON.gift : "") + "</span>";
    }
    var bg = "linear-gradient(135deg, " + mixHex(color, 255, 0.16) + ", " + color + " 55%, " + mixHex(color, 0, 0.22) + ")";
    var left = count == null ? total + " stempels" : (n >= total ? "Beloning klaar" : (total - shown) + " te gaan");
    return '<div class="sc' + (ink ? " ink" : "") + (extraClass ? " " + extraClass : "") + '" style="--c:' + color + ";background:" + bg + ";--cols:" + cols + '">' +
      '<div class="sc-head"><span class="sc-logo">' + (card.logo ? '<img src="' + imgSrc(card.logo) + '" alt="">' : esc(mono)) + "</span>" +
      '<span class="sc-title"><span class="sc-name">' + esc(card.name) + '</span><span class="sc-biz">' + esc([card.business, card.city].filter(Boolean).join(" · ")) + "</span></span>" +
      '<span class="sc-kind">Stempelkaart</span></div>' +
      '<div class="sc-stamps" role="img" aria-label="' + shown + " van " + total + ' stempels">' + stamps + "</div>" +
      '<div class="sc-reward"><span>' + esc(card.reward) + "</span><span>" + esc(left) + "</span></div></div>";
  }
  window.PasrStampCard = stampCard;

  // ---------------------------------------------------------------- server
  function loadSession() { try { return JSON.parse(localStorage.getItem(SESSION_KEY) || "null"); } catch (e) { return null; } }
  function saveSession(s) { try { s ? localStorage.setItem(SESSION_KEY, JSON.stringify(s)) : localStorage.removeItem(SESSION_KEY); } catch (e) { /* privévenster */ } }
  var session = loadSession();

  async function http(path, body, token, method) {
    var headers = { "Content-Type": "application/json", apikey: cfg.key };
    if (token) headers.Authorization = "Bearer " + token;
    var res = await fetch(cfg.url + "/" + path, { method: method || "POST", headers: headers, body: body === undefined ? undefined : JSON.stringify(body), cache: "no-store", referrerPolicy: "no-referrer" });
    var data = null;
    try { data = await res.json(); } catch (e) { /* leeg */ }
    if (!res.ok) {
      var err = new Error((data && (data.message || data.msg || data.error_description)) || "error");
      err.status = res.status; err.code = (data && (data.error_code || data.code)) || "";
      // scanner- en medewerkerfuncties (zakelijk 1.0): message is al een nette zin, hint de vaste code
      err.hint = (data && data.hint) || ""; err.details = (data && data.details) || "";
      throw err;
    }
    return data;
  }
  function keep(s) {
    session = { access_token: s.access_token, refresh_token: s.refresh_token, expires_at: Date.now() + (s.expires_in || 3600) * 1000, email: s.user && s.user.email };
    saveSession(session);
  }
  async function token() {
    if (!session) return null;
    if (Date.now() < session.expires_at - 60000) return session.access_token;
    try { keep(await http("auth/v1/token?grant_type=refresh_token", { refresh_token: session.refresh_token })); return session.access_token; }
    catch (e) { session = null; saveSession(null); return null; }
  }
  async function rpc(name, args, auth) {
    var t = auth ? await token() : null;
    if (auth && !t) { var e = new Error("not signed in"); e.status = 401; throw e; }
    return http("rest/v1/rpc/" + name, args || {}, t);
  }
  function nice(e) {
    var m = String((e && e.message) || "");
    if (e && e.hint && /\s/.test(m) && e.hint !== "not_signed_in") return m;
    if (e && e.status === 429 || /rate_limited/.test(m)) return "Even wachten: er zijn te veel pogingen gedaan. Probeer het over een paar minuten opnieuw.";
    if (/invalid login|invalid_credentials/i.test(m) || e.code === "invalid_credentials") return "E-mailadres of wachtwoord klopt niet.";
    if (/email not confirmed|not_confirmed/i.test(m) || e.code === "email_not_confirmed") return "Bevestig eerst je e-mailadres met de link in de mail.";
    if (e.code === "user_already_exists" || e.code === "email_exists") return "Er is al een account met dit e-mailadres. Log in.";
    if (e.code === "weak_password") return "Kies een wachtwoord van minstens 8 tekens.";
    if (/permanent email/i.test(m)) return "Gebruik een vast e-mailadres; tijdelijke adressen werken niet.";
    if (/not_approved/.test(m)) return "Je zaak is nog niet goedgekeurd. Je krijgt bericht zodra dat zo is.";
    if (/other_business/.test(m)) return "Deze kaart hoort bij een andere zaak.";
    if (/not_found/.test(m)) return "Niet gevonden. Controleer de code of de link.";
    if (/not_enough/.test(m)) return "Nog niet genoeg stempels voor de beloning.";
    if (/too_soon/.test(m)) return "Net al een stempel gezet. Wacht een paar seconden.";
    if (e && e.hint === "not_signed_in") return "Je bent uitgelogd. Log opnieuw in.";
    if (/card_limit/.test(m)) return "Je kunt hoogstens 5 kaarten maken.";
    if (/bad_logo/.test(m)) return "Dit logo werkt niet. Kies een PNG of JPEG.";
    if (/blocked/.test(m)) return "Je zaak is geblokkeerd. Mail support@pasr.nl als dat niet klopt.";
    if (e.status === 401) return "Je bent uitgelogd. Log opnieuw in.";
    return "Er ging iets mis. Probeer het opnieuw.";
  }

  // ---------------------------------------------------------------- dashboard
  var dash = { me: null, view: "list", edit: null };

  function dashRoot() { return $("#zk-app"); }

  function loginView(mode) {
    var shown = performance.now();
    var signup = mode === "signup", forgot = mode === "forgot";
    dashRoot().innerHTML =
      '<section class="auth" style="max-width:480px"><div class="badge">' + ICON.stamp + "</div>" +
      "<h1>" + (signup ? "Account maken" : forgot ? "Wachtwoord vergeten" : "Inloggen voor ondernemers") + "</h1>" +
      "<p>" + (signup ? "Gratis. Met je account meld je je zaak aan en beheer je je stempelkaarten." : forgot ? "Je krijgt een mail om een nieuw wachtwoord te kiezen." : "Log in met je Pasr-account. Nog geen account? Maak er gratis een.") + "</p>" +
      '<form id="zkAuth" class="zk-form" novalidate>' +
      (signup ? '<label>Je voornaam<input id="zkName" autocomplete="given-name" maxlength="40" required></label>' : "") +
      '<label>E-mailadres<input id="zkEmail" type="email" autocomplete="email" required></label>' +
      (forgot ? "" : '<label>Wachtwoord<input id="zkPw" type="password" autocomplete="' + (signup ? "new-password" : "current-password") + '" minlength="8" required></label>') +
      (signup ? '<div class="hp-field" aria-hidden="true"><label>Laat dit veld leeg<input type="text" id="zkWebsite" tabindex="-1" autocomplete="off"></label></div>' : "") +
      '<button class="zk-btn" type="submit">' + (signup ? "Account maken" : forgot ? "Stuur mail" : "Inloggen") + '</button><p class="zk-msg" id="zkMsg" role="status"></p></form>' +
      '<p class="switch" style="display:flex;gap:16px;flex-wrap:wrap;justify-content:center;margin-top:14px">' +
      (signup || forgot ? '<a href="#inloggen">Ik heb al een account</a>' : '<a href="#account">Account maken</a><a href="#vergeten">Wachtwoord vergeten?</a>') + "</p></section>";
    $("#zkAuth").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var msg = $("#zkMsg"), btn = ev.target.querySelector("button");
      var email = $("#zkEmail").value.trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return setMsg(msg, "Dit e-mailadres klopt niet.");
      btn.disabled = true;
      try {
        if (forgot) {
          await http("auth/v1/recover?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: email });
          setMsg(msg, "Als er een account met dit adres is, staat er nu een mail in je inbox.", true);
        } else if (signup) {
          var name = $("#zkName").value.replace(/[<>]/g, "").replace(/\s+/g, " ").trim().slice(0, 40), pw = $("#zkPw").value;
          if (!name) { btn.disabled = false; return setMsg(msg, "Vul je voornaam in."); }
          if (pw.length < 8) { btn.disabled = false; return setMsg(msg, "Kies een wachtwoord van minstens 8 tekens."); }
          var data = { first_name: name, fill_ms: Math.round(performance.now() - shown), app: "zakelijk" };
          var hp = $("#zkWebsite").value; if (hp) data.hp = hp;
          await http("auth/v1/signup?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: email, password: pw, data: data });
          dashRoot().innerHTML = '<section class="auth ok"><div class="badge">' + ICON.stamp + "</div><h1>Check je mail</h1><p>We hebben een mail gestuurd naar " + esc(email) +
            '. Tik op de knop in die mail om je e-mailadres te bevestigen. Kom daarna terug en log hier in om je zaak aan te melden.</p><p><a class="zk-btn" href="#inloggen">Naar inloggen</a></p></section>';
        } else {
          keep(await http("auth/v1/token?grant_type=password", { email: email, password: $("#zkPw").value }));
          if (dash.afterLogin) return dash.afterLogin();
          location.hash = "";
          await refresh();
        }
      } catch (e) { setMsg(msg, nice(e)); } finally { btn.disabled = false; }
    });
  }

  function registerView(b) {
    dashRoot().innerHTML =
      '<div class="zk-top"><div><span class="zk-kicker">Pasr voor ondernemers</span><h1>' + (b ? "Gegevens van je zaak" : "Meld je zaak aan") + "</h1></div>" + logoutBtn() + "</div>" +
      '<div class="zk-panel" style="max-width:640px"><p>' + (b ? "Pas de gegevens van je zaak aan." : "Vul de naam en plaats van je zaak in. Wij bekijken je aanmelding en keuren hem meestal binnen een werkdag goed. Je kunt alvast je stempelkaart ontwerpen.") + "</p>" +
      '<form id="zkReg" class="zk-form" novalidate>' +
      '<label>Naam van je zaak<input id="rName" maxlength="60" required value="' + esc(b && b.name) + '"></label>' +
      '<label>Plaats<input id="rCity" maxlength="60" value="' + esc(b && b.city) + '"></label>' +
      '<label>Website (optioneel; we nemen er je logo en kleur van over)<input id="rWeb" maxlength="200" inputmode="url" placeholder="jouwzaak.nl" value="' + esc(b && b.website) + '"></label>' +
      '<label>Wat voor zaak is het? (optioneel)<textarea id="rNote" rows="3" maxlength="300" placeholder="Bijvoorbeeld: koffiebar met lunch, 2 vestigingen">' + esc(b && b.note) + "</textarea></label>" +
      '<p class="small" style="font-size:14px;margin:0">De naam en plaats komen op je stempelkaart. Je e-mailadres blijft privé. Lees ook onze <a href="/privacy/#stempelkaarten-van-ondernemers">privacyverklaring</a>.</p>' +
      '<div class="row"><button class="zk-btn" type="submit">' + (b ? "Opslaan" : "Aanmelden") + "</button>" + (b ? '<button class="zk-btn ghost" type="button" id="rBack">Terug</button>' : "") + '</div><p class="zk-msg" id="rMsg" role="status"></p></form></div>';
    bindLogout();
    if (b) $("#rBack").addEventListener("click", function () { dash.view = "list"; render(); });
    $("#zkReg").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        var newWeb = ($("#rWeb").value || "").trim(), oldWeb = (b && b.website) || "";
        await rpc("pasr_business_register", { p_name: $("#rName").value, p_city: $("#rCity").value, p_website: newWeb || null, p_note: $("#rNote").value || null }, true);
        dash.view = "list"; await refresh();
        if (b && newWeb && newWeb !== oldWeb && (dash.me.cards || []).length) toast("Nieuwe website: open een kaart en tik op Huisstijl ophalen");
      } catch (e) { setMsg($("#rMsg"), /bad_name/.test(e.message) ? "Vul de naam van je zaak in." : nice(e)); btn.disabled = false; }
    });
  }

  function logoutBtn() { return '<div class="zk-actions"><a class="zk-btn ghost sm" href="/zakelijk/scan/">' + ICON.scan + 'Scanner</a><button class="zk-btn ghost sm" type="button" id="zkOut">Uitloggen</button></div>'; }
  // Tabs voor de eigenaar: Kaarten, Medewerkers, Instellingen, Log.
  var TABS = [["list", "Kaarten"], ["staff", "Medewerkers"], ["settings", "Instellingen"], ["log", "Log"]];
  function tabs() {
    return '<nav class="zk-tabs" aria-label="Dashboard">' + TABS.map(function (t) {
      return '<button type="button" class="zk-btn ghost sm" data-tab="' + t[0] + '" aria-pressed="' + (dash.view === t[0]) + '">' + t[1] + "</button>";
    }).join("") + "</nav>";
  }
  function bindTabs() {
    dashRoot().querySelectorAll(".zk-tabs button").forEach(function (b) {
      b.addEventListener("click", function () { dash.view = b.dataset.tab; render(); });
    });
  }
  function bizTop(kicker, title) {
    return '<div class="zk-top"><div><span class="zk-kicker">' + esc(kicker) + "</span><h1>" + esc(title) + "</h1></div>" + logoutBtn() + "</div>" + tabs();
  }
  function timeNl(iso) { return iso ? new Date(iso).toLocaleString("nl-NL", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—"; }

  // ---- medewerkers ----
  async function staffView() {
    var b = dash.me.business;
    dashRoot().innerHTML = bizTop(b.name, "Medewerkers") +
      '<div class="zk-panel"><h3>Medewerker uitnodigen</h3><p style="margin:0 0 10px">Een medewerker logt in met een eigen Pasr-account en kan alleen scannen: stempels geven, belonen en ongedaan maken. Kaarten, instellingen en de log blijven van jou.</p>' +
      '<form id="stInv" class="zk-form" novalidate><label>Naam<input id="stName" maxlength="60" required placeholder="bijv. Sanne"></label>' +
      '<label>E-mailadres (optioneel, alleen ter herkenning)<input id="stMail" type="email" maxlength="200" autocomplete="off"></label>' +
      '<div class="row"><button class="zk-btn" type="submit">' + ICON.plus + 'Uitnodiging maken</button></div><p class="zk-msg" id="stMsg" role="status"></p></form><div id="stLink"></div></div>' +
      '<div class="zk-panel" id="stList">Laden…</div>';
    bindLogout(); bindTabs();
    $("#stInv").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        var r = await rpc("pasr_business_staff_invite", { p_business: b.id, p_name: $("#stName").value, p_email: $("#stMail").value || null }, true);
        $("#stName").value = ""; $("#stMail").value = "";
        $("#stLink").innerHTML = '<div class="zk-qr" style="margin-top:12px"><div class="qr">' + qrSvg(r.link) + '</div><div><p style="margin:0 0 6px">Stuur deze link naar je medewerker. Hij werkt 14 dagen en één keer.</p><div class="zk-link">' + esc(r.link) + '</div>' +
          '<div class="zk-actions" style="margin-top:10px"><button class="zk-btn sm" type="button" id="stCopy">' + ICON.link + "Kopieer link</button>" +
          (navigator.share ? '<button class="zk-btn ghost sm" type="button" id="stShare">Delen</button>' : "") + "</div></div></div>";
        $("#stCopy").addEventListener("click", function () { copy(r.link); });
        var sh = $("#stShare"); if (sh) sh.addEventListener("click", function () { navigator.share({ title: "Uitnodiging " + b.name, text: "Je bent uitgenodigd om stempels te geven bij " + b.name + " met Pasr Zakelijk.", url: r.link }).catch(function () {}); });
        loadStaff();
      } catch (e) { setMsg($("#stMsg"), nice(e)); }
      btn.disabled = false;
    });
    async function loadStaff() {
      try {
        var list = await rpc("pasr_business_staff_list", { p_business: b.id }, true);
        $("#stList").innerHTML = "<h3>Wie kan scannen</h3>" + '<div style="overflow-x:auto"><table class="zk-table"><thead><tr><th>Naam</th><th>Rol</th><th>Status</th><th></th></tr></thead><tbody>' +
          list.map(function (x) {
            var st = x.revoked ? "Ingetrokken " + nlDate(x.revoked_at) : x.pending ? (x.expired ? "Uitnodiging verlopen" : "Uitnodiging open") : "Actief sinds " + nlDate(x.accepted_at || x.created_at);
            return "<tr><td>" + esc(x.name || (x.role === "owner" ? "Jij" : "—")) + (x.email ? '<br><small style="color:#6B6880">' + esc(x.email) + "</small>" : "") + "</td><td>" + (x.role === "owner" ? "Eigenaar" : "Medewerker") + "</td><td>" + esc(st) + "</td><td>" +
              (x.role !== "owner" && !x.revoked ? '<button class="zk-btn ghost sm" type="button" data-revoke="' + esc(x.id) + '">' + (x.pending ? "Intrekken" : "Toegang intrekken") + "</button>" : "") + "</td></tr>";
          }).join("") + "</tbody></table></div>";
        $("#stList").querySelectorAll("button[data-revoke]").forEach(function (btn) {
          btn.addEventListener("click", async function () {
            if (!confirm("Toegang intrekken? Deze medewerker kan dan niet meer scannen.")) return;
            btn.disabled = true;
            try { await rpc("pasr_business_staff_revoke", { p_staff: btn.dataset.revoke }, true); toast("Ingetrokken"); loadStaff(); }
            catch (e) { btn.disabled = false; toast(nice(e)); }
          });
        });
      } catch (e) { $("#stList").textContent = nice(e); }
    }
    loadStaff();
  }

  // ---- instellingen: afkoeltijd, max per scan, vindbaar in Pasr, adres ----
  function settingsView() {
    var b = dash.me.business;
    dashRoot().innerHTML = bizTop(b.name, "Instellingen") +
      '<form id="setForm" class="zk-panel zk-form" novalidate style="max-width:640px">' +
      '<label>Afkoeltijd: zo lang na een stempel krijgt dezelfde klant geen nieuwe stempel (minuten, 0 = uit)<input id="setCool" type="number" inputmode="numeric" min="0" max="1440" value="' + esc(b.cooldown_minutes == null ? 5 : b.cooldown_minutes) + '"></label>' +
      '<label>Hoogstens zoveel stempels per scan (1 tot 30)<input id="setMax" type="number" inputmode="numeric" min="1" max="30" value="' + esc(b.max_per_scan == null ? 10 : b.max_per_scan) + '"></label>' +
      '<label class="check"><input id="setListed" type="checkbox"' + (b.listed === false ? "" : " checked") + "> Vindbaar in Pasr: klanten vinden je stempelkaart in de app bij Kaart toevoegen › Stempelkaart</label>" +
      '<label>Adres (optioneel, voor "In de buurt" in Pasr)<input id="setAddr" maxlength="200" autocomplete="street-address" placeholder="Straat en huisnummer, plaats" value="' + esc(b.address || "") + '"></label>' +
      '<p style="font-size:14px;margin:0">' + (b.lat != null ? "Locatie bekend: je kaart verschijnt bij In de buurt." : "De locatie zet je met de app Pasr Zakelijk (Instellingen › Adres); zonder locatie ben je wel vindbaar op naam en plaats.") + "</p>" +
      '<div class="row"><button class="zk-btn" type="submit">Opslaan</button></div><p class="zk-msg" id="setMsg" role="status"></p></form>' +
      '<div class="zk-panel" style="max-width:640px"><h3>Gegevens van je zaak</h3><p style="margin:0">' + esc(b.name) + (b.city ? " · " + esc(b.city) : "") + ' · <a href="#" id="zkEditBiz">wijzigen</a></p></div>';
    bindLogout(); bindTabs();
    $("#zkEditBiz").addEventListener("click", function (e) { e.preventDefault(); registerView(b); });
    $("#setForm").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var cd = Number($("#setCool").value), mx = Number($("#setMax").value);
      if (!Number.isInteger(cd) || cd < 0 || cd > 1440) return setMsg($("#setMsg"), "Afkoeltijd moet tussen 0 en 1440 minuten liggen.");
      if (!Number.isInteger(mx) || mx < 1 || mx > 30) return setMsg($("#setMsg"), "Max per scan moet tussen 1 en 30 liggen.");
      var addr = $("#setAddr").value.replace(/\s+/g, " ").trim();
      var settings = { cooldown_minutes: cd, max_per_scan: mx, listed: $("#setListed").checked };
      if (addr !== (b.address || "")) settings.address = addr || null;   // ander adres: de oude locatie vervalt
      var btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        var nb = await rpc("pasr_business_settings_save", { p_business: b.id, p_settings: settings }, true);
        dash.me.business = Object.assign({}, b, nb); setMsg($("#setMsg"), "Opgeslagen.", true);
      } catch (e) { setMsg($("#setMsg"), nice(e)); }
      btn.disabled = false;
    });
  }

  // ---- log: wie gaf wanneer welke stempel (niet te wissen) ----
  var KIND = { join: "Nieuw lid", claim: "Kaart naar de app", stamp: "Stempel", redeem: "Beloning ingewisseld", undo: "Ongedaan gemaakt" };
  async function logView() {
    var b = dash.me.business;
    dashRoot().innerHTML = bizTop(b.name, "Log") + '<div class="zk-panel" id="lgStats"></div><div class="zk-panel" id="lgBody">Laden…</div>';
    bindLogout(); bindTabs();
    try {
      var st = await rpc("pasr_business_stats", { p_business: b.id, p_days: 30 }, true);
      var max = 1; (st.days || []).forEach(function (d) { if (d.stamps > max) max = d.stamps; });
      $("#lgStats").innerHTML = "<h3>Laatste 30 dagen</h3><div class=\"zk-stats\"><span class=\"zk-stat\"><b>" + st.totals.stamps + "</b><small>stempels</small></span><span class=\"zk-stat\"><b>" + st.totals.rewards + "</b><small>beloningen</small></span><span class=\"zk-stat\"><b>" + st.totals.new_members + "</b><small>nieuwe leden</small></span><span class=\"zk-stat\"><b>" + st.totals.members + "</b><small>leden totaal</small></span></div>" +
        '<div class="zk-bars" aria-hidden="true">' + (st.days || []).map(function (d) { return '<i style="height:' + Math.max(2, Math.round(d.stamps / max * 100)) + '%" title="' + d.day + ": " + d.stamps + ' stempels"></i>'; }).join("") + "</div>";
    } catch (e) { $("#lgStats").textContent = nice(e); }
    try {
      var r = await rpc("pasr_business_log", { p_business: b.id, p_limit: 300 }, true), ev = r.events || [];
      $("#lgBody").innerHTML = "<h3>Log</h3>" + (ev.length ? '<div style="overflow-x:auto"><table class="zk-table"><thead><tr><th>Wanneer</th><th>Wat</th><th>Kaart</th><th>Klant</th><th>Door</th></tr></thead><tbody>' +
        ev.map(function (x) {
          var what = KIND[x.kind] || x.kind;
          if (x.kind === "stamp") what = x.amount === 1 ? "1 stempel" : x.amount + " stempels";
          if (x.stamps_after != null && x.kind !== "join" && x.kind !== "claim") what += " (" + x.stamps_before + " → " + x.stamps_after + ")";
          var who = x.by_role === "customer" ? "Klant" : esc(x.by_name || "—") + (x.by_role === "staff" ? " (medewerker)" : "") + (x.device ? '<br><small style="color:#6B6880">' + esc(x.device) + "</small>" : "");
          return "<tr" + (x.undone ? ' style="text-decoration:line-through;opacity:.6"' : "") + "><td>" + timeNl(x.at) + "</td><td>" + esc(what) + "</td><td>" + esc(x.card_name || "verwijderde kaart") + "</td><td>…" + esc(x.member_suffix || "") + "</td><td>" + who + "</td></tr>";
        }).join("") + "</tbody></table></div>" : '<p class="zk-empty">Nog niets gebeurd.</p>') +
        '<p style="font-size:14px;margin:12px 0 0">De log kan niet worden gewist of aangepast, ook niet door jou. Doorgestreept = ongedaan gemaakt.</p>';
    } catch (e) { $("#lgBody").textContent = nice(e); }
  }

  // ---- medewerker (geen eigen zaak): alleen de scanner ----
  function staffOnlyView() {
    var list = (dash.me.businesses || []).filter(function (x) { return x.role === "staff"; });
    dashRoot().innerHTML = '<div class="zk-top"><div><span class="zk-kicker">Medewerker</span><h1>' + esc(list.map(function (x) { return x.name; }).join(", ")) + "</h1></div>" + logoutBtn() + "</div>" +
      '<div class="zk-panel" style="max-width:640px"><p>Je bent medewerker en kunt stempels geven en belonen met de scanner, of met de app Pasr Zakelijk.</p><p><a class="zk-btn" href="/zakelijk/scan/">' + ICON.scan + "Open de scanner</a></p>" +
      '<p style="font-size:14px;margin:0">Heb je zelf een zaak? <a href="#" id="zkOwn">Meld je zaak aan</a>.</p></div>';
    bindLogout();
    $("#zkOwn").addEventListener("click", function (e) { e.preventDefault(); registerView(null); });
  }
  function bindLogout() {
    var b = $("#zkOut"); if (!b) return;
    b.addEventListener("click", async function () {
      try { var t = await token(); if (t) await http("auth/v1/logout", {}, t); } catch (e) { /* toch uitloggen */ }
      session = null; saveSession(null); dash.me = null; render();
    });
  }

  var STATUS = { pending: ["Wacht op goedkeuring", ""], approved: ["Goedgekeurd", "approved"], blocked: ["Geblokkeerd", "blocked"] };

  function listView() {
    var b = dash.me.business, cards = dash.me.cards || [];
    var st = STATUS[b.status] || STATUS.pending;
    var html = '<div class="zk-top"><div><span class="zk-status ' + st[1] + '">' + st[0] + "</span><h1>" + esc(b.name) + '</h1><p style="margin:4px 0 0">' + esc(b.city || "") +
      ' · <a href="#" id="zkEditBiz">gegevens wijzigen</a></p></div>' + logoutBtn() + "</div>" + tabs();
    if (b.status === "pending") html += '<div class="zk-panel"><h3>Bijna klaar</h3><p style="margin:0">We bekijken je aanmelding. Ontwerp alvast je stempelkaart; zodra je zaak is goedgekeurd zet je hem online en kun je stempels geven.</p></div>';
    if (b.status === "blocked") html += '<div class="zk-panel"><h3>Je zaak is geblokkeerd</h3><p style="margin:0">Je kaarten zijn offline. Mail <a href="mailto:support@pasr.nl">support@pasr.nl</a> als dat niet klopt.</p></div>';
    if (!cards.length) {
      html += '<div class="zk-panel zk-empty"><h2>Je eerste stempelkaart</h2><p>Kies een naam, je logo en kleur, hoeveel stempels er op een kaart gaan en wat je klant daarvoor krijgt.</p><button class="zk-btn" id="zkNew" type="button">' + ICON.plus + "Kaart ontwerpen</button></div>";
    } else {
      html += '<div class="zk-cards">' + cards.map(function (c) {
        return '<article class="zk-card" data-id="' + esc(c.id) + '">' + stampCard(c, null) + "<div>" +
          '<div class="row" style="display:flex;gap:10px;align-items:center;flex-wrap:wrap"><h2 style="margin:0">' + esc(c.name) + '</h2><span class="zk-pill' + (c.published ? " on" : "") + '">' + (c.published ? "Online" : "Concept") + "</span></div>" +
          '<p style="margin:4px 0 0">' + esc(c.stamps_total) + " stempels voor " + esc(c.reward) + "</p>" +
          '<div class="zk-stats"><span class="zk-stat"><b>' + (c.members || 0) + '</b><small>leden</small></span><span class="zk-stat"><b>' + (c.stamps || 0) + '</b><small>stempels</small></span><span class="zk-stat"><b>' + (c.rewards || 0) + "</b><small>beloningen</small></span></div>" +
          '<div class="zk-actions"><button class="zk-btn sm" data-act="edit">' + ICON.edit + "Bewerken</button>" +
          (c.published ? '<button class="zk-btn ghost sm" data-act="share">' + ICON.qr + 'QR en link</button><a class="zk-btn ghost sm" href="/zakelijk/flyer/#' + esc(c.id) + '" target="_blank" rel="noopener">' + ICON.print + "Flyer</a>" : "") +
          '<button class="zk-btn ghost sm" data-act="members">' + ICON.users + "Leden</button></div></div></article>";
      }).join("") + "</div>";
      if (cards.length < 5) html += '<p style="text-align:center;margin-top:18px"><button class="zk-btn ghost" id="zkNew" type="button">' + ICON.plus + "Nog een kaart</button></p>";
    }
    dashRoot().innerHTML = html;
    bindLogout(); bindTabs();
    $("#zkEditBiz").addEventListener("click", function (e) { e.preventDefault(); registerView(b); });
    var nb = $("#zkNew"); if (nb) nb.addEventListener("click", function () { dash.edit = null; dash.view = "edit"; render(); });
    dashRoot().querySelectorAll(".zk-card button[data-act]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var id = btn.closest(".zk-card").dataset.id, card = cards.filter(function (c) { return c.id === id; })[0];
        if (btn.dataset.act === "edit") { dash.edit = card; dash.view = "edit"; render(); }
        if (btn.dataset.act === "share") shareModal(card);
        if (btn.dataset.act === "members") { dash.edit = card; dash.view = "members"; render(); }
      });
    });
  }

  function shareModal(card) {
    var url = joinUrl(card.id), m = document.createElement("div");
    m.className = "zk-modal";
    m.innerHTML = '<div role="dialog" aria-modal="true" aria-label="QR en link"><h2>Laat klanten aansluiten</h2><p>Hang de QR-code bij de kassa of deel de link. Met Pasr opent de kaart in de app; zonder app werkt hij in de browser.</p>' +
      '<div class="zk-qr"><div class="qr" id="mQr">' + qrSvg(url) + '</div><div><div class="zk-link">' + esc(url) + '</div><div class="zk-actions" style="margin-top:10px">' +
      '<button class="zk-btn sm" id="mCopy">' + ICON.link + 'Kopieer link</button><button class="zk-btn ghost sm" id="mPng">' + ICON.download + 'QR als afbeelding</button>' +
      '<a class="zk-btn ghost sm" href="/zakelijk/flyer/#' + esc(card.id) + '" target="_blank" rel="noopener">' + ICON.print + "Flyer printen</a></div></div></div>" +
      '<p style="text-align:right;margin:16px 0 0"><button class="zk-btn ghost" id="mClose">Sluiten</button></p></div>';
    document.body.appendChild(m);
    var close = function () { m.remove(); };
    m.addEventListener("click", function (e) { if (e.target === m) close(); });
    $("#mClose", m).addEventListener("click", close);
    $("#mCopy", m).addEventListener("click", function () { copy(url); });
    $("#mPng", m).addEventListener("click", function () {
      var q = qrcode(0, "M"); q.addData(url); q.make();
      var a = document.createElement("a"); a.href = q.createDataURL(16, 4); a.download = "pasr-qr-" + card.name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + ".gif"; a.click();
    });
  }

  var SWATCHES = ["#6A5CFF", "#17162A", "#E30613", "#FF6B57", "#E2683C", "#F2B705", "#2ED3A6", "#12A77E", "#0A84FF", "#7B4B2A", "#AF52DE", "#FF375F"];

  function editView() {
    var c = dash.edit || { name: "", reward: "", stamps_total: 10, color: "#6A5CFF", logo: null, published: false };
    var b = dash.me.business, approved = b.status === "approved";
    var state = { name: c.name, reward: c.reward, stamps_total: c.stamps_total, color: c.color, logo: c.logo, business: b.name, city: b.city, text_color: c.id ? undefined : null };
    dashRoot().innerHTML =
      '<div class="zk-top"><div><span class="zk-kicker">Stempelkaart</span><h1>' + (c.id ? "Kaart bewerken" : "Nieuwe kaart") + "</h1></div>" + logoutBtn() + "</div>" +
      '<div class="zk-editor"><form id="zkCard" class="zk-panel zk-form" novalidate>' +
      '<label>Naam van de kaart<input id="cName" maxlength="40" placeholder="bijv. Koffiekaart" value="' + esc(c.name) + '" required></label>' +
      '<label>Beloning<input id="cReward" maxlength="80" placeholder="bijv. 1 gratis koffie" value="' + esc(c.reward) + '" required></label>' +
      '<label>Aantal stempels: <output id="cTotOut">' + c.stamps_total + '</output><input id="cTotal" type="range" min="2" max="30" value="' + c.stamps_total + '"></label>' +
      '<label>Kleur<span class="row"><input id="cColor" type="color" value="' + esc(c.color) + '"><span class="swatches">' + SWATCHES.map(function (s) { return '<button type="button" data-c="' + s + '" style="background:' + s + '" aria-label="Kleur ' + s + '"></button>'; }).join("") + "</span></span></label>" +
      '<div class="zk-brand" id="cBrand" role="status"></div>' +
      '<label>Logo (PNG of JPEG, vierkant werkt het best)<span class="row"><input id="cLogo" type="file" accept="image/png,image/jpeg,image/webp"><button type="button" class="zk-btn ghost sm" id="cNoLogo">Geen logo</button></span></label>' +
      '<label class="check"><input id="cPub" type="checkbox"' + (c.published && approved ? " checked" : "") + (approved ? "" : " disabled") + "> Online: klanten kunnen aansluiten" + (approved ? "" : " (kan na goedkeuring)") + "</label>" +
      '<div class="row"><button class="zk-btn" type="submit">Opslaan</button><button class="zk-btn ghost" type="button" id="cBack">Annuleren</button>' + (c.id ? '<button class="zk-btn ghost" type="button" id="cDel" style="margin-left:auto;color:#C2361F">Verwijderen</button>' : "") + '</div><p class="zk-msg" id="cMsg" role="status"></p></form>' +
      '<div class="preview"><div id="cPrev" style="width:100%"></div><p style="font-size:14px;margin:0">Zo ziet je klant de kaart in Pasr en in de browser.</p><div class="zk-actions" id="cDemo"><button class="zk-btn ghost sm" type="button" data-n="0">Leeg</button><button class="zk-btn ghost sm" type="button" data-n="half">Half vol</button><button class="zk-btn ghost sm" type="button" data-n="full">Vol</button></div></div></div>';
    bindLogout();
    var demo = null;
    function draw() {
      var n = demo === "half" ? Math.floor(state.stamps_total / 2) : demo === "full" ? state.stamps_total : demo === 0 ? 0 : null;
      $("#cPrev").innerHTML = stampCard({ name: state.name || "Naam van de kaart", reward: state.reward || "Je beloning", stamps_total: state.stamps_total, color: state.color, logo: state.logo, business: state.business, city: state.city, text_color: state.text_color === undefined ? c.text_color : state.text_color }, n);
    }
    draw();
    // huisstijl van de website (functie business-brand): bij een nieuwe kaart vanzelf, anders met de knop
    async function fetchBrand(auto) {
      var box = $("#cBrand");
      if (!b.website) { box.innerHTML = auto ? "" : '<p class="small">Vul je website in bij <a href="#" id="cBizLink">de gegevens van je zaak</a>, dan nemen we je logo en kleur automatisch over.</p>'; var l = $("#cBizLink"); if (l) l.addEventListener("click", function (e) { e.preventDefault(); registerView(b); }); return; }
      box.innerHTML = '<p class="small">Huisstijl ophalen van ' + esc(b.website.replace(/^https?:\/\//, "").replace(/\/.*$/, "")) + "…</p>";
      try {
        var t = await token();
        var r = await http("functions/v1/business-brand", { business_id: b.id }, t);
        if (r.logo) state.logo = r.logo;
        if (r.color) { state.color = r.color.toUpperCase(); $("#cColor").value = state.color; state.text_color = r.text_color || null; }
        if (r.name && !state.name.trim() && !c.id) { state.name = r.name.slice(0, 40); $("#cName").value = state.name; }
        draw();
        box.innerHTML = '<p class="small"><span><b>Overgenomen van ' + esc(r.domain) + '</b>. Je kunt alles aanpassen.</span> <button type="button" class="zk-btn ghost sm" id="cRebrand">Opnieuw ophalen</button></p>';
      } catch (e) {
        // lukt het niet: neutrale Pasr-kleur en de initiaal; nooit blokkeren
        var why = e.status === 429 ? "Even wachten: je hebt het vaak geprobeerd." : e.message === "bad_url" || e.message === "no_website" ? "Je website klopt niet." : "Je website gaf geen logo of kleur.";
        box.innerHTML = '<p class="small"><span>' + esc(why) + ' Kies zelf een logo en kleur.</span> <button type="button" class="zk-btn ghost sm" id="cRebrand">Opnieuw ophalen</button></p>';
      }
      var rb = $("#cRebrand"); if (rb) rb.addEventListener("click", function () { fetchBrand(false); });
    }
    if (!c.id) fetchBrand(true);
    else $("#cBrand").innerHTML = b.website ? '<p class="small"><button type="button" class="zk-btn ghost sm" id="cRebrand">Huisstijl ophalen van je website</button></p>' : "";
    var rb0 = $("#cRebrand"); if (rb0) rb0.addEventListener("click", function () { fetchBrand(false); });
    $("#cName").addEventListener("input", function (e) { state.name = e.target.value; draw(); });
    $("#cReward").addEventListener("input", function (e) { state.reward = e.target.value; draw(); });
    $("#cTotal").addEventListener("input", function (e) { state.stamps_total = Number(e.target.value); $("#cTotOut").textContent = e.target.value; draw(); });
    $("#cColor").addEventListener("input", function (e) { state.color = e.target.value.toUpperCase(); state.text_color = null; draw(); });
    dashRoot().querySelectorAll(".swatches button").forEach(function (s) { s.addEventListener("click", function () { state.color = s.dataset.c; state.text_color = null; $("#cColor").value = s.dataset.c; draw(); }); });
    $("#cDemo").querySelectorAll("button").forEach(function (s) { s.addEventListener("click", function () { demo = s.dataset.n === "0" ? 0 : s.dataset.n; draw(); }); });
    $("#cNoLogo").addEventListener("click", function () { state.logo = null; $("#cLogo").value = ""; draw(); });
    $("#cLogo").addEventListener("change", function (e) {
      var f = e.target.files && e.target.files[0]; if (!f) return;
      var img = new Image(), url = URL.createObjectURL(f);
      img.onload = function () {
        var size = 256, s = Math.min(size / img.width, size / img.height, 1), cv = document.createElement("canvas");
        cv.width = Math.max(1, Math.round(img.width * s)); cv.height = Math.max(1, Math.round(img.height * s));
        cv.getContext("2d").drawImage(img, 0, 0, cv.width, cv.height);
        state.logo = cv.toDataURL("image/png").split(",")[1];
        if (state.logo.length > 200000) state.logo = cv.toDataURL("image/jpeg", 0.85).split(",")[1];
        URL.revokeObjectURL(url); draw();
      };
      img.onerror = function () { setMsg($("#cMsg"), "Dit bestand is geen afbeelding."); };
      img.src = url;
    });
    $("#cBack").addEventListener("click", function () { dash.view = "list"; render(); });
    var del = $("#cDel");
    if (del) del.addEventListener("click", async function () {
      if (!confirm("Deze kaart verwijderen? Alle leden en stempels van deze kaart gaan ook weg (de log blijft staan). Dit kan niet ongedaan worden.")) return;
      try { await rpc("pasr_business_card_delete", { p_card: c.id }, true); dash.view = "list"; await refresh(); } catch (e) { setMsg($("#cMsg"), nice(e)); }
    });
    $("#zkCard").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      if (!state.name.trim()) return setMsg($("#cMsg"), "Geef de kaart een naam.");
      if (!state.reward.trim()) return setMsg($("#cMsg"), "Vul de beloning in.");
      var btn = ev.target.querySelector("button[type=submit]"); btn.disabled = true;
      try {
        var payload = { name: state.name, reward: state.reward, stamps_total: state.stamps_total, color: state.color.toUpperCase(), published: $("#cPub").checked, logo: state.logo || null };
        if (state.text_color !== undefined) payload.text_color = state.text_color;
        if (c.id) payload.id = c.id;
        await rpc("pasr_business_card_save", { p_card: payload }, true);
        dash.view = "list"; await refresh(); toast("Kaart opgeslagen");
      } catch (e) { setMsg($("#cMsg"), nice(e)); btn.disabled = false; }
    });
  }

  async function membersView() {
    var c = dash.edit;
    dashRoot().innerHTML = '<div class="zk-top"><div><span class="zk-kicker">Leden</span><h1>' + esc(c.name) + "</h1></div>" + logoutBtn() + '</div><div class="zk-panel" id="mBody">Laden…</div><p><button class="zk-btn ghost" id="mBack">Terug</button></p>';
    bindLogout();
    $("#mBack").addEventListener("click", function () { dash.view = "list"; render(); });
    try {
      var d = await rpc("pasr_business_members_list", { p_card: c.id, p_limit: 300 }, true);
      var days = {}; (d.days || []).forEach(function (x) { days[x.day] = x; });
      var bars = "", max = 1, list = [];
      for (var i = 29; i >= 0; i--) { var k = new Date(Date.now() - i * 864e5).toLocaleDateString("sv-SE", { timeZone: "Europe/Amsterdam" }); var v = days[k] ? days[k].stamps : 0; list.push([k, v]); if (v > max) max = v; }
      bars = list.map(function (x) { return '<i style="height:' + Math.max(2, Math.round(x[1] / max * 100)) + '%" title="' + x[0] + ": " + x[1] + ' stempels"></i>'; }).join("");
      var sum = list.reduce(function (a, x) { return a + x[1]; }, 0);
      $("#mBody").innerHTML = '<h3>Stempels per dag</h3><p style="margin:0">' + sum + " stempels in de laatste 30 dagen, " + d.total + ' leden in totaal.</p><div class="zk-bars" aria-hidden="true">' + bars + "</div>" +
        (d.members && d.members.length ? '<div style="overflow-x:auto"><table class="zk-table"><thead><tr><th>Lid</th><th>Stempels</th><th>Beloningen</th><th>Laatste stempel</th><th>Lid sinds</th></tr></thead><tbody>' +
          d.members.map(function (m) { return "<tr><td>" + esc(m.code) + (m.app ? ' <span class="zk-pill on">app</span>' : "") + "</td><td>" + m.stamps_count + " / " + c.stamps_total + "</td><td>" + m.rewards_redeemed + "</td><td>" + nlDate(m.last_stamp_at) + "</td><td>" + nlDate(m.created_at) + "</td></tr>"; }).join("") + "</tbody></table></div>"
          : '<p class="zk-empty">Nog geen leden. Deel de QR-code of de link om klanten te laten aansluiten.</p>') +
        '<p style="font-size:14px;margin:12px 0 0">Je ziet alleen de laatste 4 tekens van de lidcode; Pasr bewaart geen namen of contactgegevens van je klanten.</p>';
    } catch (e) { $("#mBody").textContent = nice(e); }
  }

  function render() {
    if (!ready) { dashRoot().innerHTML = '<section class="auth err"><h1>Binnenkort</h1><p>Pasr voor ondernemers komt binnenkort.</p></section>'; return; }
    var h = location.hash.replace("#", "");
    if (!session) return loginView(h === "account" ? "signup" : h === "vergeten" ? "forgot" : "login");
    if (!dash.me) { dashRoot().innerHTML = '<p class="zk-empty">Laden…</p>'; return refresh(); }
    if (!dash.me.business) return (dash.me.businesses || []).some(function (x) { return x.role === "staff"; }) ? staffOnlyView() : registerView(null);
    if (dash.view === "edit") return editView();
    if (dash.view === "members") return membersView();
    if (dash.view === "staff") return staffView();
    if (dash.view === "settings") return settingsView();
    if (dash.view === "log") return logView();
    return listView();
  }
  async function refresh() {
    try { dash.me = await rpc("pasr_business_me", {}, true); }
    catch (e) { if (e.status === 401) { session = null; saveSession(null); } dash.me = null; if (session) { dashRoot().innerHTML = '<p class="zk-empty">' + esc(nice(e)) + "</p>"; return; } }
    render();
  }

  // ---------------------------------------------------------------- join-pagina: pasr.nl/zakelijk/kaart/#<id>
  async function joinPage() {
    var id = location.hash.slice(1), root = $("#zk-join");
    var store = "pasr.zakelijk.member." + id;
    function fail(title, text) { root.innerHTML = "<h1>" + esc(title) + "</h1><p>" + esc(text) + '</p><a class="btn btn-ghost" href="/zakelijk/">Over Pasr voor ondernemers</a>'; }
    if (!/^[0-9a-f-]{36}$/i.test(id)) return fail("Deze link werkt niet", "De link is niet compleet. Scan de QR-code bij de zaak opnieuw.");
    if (!ready) return fail("Even niet beschikbaar", "Probeer het later opnieuw.");
    var code = null;
    try { code = localStorage.getItem(store); } catch (e) { /* privévenster */ }
    function memberView(m) {
      document.title = m.card.name + " | " + m.card.business + " | Pasr";
      root.innerHTML = "<h1>" + esc(m.card.name) + "</h1><p>Laat deze code scannen bij " + esc(m.card.business) + " voor een stempel.</p>" + stampCard(m.card, m.stamps_count) +
        '<div class="zk-member-qr">' + qrSvg(m.member_code) + '</div><p class="zk-code">' + esc(m.member_code.replace(/(.{4})(?=.)/g, "$1 ")) + "</p>" +
        "<p>" + (m.stamps_count >= m.stamps_total ? "Je beloning staat klaar: " + esc(m.reward) + "." : "Nog " + (m.stamps_total - m.stamps_count) + " stempels tot " + esc(m.reward) + ".") + "</p>" +
        '<div class="actions"><button class="btn btn-ghost" id="jRefresh" type="button">Vernieuwen</button><a class="btn btn-primary" href="pasr://zakelijk?code=' + encodeURIComponent(m.member_code) + "#" + esc(id) + '">Bewaar in Pasr</a></div>' +
        '<p class="note">Deze kaart staat in deze browser. Met Bewaar in Pasr gaan je stempels mee naar de app. Met de gratis app <a href="' + APP_STORE + '" rel="noopener">Pasr</a> heb je hem altijd bij de hand, ook in Apple Wallet.</p>';
      $("#jRefresh").addEventListener("click", load);
    }
    async function load() {
      try {
        var m = await rpc("pasr_business_member", { p_code: code });
        if (m.status === "ok") return memberView(m);
        if (m.status === "blocked") return fail("Deze kaart is niet meer actief", "De zaak gebruikt deze stempelkaart niet meer.");
        try { localStorage.removeItem(store); } catch (e) { /* */ }
        code = null; return start();
      } catch (e) { fail("Kaart niet opgehaald", "Geen verbinding met Pasr. Controleer je internet en laad de pagina opnieuw."); }
    }
    async function start() {
      var card;
      try { card = await rpc("pasr_business_card_public", { p_card: id }); } catch (e) { return fail("Kaart niet opgehaald", "Geen verbinding met Pasr. Controleer je internet en laad de pagina opnieuw."); }
      if (!card) return fail("Deze kaart bestaat niet (meer)", "Vraag de zaak om een nieuwe QR-code of link.");
      document.title = card.name + " | " + card.business + " | Pasr";
      root.innerHTML = '<span class="zk-kicker">Stempelkaart</span><h1>' + esc(card.name) + "</h1><p>Spaar stempels bij " + esc(card.business) + (card.city ? " in " + esc(card.city) : "") + ". Bij " + card.stamps_total + " stempels: " + esc(card.reward) + ".</p>" +
        stampCard(card, null) +
        '<div class="actions"><a class="btn btn-primary" href="pasr://zakelijk#' + esc(id) + '">Open in Pasr</a><a class="btn btn-ghost" href="' + APP_STORE + '" rel="noopener">Download Pasr</a></div>' +
        '<p class="note">Geen app? <button class="zk-btn sm" id="jJoin" type="button">Gebruik de kaart in je browser</button></p><p class="zk-msg" id="jMsg" role="status"></p>' +
        '<p class="note" style="font-size:14px">Je krijgt een anonieme lidcode; Pasr vraagt geen naam of e-mailadres. <a href="/privacy/#stempelkaarten-van-ondernemers">Privacy</a></p>';
      $("#jJoin").addEventListener("click", async function (ev) {
        ev.target.disabled = true;
        try {
          var m = await rpc("pasr_business_join", { p_card: id });
          code = m.member_code;
          try { localStorage.setItem(store, code); } catch (e) { /* privévenster: alleen deze sessie */ }
          memberView(m);
        } catch (e) { ev.target.disabled = false; setMsg($("#jMsg"), nice(e)); }
      });
    }
    code ? load() : start();
  }

  // ---------------------------------------------------------------- scanner: pasr.nl/zakelijk/scan
  function codeFrom(text) {
    var t = String(text || "").trim().toUpperCase();
    var m = t.match(/PZ(?:[A-HJ-NP-Z2-9]{14}|[A-HJ-NP-Z2-9]{10})(?![A-HJ-NP-Z2-9])/);
    return m ? m[0] : null;
  }
  async function scanPage() {
    var root = $("#zk-scan");
    if (!ready) { root.innerHTML = "<p>Even niet beschikbaar.</p>"; return; }
    if (!session || !(await token())) {
      root.innerHTML = '<section class="auth"><h1>Eerst inloggen</h1><p>De scanner werkt met het account van je zaak, of met je eigen account als medewerker.</p><a class="zk-btn" href="/zakelijk/dashboard/">Inloggen</a></section>';
      return;
    }
    root.innerHTML = '<div class="zk-top"><div><span class="zk-kicker">Scanner</span><h1>Stempel geven</h1></div><a class="zk-btn ghost sm" href="/zakelijk/dashboard/">Dashboard</a></div>' +
      '<div class="zk-cam" id="sCam"><video id="sVideo" playsinline muted></video><span class="frame"></span><span class="hint" id="sHint">Richt de camera op de QR-code van je klant</span></div>' +
      '<form id="sManual" class="zk-form" style="margin-top:14px" novalidate><label>Of typ de code<span class="row"><input id="sCode" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="PZ…" style="flex:1"><button class="zk-btn dark" type="submit">Zoek</button></span></label></form>' +
      '<p class="zk-msg" id="sMsg" role="status"></p><div id="sResult"></div>';
    var video = $("#sVideo"), busy = false, last = "", lastAt = 0, stream = null;
    var detector = ("BarcodeDetector" in window) ? new window.BarcodeDetector({ formats: ["qr_code"] }) : null;
    var canvas = document.createElement("canvas"), ctx = canvas.getContext("2d", { willReadFrequently: true });

    async function show(code) {
      busy = true; setMsg($("#sMsg"), "");
      try {
        var m = await rpc("pasr_business_scan", { p_code: code }, true);
        result(m);
        if (navigator.vibrate) navigator.vibrate(40);
      } catch (e) { setMsg($("#sMsg"), nice(e)); $("#sResult").innerHTML = ""; }
      busy = false;
    }
    var DEVICE = "Webscanner";
    var undoTimer = null;
    function result(m) {
      // aantal-kiezer: standaard 1, tot het maximum per scan van de zaak (1 tot 30)
      var amount = 1, maxAmt = Math.max(1, Math.min(30, Number(m.max_per_scan) || 10)), full = m.stamps_count >= m.stamps_total;
      var cool = m.cooldown_until && new Date(m.cooldown_until) > new Date();
      clearInterval(undoTimer);
      $("#sResult").innerHTML = '<div class="zk-result" id="sBox">' + stampCard(m.card, Math.min(m.stamps_count, m.stamps_total)) +
        '<div class="big">' + m.stamps_count + " van " + m.stamps_total + " stempels</div>" +
        (full ? '<p style="margin:0">Beloning klaar: <b>' + esc(m.reward) + "</b>" + (m.stamps_count > m.stamps_total ? " (" + (m.stamps_count - m.stamps_total) + " stempels blijven staan voor de volgende kaart)" : "") + "</p>" : "") +
        (cool ? '<p class="zk-msg bad" style="margin:0">Afkoeltijd: deze klant kreeg net een stempel. De volgende kan vanaf ' + new Date(m.cooldown_until).toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" }) + ".</p>" : "") +
        '<label class="zk-amount">Aantal stempels<span class="zk-stepper"><button class="zk-btn ghost sm" type="button" id="sMin" aria-label="Minder">-</button>' +
        '<input id="sAmt" type="number" inputmode="numeric" min="1" max="' + maxAmt + '" value="1" aria-label="Aantal stempels">' +
        '<button class="zk-btn ghost sm" type="button" id="sPlus" aria-label="Meer">+</button></span><small>hoogstens ' + maxAmt + " per scan</small></label>" +
        '<div class="zk-actions" style="justify-content:center"><button class="zk-btn mint" id="sStamp" type="button"' + (cool ? " disabled" : "") + ">" + ICON.stamp + '<span id="sStampTxt">Stempel erbij</span></button>' +
        '<button class="zk-btn coral" id="sRedeem" type="button"' + (full ? "" : " disabled") + ">" + ICON.gift + "Beloning inwisselen</button></div>" +
        (m.can_undo_event_id ? '<p style="margin:0"><button class="zk-btn ghost sm" type="button" id="sUndo">Ongedaan maken <span id="sUndoLeft"></span></button></p>' : "") +
        '<p style="font-size:13px;margin:0">Lid …' + esc(m.member_code_suffix || m.member_code.slice(-4)) + (m.rewards_redeemed ? " · " + m.rewards_redeemed + "x beloning gehad" : "") + "</p></div>";
      function setAmt(n) {
        amount = Math.max(1, Math.min(maxAmt, Math.round(Number(n)) || 1));
        $("#sAmt").value = amount;
        $("#sStampTxt").textContent = amount === 1 ? "Stempel erbij" : amount + " stempels erbij";
      }
      $("#sMin").addEventListener("click", function () { setAmt(amount - 1); });
      $("#sPlus").addEventListener("click", function () { setAmt(amount + 1); });
      $("#sAmt").addEventListener("change", function (e) { setAmt(e.target.value); });
      $("#sStamp").addEventListener("click", function (ev) { act(ev.currentTarget, "pasr_business_stamp", { p_code: m.member_code, p_amount: amount, p_device: DEVICE }, amount === 1 ? "Stempel gezet" : amount + " stempels gezet"); });
      $("#sRedeem").addEventListener("click", function (ev) {
        if (!confirm("Beloning inwisselen: " + m.reward + "? Er gaan " + m.stamps_total + " stempels af.")) return;
        act(ev.currentTarget, "pasr_business_redeem", { p_code: m.member_code, p_device: DEVICE }, "Beloning ingewisseld");
      });
      var undo = $("#sUndo");
      if (undo) {
        // ongedaan maken kan 2 minuten na het eigen stempel (eigenaar: elk); de server controleert het ook
        var until = Date.now() + 120000;
        if (m.event_id && m.event_id === m.can_undo_event_id) until = Date.now() + 120000;
        else if (m.last_stamp_at) until = Math.min(until, new Date(m.last_stamp_at).getTime() + 120000);
        var tickUndo = function () {
          var left = Math.round((until - Date.now()) / 1000);
          if (left <= 0) { clearInterval(undoTimer); undo.remove(); return; }
          $("#sUndoLeft").textContent = "(" + Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0") + ")";
        };
        tickUndo(); undoTimer = setInterval(tickUndo, 1000);
        undo.addEventListener("click", function (ev) { act(ev.currentTarget, "pasr_business_undo", { p_event: m.can_undo_event_id, p_device: DEVICE }, "Ongedaan gemaakt"); });
      }
      $("#sBox").scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
    async function act(btn, fn, args, done) {
      btn.disabled = true;
      try { var m = await rpc(fn, args, true); result(m); $("#sBox").classList.add("zk-flash"); setMsg($("#sMsg"), done, true); if (navigator.vibrate) navigator.vibrate(30); }
      catch (e) { btn.disabled = false; setMsg($("#sMsg"), nice(e)); }
    }
    $("#sManual").addEventListener("submit", function (ev) {
      ev.preventDefault();
      var c = codeFrom($("#sCode").value.replace(/\s+/g, ""));
      if (!c) return setMsg($("#sMsg"), "Een code begint met PZ en heeft 16 tekens (oudere codes 12).");
      show(c);
    });
    async function tick() {
      if (!stream) return;
      if (!busy && video.readyState >= 2) {
        var text = null;
        try {
          if (detector) { var r = await detector.detect(video); text = r[0] && r[0].rawValue; }
          else if (window.jsQR) {
            var w = 480, h = Math.round(video.videoHeight / video.videoWidth * w) || 480;
            canvas.width = w; canvas.height = h; ctx.drawImage(video, 0, 0, w, h);
            var q = window.jsQR(ctx.getImageData(0, 0, w, h).data, w, h, { inversionAttempts: "dontInvert" });
            text = q && q.data;
          }
        } catch (e) { /* volgende frame */ }
        var c = codeFrom(text);
        if (c && (c !== last || Date.now() - lastAt > 4000)) { last = c; lastAt = Date.now(); show(c); }
      }
      setTimeout(function () { requestAnimationFrame(tick); }, 120);
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false });
      video.srcObject = stream; await video.play(); tick();
    } catch (e) {
      $("#sHint").textContent = "Geen camera: geef toegang in je browser of typ de code hieronder.";
    }
  }

  // ---------------------------------------------------------------- uitnodiging medewerker: pasr.nl/zakelijk/uitnodiging/#<code>
  async function invitePage() {
    var KEY = "pasr.zakelijk.invite";
    var fromHash = location.hash.slice(1).toUpperCase();
    if (/^[A-HJ-NP-Z2-9]{20}$/.test(fromHash)) { try { sessionStorage.setItem(KEY, fromHash); } catch (e) { /* */ } }
    var code = /^[A-HJ-NP-Z2-9]{20}$/.test(fromHash) ? fromHash : (function () { try { return sessionStorage.getItem(KEY); } catch (e) { return null; } })();
    function box(html) { dashRoot().innerHTML = '<section class="auth" style="max-width:520px"><div class="badge">' + ICON.users + "</div>" + html + "</section>"; }
    if (!code) return box("<h1>Deze link werkt niet</h1><p>De uitnodiging is niet compleet. Vraag de eigenaar van de zaak om een nieuwe link.</p>");
    if (!ready) return box("<h1>Even niet beschikbaar</h1><p>Probeer het later opnieuw.</p>");
    var info;
    try { info = await rpc("pasr_business_staff_invite_info", { p_code: code }); } catch (e) { return box("<h1>Niet opgehaald</h1><p>Geen verbinding met Pasr. Laad de pagina opnieuw.</p>"); }
    if (!info || info.status !== "ok") return box("<h1>Uitnodiging verlopen</h1><p>Deze uitnodiging is verlopen of al gebruikt. Vraag de eigenaar om een nieuwe.</p>");
    var appLink = "pasrzakelijk://uitnodiging#" + code;
    async function accept() {
      try {
        var r = await rpc("pasr_business_staff_accept", { p_code: code }, true);
        try { sessionStorage.removeItem(KEY); } catch (e) { /* */ }
        box("<h1>Welkom bij " + esc(r.business.name) + "</h1><p>Je kunt nu stempels geven en belonen. Open de scanner op deze telefoon, of gebruik de app Pasr Zakelijk.</p>" +
          '<p style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center"><a class="zk-btn" href="/zakelijk/scan/">' + ICON.scan + 'Open de scanner</a><a class="zk-btn ghost" href="' + appLink + '">Open in Pasr Zakelijk</a></p>');
      } catch (e) { box("<h1>Dat lukte niet</h1><p>" + esc(nice(e)) + "</p>"); }
    }
    dash.afterLogin = accept;
    function intro() {
      box("<h1>Uitnodiging van " + esc(info.business) + "</h1><p>" + (info.name ? esc(info.name) + ", je" : "Je") + " bent uitgenodigd om stempels te geven bij " + esc(info.business) + (info.city ? " in " + esc(info.city) : "") + ". Je logt in met je eigen Pasr-account.</p>" +
        '<p style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center"><a class="zk-btn" href="' + appLink + '">Open in Pasr Zakelijk</a>' +
        '<button class="zk-btn ghost" type="button" id="invWeb">' + (session ? "Accepteren in de browser" : "Inloggen en accepteren") + "</button></p>" +
        '<p style="font-size:14px">De app Pasr Zakelijk komt binnenkort in de App Store. Tot die tijd werkt de scanner in je browser.</p>');
      $("#invWeb").addEventListener("click", async function () {
        if (session && (await token())) return accept();
        location.hash = "inloggen"; loginView("login");
      });
    }
    window.addEventListener("hashchange", function () {
      var h = location.hash.replace("#", "");
      if (h === "account") loginView("signup"); else if (h === "vergeten") loginView("forgot"); else if (h === "inloggen") loginView("login");
    });
    intro();
  }

  // ---------------------------------------------------------------- flyer: pasr.nl/zakelijk/flyer/#<id>
  async function flyerPage() {
    var id = location.hash.slice(1), root = $("#zk-flyer");
    if (!/^[0-9a-f-]{36}$/i.test(id) || !ready) { root.innerHTML = "<p>Deze link werkt niet.</p>"; return; }
    var card = null;
    try { card = await rpc("pasr_business_card_public", { p_card: id }); } catch (e) { /* hieronder */ }
    if (!card) { root.innerHTML = '<div class="flyer"><h1>Kaart niet gevonden</h1><p>Zet de kaart eerst online in je dashboard.</p></div>'; return; }
    document.title = "Flyer " + card.name + " | Pasr";
    root.innerHTML = '<p class="no-print"><button class="zk-btn" onclick="window.print()" type="button">' + ICON.print + "Printen of bewaren als PDF</button></p>" +
      '<div class="flyer"><span class="zk-kicker">Digitale stempelkaart</span><h1>Spaar bij ' + esc(card.business) + "</h1>" +
      '<p style="font-size:20px;margin:0">' + card.stamps_total + " stempels = <b>" + esc(card.reward) + "</b></p>" + stampCard(card, Math.ceil(card.stamps_total / 2)) +
      '<div class="qr">' + qrSvg(joinUrl(card.id)) + "</div><p style=\"margin:0;font-weight:700\">Scan met je camera</p>" +
      "<ol><li>Scan de QR-code met de camera van je telefoon.</li><li>Bewaar de kaart in de gratis app Pasr, of gebruik hem in je browser.</li><li>Laat bij elke aankoop je kaart scannen voor een stempel.</li></ol>" +
      '<div class="foot"><img src="/assets/icon.png" alt="">pasr.nl</div></div>';
  }

  // ---------------------------------------------------------------- landingspagina: bewegende voorbeeldkaart
  function homePage() {
    var el = $("#zk-demo");
    if (el) el.innerHTML = stampCard({ name: "Koffiekaart", business: "Koffiebar De Hoek", city: "Apeldoorn", color: "#7B4B2A", stamps_total: 10, reward: "1 gratis koffie" }, 7, "demo");
  }

  var page = document.body.dataset.page;
  if (page === "zk-dashboard") { window.addEventListener("hashchange", function () { if (!session) render(); }); render(); }
  if (page === "zk-join") joinPage();
  if (page === "zk-scan") scanPage();
  if (page === "zk-flyer") flyerPage();
  if (page === "zk-invite") invitePage();
  if (page === "zk-home") homePage();
})();
