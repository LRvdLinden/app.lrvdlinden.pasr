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
    chart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 4v16h16"/><path d="M7 15c2-4 3.5-6 5-4s3 3 4.5-1 2-4 2.5-5"/></svg>',
    card: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3"/><circle cx="8" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="16" cy="12" r="1.6"/></svg>',
    gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
    user: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/></svg>',
    logout: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3M10 17l5-5-5-5M15 12H4"/></svg>',
    mail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18v12H3zM3 7l9 6 9-6"/></svg>',
    back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 5l-7 7 7 7"/></svg>',
    chevron: '<svg class="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>',
    clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    lock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3"/></svg>',
    upload: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 16V4M7 9l5-5 5 5M4 20h16"/></svg>',
    trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>',
    palette: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 3a9 9 0 1 0 0 18c1.2 0 1.8-.9 1.5-1.9-.3-1 .3-2.1 1.5-2.1H17a4 4 0 0 0 4-4c0-5.5-4-10-9-10z"/><circle cx="7.5" cy="11" r="1"/><circle cx="10" cy="7" r="1"/><circle cx="14.5" cy="7" r="1"/></svg>',
    key: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3M15 8l2 2"/></svg>',
    camera: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/></svg>',
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/></svg>',
    undo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/></svg>',
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
  // Deellink van een stempelkaart: eigen pagina per kaart (titel, beschrijving en OG-afbeelding voor WhatsApp, iMessage, …).
  // De oude vorm /zakelijk/kaart/#<id> blijft werken: die pagina stuurt door naar /zakelijk/kaart/<id>/.
  function joinUrl(id) { return "https://pasr.nl/zakelijk/kaart/" + String(id).toLowerCase() + "/"; }
  function nlDate(iso) { return iso ? new Date(iso).toLocaleDateString("nl-NL", { day: "numeric", month: "short", year: "numeric" }) : "—"; }
  function setMsg(el, text, good) { if (el) { el.textContent = text || ""; el.className = "zk-msg " + (text ? (good ? "good" : "bad") : ""); } }
  function toast(text) {
    var t = $("#zk-toast");
    if (!t) { t = document.createElement("div"); t.id = "zk-toast"; t.className = "zk-toast"; t.setAttribute("role", "status"); t.setAttribute("aria-live", "polite"); document.body.appendChild(t); }
    t.textContent = text; t.classList.add("on"); clearTimeout(t._h); t._h = setTimeout(function () { t.classList.remove("on"); }, 2600);
  }
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
      stamps += '<span class="sc-stamp' + (on ? " on" : "") + (last && !on ? " gift" : "") + '" style="--i:' + i + '">' + (on ? "" : last ? ICON.gift : "") + "</span>";
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

  // ---------------------------------------------------------------- dashboard: pasr.nl/zakelijk/dashboard/
  // Alles wat de app Pasr Zakelijk kan, met dezelfde databasefuncties. Tabs staan in TABS; een nieuwe tab = een regel
  // in TABS plus een functie in VIEWS. Eigenaar: alle tabs. Medewerker: alleen Scannen. Meerdere zaken: zaakkiezer.
  var dash = { me: null, bizId: null, tab: null, sub: null, edit: null, chart: { days: 30, metric: "stamps", prev: false } };
  var BIZ_KEY = "pasr.zakelijk.biz";
  var TABS = [
    { id: "overzicht", label: "Overzicht", icon: "chart", owner: true },
    { id: "kaarten", label: "Kaarten", icon: "card", owner: true },
    { id: "scannen", label: "Scannen", icon: "scan" },
    { id: "medewerkers", label: "Medewerkers", short: "Team", icon: "users", owner: true },
    { id: "instellingen", label: "Instellingen", icon: "gear", owner: true },
    { id: "mijn-account", label: "Account", icon: "user", owner: true },
  ];
  var VIEWS = {};   // tab-id -> function(panel, zaak)

  function dashRoot() { return $("#zk-app"); }
  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); v === null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (e) { return null; } }
  function bizList() { return (dash.me && dash.me.businesses) || []; }
  function current() {
    var list = bizList(), id = dash.bizId || store(BIZ_KEY);
    return list.filter(function (b) { return b.id === id; })[0] || list[0] || null;
  }
  function ownBiz() { return bizList().filter(function (b) { return b.role === "owner"; })[0] || null; }
  function tabsFor(b) {
    if (!b) return [];
    if (b.role !== "owner") return TABS.filter(function (t) { return !t.owner; });
    if (b.status === "blocked") return TABS.filter(function (t) { return t.id === "mijn-account"; });
    return TABS;
  }
  function plural(n, one, more) { return n + " " + (n === 1 ? one : more); }
  function dayLabel(iso, long) {
    var d = new Date(iso + "T12:00:00");
    return d.toLocaleDateString("nl-NL", long ? { weekday: "long", day: "numeric", month: "long" } : { day: "numeric", month: "short" });
  }

  // ---- inloggen, account maken, wachtwoord vergeten (bestaande Pasr-accountflow) ----
  function loginView(mode) {
    var shown = performance.now();
    var signup = mode === "signup", forgot = mode === "forgot";
    dashRoot().innerHTML =
      '<section class="auth zd-auth"><div class="badge">' + ICON.stamp + "</div>" +
      "<h1>" + (signup ? "Gratis aanmelden" : forgot ? "Wachtwoord vergeten" : "Inloggen voor ondernemers") + "</h1>" +
      "<p>" + (signup ? "Maak een gratis Pasr-account met het e-mailadres van je zaak. Daarna meld je je zaak aan en ontwerp je je stempelkaart." : forgot ? "Vul je e-mailadres in. Je krijgt een mail om een nieuw wachtwoord te kiezen." : "Log in met je Pasr-account, hetzelfde als in de app Pasr Zakelijk.") + "</p>" +
      '<form id="zkAuth" class="zk-form" novalidate>' +
      (signup ? '<label for="zkName">Je voornaam</label><input id="zkName" autocomplete="given-name" maxlength="40" required>' : "") +
      '<label for="zkEmail">E-mailadres</label><input id="zkEmail" type="email" autocomplete="email" required>' +
      (forgot ? "" : '<label for="zkPw">Wachtwoord</label><input id="zkPw" type="password" autocomplete="' + (signup ? "new-password" : "current-password") + '" minlength="8" required' + (signup ? ' aria-describedby="zkPwHelp"' : "") + ">" +
        (signup ? '<small id="zkPwHelp" class="zd-help">Minstens 8 tekens.</small>' : "")) +
      (signup ? '<div class="hp-field" aria-hidden="true"><label>Laat dit veld leeg<input type="text" id="zkWebsite" tabindex="-1" autocomplete="off"></label></div>' : "") +
      '<button class="zk-btn" type="submit">' + (signup ? "Account maken" : forgot ? "Stuur mail" : "Inloggen") + '</button><p class="zk-msg" id="zkMsg" role="status" aria-live="polite"></p></form>' +
      '<p class="switch">' +
      (signup ? 'Al een account? <a href="#inloggen">Inloggen</a>' : forgot ? '<a href="#inloggen">Terug naar inloggen</a>' : 'Nog geen account? <a href="#account">Gratis aanmelden</a> · <a href="#vergeten">Wachtwoord vergeten?</a>') + "</p></section>";
    $("#zkAuth").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var msg = $("#zkMsg"), btn = ev.target.querySelector("button");
      var email = $("#zkEmail").value.trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { $("#zkEmail").focus(); return setMsg(msg, "Dit e-mailadres klopt niet."); }
      btn.disabled = true;
      try {
        if (forgot) {
          await http("auth/v1/recover?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: email });
          setMsg(msg, "Als er een account met dit adres is, staat er nu een mail in je inbox.", true);
        } else if (signup) {
          var name = $("#zkName").value.replace(/[<>]/g, "").replace(/\s+/g, " ").trim().slice(0, 40), pw = $("#zkPw").value;
          if (!name) { btn.disabled = false; $("#zkName").focus(); return setMsg(msg, "Vul je voornaam in."); }
          if (pw.length < 8) { btn.disabled = false; $("#zkPw").focus(); return setMsg(msg, "Kies een wachtwoord van minstens 8 tekens."); }
          var data = { first_name: name, fill_ms: Math.round(performance.now() - shown), app: "zakelijk" };
          var hp = $("#zkWebsite").value; if (hp) data.hp = hp;
          await http("auth/v1/signup?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: email, password: pw, data: data });
          dashRoot().innerHTML = '<section class="auth ok zd-auth"><div class="badge">' + ICON.mail + "</div><h1>Check je mail</h1><p>We hebben een mail gestuurd naar " + esc(email) +
            '. Tik op de knop in die mail om je e-mailadres te bevestigen. Kom daarna terug en log hier in om je zaak aan te melden.</p><p><a class="zk-btn" href="#inloggen">Naar inloggen</a></p></section>';
        } else {
          keep(await http("auth/v1/token?grant_type=password", { email: email, password: $("#zkPw").value }));
          navState();
          if (dash.afterLogin) return dash.afterLogin();
          history.replaceState(null, "", location.pathname);
          await refresh();
        }
      } catch (e) { setMsg(msg, nice(e)); } finally { btn.disabled = false; }
    });
    var first = $(signup ? "#zkName" : "#zkEmail"); if (first && mode !== "login-quiet") first.focus({ preventScroll: true });
  }

  // ---- zaak aanmelden (geen eigen zaak) ----
  function registerView() {
    var staff = bizList().length > 0;
    dashRoot().innerHTML = '<div class="zd-head"><div class="zd-biz"><span class="zd-logo">' + ICON.plus + '</span><div><h1>Meld je zaak aan</h1><p class="zd-sub">Gratis · we keuren elke zaak met de hand, meestal binnen een werkdag</p></div></div>' + userBox() + "</div>" +
      (staff ? '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="rBack">' + ICON.back + "Terug naar je zaken</button></p>" : "") +
      '<div class="zk-panel zd-narrow"><form id="zkReg" class="zk-form" novalidate>' + bizFields(null) +
      '<p class="zd-help">De naam en plaats komen op je stempelkaart. Je e-mailadres blijft privé. Lees ook onze <a href="/privacy/#stempelkaarten-van-ondernemers">privacyverklaring</a>.</p>' +
      '<div class="row"><button class="zk-btn" type="submit">Aanmelden</button></div><p class="zk-msg" id="rMsg" role="status" aria-live="polite"></p></form></div>';
    bindUser();
    var back = $("#rBack"); if (back) back.addEventListener("click", function () { dash.sub = null; render(); });
    $("#zkReg").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        var nb = await rpc("pasr_business_register", bizArgs(), true);
        dash.bizId = nb.id; store(BIZ_KEY, nb.id); dash.sub = null; dash.tab = "kaarten";
        await refresh(); toast("Je zaak is aangemeld");
      } catch (e) { setMsg($("#rMsg"), /bad_name/.test(e.message) ? "Vul de naam van je zaak in (minstens 2 tekens)." : nice(e)); btn.disabled = false; }
    });
  }
  function bizFields(b) {
    return '<label for="rName">Naam van je zaak</label><input id="rName" maxlength="60" required autocomplete="organization" value="' + esc(b && b.name) + '">' +
      '<label for="rCity">Plaats</label><input id="rCity" maxlength="60" autocomplete="address-level2" value="' + esc(b && b.city) + '">' +
      '<label for="rWeb">Website <span class="zd-opt">(optioneel)</span></label><input id="rWeb" maxlength="200" inputmode="url" autocomplete="url" placeholder="jouwzaak.nl" aria-describedby="rWebHelp" value="' + esc(b && b.website) + '">' +
      '<small id="rWebHelp" class="zd-help">Pasr neemt je logo en kleur van je website over voor je stempelkaart.</small>' +
      '<label for="rNote">Wat voor zaak is het? <span class="zd-opt">(optioneel)</span></label><textarea id="rNote" rows="3" maxlength="300" placeholder="Bijvoorbeeld: koffiebar met lunch, 2 vestigingen">' + esc(b && b.note) + "</textarea>";
  }
  function bizArgs() { return { p_name: $("#rName").value, p_city: $("#rCity").value, p_website: ($("#rWeb").value || "").trim() || null, p_note: $("#rNote").value || null }; }

  // ---- kop van het dashboard: zaak, zaakkiezer, account ----
  function logoOf(b) { var c = (b.cards || []).filter(function (x) { return x.logo; })[0]; return c ? '<img src="' + imgSrc(c.logo) + '" alt="">' : esc(String(b.name || "?").trim().charAt(0).toUpperCase()); }
  function colorOf(b) { var c = (b.cards || [])[0]; return c && /^#[0-9a-f]{6}$/i.test(c.color || "") ? c.color : "#6A5CFF"; }
  var STATUS = { pending: ["Wacht op goedkeuring", "pending"], approved: ["Goedgekeurd", "approved"], blocked: ["Geblokkeerd", "blocked"] };
  function userBox() {
    return '<div class="zd-user"><span class="zd-mail" title="Ingelogd als">' + ICON.user + "<span>" + esc((session && session.email) || "") + '</span></span><button class="zk-btn ghost sm" type="button" id="zkOut">' + ICON.logout + "Uitloggen</button></div>";
  }
  function bindUser() {
    var b = $("#zkOut"); if (!b) return;
    b.addEventListener("click", logout);
  }
  async function logout() {
    stopScanner();
    try { var t = await token(); if (t) await http("auth/v1/logout", {}, t); } catch (e) { /* toch uitloggen */ }
    session = null; saveSession(null); dash.me = null; dash.tab = null; dash.sub = null; store(BIZ_KEY, null);
    navState(); history.replaceState(null, "", location.pathname); render();
  }
  function picker(b) {
    var list = bizList(), own = ownBiz();
    if (list.length < 2 && own) return "";
    var opts = list.map(function (x) {
      return '<option value="' + esc(x.id) + '"' + (x.id === b.id ? " selected" : "") + ">" + esc(x.name) + (x.city ? " · " + esc(x.city) : "") + " (" + (x.role === "owner" ? "eigenaar" : "medewerker") + ")</option>";
    }).join("") + (own ? "" : '<option value="__new">+ Eigen zaak aanmelden</option>');
    return '<div class="zd-picker"><label for="zdPick">Zaak</label><select id="zdPick">' + opts + "</select></div>";
  }
  function head(b) {
    var st = STATUS[b.status] || STATUS.pending;
    return '<div class="zd-head"><div class="zd-biz"><span class="zd-logo" style="background:' + colorOf(b) + '">' + logoOf(b) + "</span><div>" +
      '<span class="zk-status ' + st[1] + '">' + st[0] + '</span><h1>' + esc(b.name) + '</h1><p class="zd-sub">' + esc([b.city, b.role === "owner" ? "Eigenaar" : "Medewerker"].filter(Boolean).join(" · ")) + "</p></div></div>" +
      picker(b) + userBox() + "</div>";
  }
  function banner(b) {
    if (b.status === "blocked") {
      return '<div class="zd-state blocked" role="alert"><span class="zd-state-ic">' + ICON.lock + "</span><div><h2>" + (b.role === "owner" ? "Je zaak is geblokkeerd" : "Deze zaak is geblokkeerd") + "</h2>" +
        "<p>Je stempelkaarten zijn offline en er kunnen geen stempels worden gezet. Denk je dat dit niet klopt? Mail <a href=\"mailto:support@pasr.nl?subject=" + encodeURIComponent("Zaak geblokkeerd: " + b.name) + "\">support@pasr.nl</a>.</p></div></div>";
    }
    if (b.status !== "approved") {
      return '<div class="zd-state pending" role="status"><span class="zd-state-ic">' + ICON.clock + "</span><div><h2>Wacht op goedkeuring</h2>" +
        (b.role === "owner"
          ? "<p>We bekijken je aanmelding, meestal binnen een werkdag. Ontwerp alvast je stempelkaart en stel je zaak in; zodra je zaak is goedgekeurd zet je de kaart online en geef je stempels. Je krijgt een mail.</p>"
          : "<p>Deze zaak is nog niet goedgekeurd. Scannen kan zodra Pasr de zaak heeft goedgekeurd.</p>") + "</div></div>";
    }
    return "";
  }
  function tabBar(b) {
    var tabs = tabsFor(b);
    if (tabs.length < 2) return "";
    return '<div class="zd-tabs" role="tablist" aria-label="Onderdelen van je dashboard">' + tabs.map(function (t) {
      var on = t.id === dash.tab;
      return '<button type="button" role="tab" id="tab-' + t.id + '" aria-controls="zd-panel" aria-selected="' + on + '" tabindex="' + (on ? 0 : -1) + '" data-tab="' + t.id + '">' +
        ICON[t.icon] + '<span class="l">' + t.label + "</span>" + (t.short ? '<span class="s" aria-hidden="true">' + t.short + "</span>" : "") + "</button>";
    }).join("") + "</div>";
  }
  function bindTabs() {
    var list = dashRoot().querySelector(".zd-tabs"); if (!list) return;
    var btns = Array.prototype.slice.call(list.querySelectorAll("[role=tab]"));
    btns.forEach(function (btn, i) {
      btn.addEventListener("click", function () { go(btn.dataset.tab); });
      btn.addEventListener("keydown", function (e) {
        var k = e.key, j = k === "ArrowRight" ? i + 1 : k === "ArrowLeft" ? i - 1 : k === "Home" ? 0 : k === "End" ? btns.length - 1 : null;
        if (j === null) return;
        e.preventDefault(); j = (j + btns.length) % btns.length; go(btns[j].dataset.tab, true);
      });
    });
  }
  function go(tab, focusTab) {
    dash.sub = null; dash.edit = null;
    if (location.hash !== "#" + tab) history.pushState(null, "", "#" + tab);
    dash.tab = tab; render();
    var t = $("#tab-" + tab); if (focusTab && t) t.focus();
  }

  function render() {
    stopScanner();
    if (!ready) { dashRoot().innerHTML = '<section class="auth err"><h1>Binnenkort</h1><p>Pasr voor ondernemers komt binnenkort.</p></section>'; return; }
    var h = location.hash.replace("#", "");
    if (!session) return loginView(h === "account" ? "signup" : h === "vergeten" ? "forgot" : "login");
    if (!dash.me) { dashRoot().innerHTML = '<p class="zk-empty">Laden…</p>'; return refresh(); }
    if (dash.sub === "register" || !bizList().length) return registerView();
    var b = current(); dash.bizId = b.id;
    var tabs = tabsFor(b), ids = tabs.map(function (t) { return t.id; });
    if (ids.indexOf(h) >= 0) dash.tab = h;
    if (ids.indexOf(dash.tab) < 0) dash.tab = b.role === "owner" ? (b.status === "blocked" ? "mijn-account" : (b.cards || []).length ? "overzicht" : "kaarten") : "scannen";
    var tab = tabs.filter(function (t) { return t.id === dash.tab; })[0];
    dashRoot().innerHTML = head(b) + banner(b) + tabBar(b) +
      '<section id="zd-panel" class="zd-panel" role="' + (tabs.length > 1 ? "tabpanel" : "region") + '" aria-labelledby="' + (tabs.length > 1 ? "tab-" + tab.id : "zd-title") + '" tabindex="-1"></section>';
    document.title = tab.label + " · " + b.name + " | Pasr voor ondernemers";
    bindUser(); bindTabs();
    var pick = $("#zdPick");
    if (pick) pick.addEventListener("change", function () {
      if (pick.value === "__new") { dash.sub = "register"; return render(); }
      dash.bizId = pick.value; store(BIZ_KEY, pick.value); dash.tab = null; dash.sub = null;
      history.replaceState(null, "", location.pathname); render(); toast("Gewisseld naar " + current().name);
    });
    var panel = $("#zd-panel");
    if (b.status === "blocked" && b.role !== "owner") { panel.innerHTML = '<p class="zk-empty">Er is hier nu niets te doen.</p>'; return; }
    (VIEWS[tab.id] || function () {})(panel, b);
  }
  async function refresh() {
    try { dash.me = await rpc("pasr_business_me", {}, true); }
    catch (e) {
      if (e.status === 401) { session = null; saveSession(null); navState(); }
      dash.me = null;
      if (session) { dashRoot().innerHTML = '<div class="zd-state blocked" role="alert"><div><h2>Niet opgehaald</h2><p>' + esc(nice(e)) + '</p><p><button class="zk-btn" type="button" id="zdRetry">Opnieuw proberen</button></p></div></div>'; $("#zdRetry").addEventListener("click", refresh); return; }
    }
    render();
  }
  function panelTitle(title, sub, actions) {
    return '<div class="zd-ptitle"><div><h2 id="zd-title">' + esc(title) + "</h2>" + (sub ? '<p class="zd-sub">' + sub + "</p>" : "") + "</div>" + (actions || "") + "</div>";
  }
  function table(cols, rows, cls) {
    return '<div class="zd-tablewrap"><table class="zk-table zd-table ' + (cls || "") + '"><thead><tr>' + cols.map(function (c) { return '<th scope="col">' + c + "</th>"; }).join("") + "</tr></thead><tbody>" +
      rows.map(function (r) { return "<tr" + (r.attr || "") + ">" + r.cells.map(function (c, i) { return '<td data-label="' + esc(cols[i].replace(/<[^>]+>/g, "")) + '"><span>' + c + "</span></td>"; }).join("") + "</tr>"; }).join("") +
      "</tbody></table></div>";
  }

  // ---- Overzicht: grafiek in Homey Insights-stijl, cijfers, leden per kaart en het logboek ----
  var METRICS = { stamps: ["Stempels", "stempels", "#12A77E", "#2ED3A6"], rewards: ["Beloningen", "beloningen", "#D2412E", "#FF6B57"], new_members: ["Nieuwe leden", "leden", "#4A3CE0", "#6A5CFF"] };
  var PERIODS = [[7, "W", "Week"], [30, "M", "Maand"], [90, "K", "Kwartaal"], [365, "J", "Jaar"]];
  VIEWS.overzicht = async function (panel, b) {
    if (dash.sub === "members") return membersView(panel, b);
    if (dash.sub === "log") return logView(panel, b, 300);
    panel.innerHTML = panelTitle("Overzicht", "Hoe je stempelkaarten het doen.") +
      '<div class="zd-kpis" id="ovKpi">' + ["Stempels", "Beloningen", "Nieuwe leden", "Leden"].map(function (t, i) { return '<div class="zd-kpi k' + i + '"><small>' + t + "</small><b>–</b></div>"; }).join("") + "</div>" +
      '<div class="zd-insights" id="ovChart"><p class="zk-empty">Laden…</p></div>' +
      '<div class="zd-two"><div class="zk-panel" id="ovCards"></div><div class="zk-panel" id="ovLog"><h3>Logboek</h3><p class="zk-empty">Laden…</p></div></div>';
    var cards = b.cards || [];
    $("#ovCards").innerHTML = "<h3>Leden per kaart</h3>" + (cards.length ? '<ul class="zd-list">' + cards.map(function (c) {
      return '<li><button type="button" data-card="' + esc(c.id) + '"><span class="dot" style="background:' + esc(c.color) + '"></span><span class="t"><b>' + esc(c.name) + "</b><small>" + (c.published ? "Online" : "Concept") + " · " + plural(c.stamps || 0, "stempel", "stempels") + "</small></span><span class=\"n\">" + (c.members || 0) + '<small>leden</small></span>' + ICON.chevron + "</button></li>";
    }).join("") + "</ul>" : '<p class="zk-empty">Nog geen kaarten. <button class="zk-btn sm" type="button" id="ovNew">' + ICON.plus + "Kaart ontwerpen</button></p>");
    $("#ovCards").querySelectorAll("[data-card]").forEach(function (btn) {
      btn.addEventListener("click", function () { dash.edit = cards.filter(function (c) { return c.id === btn.dataset.card; })[0]; dash.sub = "members"; VIEWS.overzicht(panel, b); });
    });
    var nb = $("#ovNew"); if (nb) nb.addEventListener("click", function () { go("kaarten"); });
    drawInsights(b);
    logView($("#ovLog"), b, 8, true);
  };

  async function drawInsights(b) {
    var box = $("#ovChart"); if (!box) return;
    var st = dash.chart, days = st.days, both = days * 2 <= 366;
    var data;
    try { data = await rpc("pasr_business_stats", { p_business: b.id, p_days: both ? days * 2 : days }, true); }
    catch (e) { box.innerHTML = '<p class="zk-empty">' + esc(nice(e)) + "</p>"; return; }
    if (!$("#ovChart")) return;
    var all = data.days || [], cur = all.slice(-days), prev = both ? all.slice(0, all.length - days) : [];
    var sum = function (arr, k) { return arr.reduce(function (a, d) { return a + (Number(d[k]) || 0); }, 0); };
    var kpi = $("#ovKpi");
    if (kpi) {
      var vals = [sum(cur, "stamps"), sum(cur, "rewards"), sum(cur, "new_members"), (data.totals && data.totals.members) || 0];
      kpi.querySelectorAll("b").forEach(function (el, i) { el.textContent = vals[i]; });
    }
    var m = METRICS[st.metric], shown = st.prev && both ? prev : cur, total = sum(shown, st.metric);
    var plabel = (PERIODS.filter(function (p) { return p[0] === days; })[0] || [0, "", "Periode"])[2];
    var range = shown.length ? dayLabel(shown[0].day) + " – " + dayLabel(shown[shown.length - 1].day) : "";
    box.innerHTML =
      '<div class="zi-top"><div class="zi-metric" role="group" aria-label="Meetwaarde">' + Object.keys(METRICS).map(function (k) {
        return '<button type="button" aria-pressed="' + (k === st.metric) + '" data-m="' + k + '" style="--mc:' + METRICS[k][2] + '">' + METRICS[k][0] + "</button>";
      }).join("") + "</div></div>" +
      '<div class="zi-head"><div><h3>' + (st.prev ? "Vorige " + plabel.toLowerCase() : "Deze " + plabel.toLowerCase()) + '</h3><p id="ziWhen">' + esc(range) + '</p></div><p class="zi-val" style="color:' + m[2] + '"><b id="ziVal">' + total + "</b> <span>" + m[1] + "</span></p></div>" +
      chartHtml(shown, st.metric, m) +
      '<div class="zi-segs"><div class="zi-seg" role="group" aria-label="Periode">' + PERIODS.map(function (p) {
        return '<button type="button" data-d="' + p[0] + '" aria-pressed="' + (p[0] === days) + '" aria-label="' + p[2] + '">' + p[1] + "</button>";
      }).join("") + '</div><div class="zi-seg" role="group" aria-label="Vergelijken">' +
      '<button type="button" data-p="0" aria-pressed="' + !st.prev + '">Deze ' + plabel.toLowerCase() + "</button>" +
      (both ? '<button type="button" data-p="1" aria-pressed="' + st.prev + '">Vorige ' + plabel.toLowerCase() + "</button>" : "") + "</div></div>" +
      '<p class="sr-only">' + esc(m[0] + ": " + total + " in " + range + ". " + (st.prev ? "" : both ? "Vorige periode: " + sum(prev, st.metric) + "." : "")) + "</p>";
    box.querySelectorAll("[data-m]").forEach(function (x) { x.addEventListener("click", function () { st.metric = x.dataset.m; drawInsights(b); }); });
    box.querySelectorAll("[data-d]").forEach(function (x) { x.addEventListener("click", function () { st.days = Number(x.dataset.d); if (st.days * 2 > 366) st.prev = false; drawInsights(b); }); });
    box.querySelectorAll("[data-p]").forEach(function (x) { x.addEventListener("click", function () { st.prev = x.dataset.p === "1"; drawInsights(b); }); });
    bindChart(box, shown, st.metric, m, total, range);
  }
  /** Grafiek zoals Homey Insights: vloeiende lijn met verloopvlak, gestippeld raster, eenheid boven de Y-as, selectie met ring-punt. */
  function chartHtml(rows, key, m) {
    var W = 600, H = 220, n = rows.length, vals = rows.map(function (d) { return Number(d[key]) || 0; });
    var max = Math.max.apply(null, vals.concat([0])), step = Math.max(1, Math.ceil(Math.max(4, max * 1.15) / 3)), top = step * 3;
    var pts = vals.map(function (v, i) { return [n > 1 ? i * W / (n - 1) : W / 2, H - v / top * H]; });
    var d = pts.length ? "M" + pts[0][0].toFixed(1) + " " + pts[0][1].toFixed(1) : "";
    for (var i = 1; i < pts.length; i++) {
      var p0 = pts[i - 1], p1 = pts[i], cx = ((p0[0] + p1[0]) / 2).toFixed(1);
      d += " C" + cx + " " + p0[1].toFixed(1) + " " + cx + " " + p1[1].toFixed(1) + " " + p1[0].toFixed(1) + " " + p1[1].toFixed(1);
    }
    var grid = [1, 2, 3].map(function (k) { return '<line x1="0" x2="' + W + '" y1="' + (H - k * H / 3) + '" y2="' + (H - k * H / 3) + '"/>'; }).join("");
    var ylab = [3, 2, 1, 0].map(function (k) { return '<span style="top:' + (100 - k * 100 / 3) + '%">' + k * step + "</span>"; }).join("");
    var xn = Math.min(5, n), xlab = "";
    for (var j = 0; j < xn; j++) { var idx = Math.round(j * (n - 1) / Math.max(1, xn - 1)); xlab += '<span style="left:' + (n > 1 ? idx * 100 / (n - 1) : 50) + '%">' + esc(rows[idx] ? dayLabel(rows[idx].day) : "") + "</span>"; }
    var empty = !vals.some(function (v) { return v > 0; });
    var gid = "zg" + key;
    return '<div class="zi-chart" style="--mc:' + m[3] + '"><span class="zi-unit">' + m[1] + '</span><div class="zi-y" aria-hidden="true">' + ylab + "</div>" +
      '<div class="zi-plot" tabindex="0" role="img" aria-label="Grafiek ' + esc(m[0].toLowerCase()) + ' per dag. Gebruik de pijltjestoetsen om per dag te bekijken.">' +
      '<svg viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="' + gid + '" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="' + m[3] + '" stop-opacity=".35"/><stop offset="1" stop-color="' + m[3] + '" stop-opacity="0"/></linearGradient></defs>' +
      '<g class="zi-grid">' + grid + "</g>" + (d ? '<path d="' + d + " L" + W + " " + H + " L0 " + H + ' Z" fill="url(#' + gid + ')"/><path class="zi-line" d="' + d + '"/>' : "") + "</svg>" +
      '<span class="zi-rule" hidden></span><span class="zi-dot" hidden></span>' + (empty ? '<span class="zi-empty">Nog geen gegevens in deze periode</span>' : "") + "</div>" +
      '<div class="zi-x" aria-hidden="true">' + xlab + "</div></div>";
  }
  function bindChart(box, rows, key, m, total, range) {
    var plot = box.querySelector(".zi-plot"); if (!plot || !rows.length) return;
    var rule = plot.querySelector(".zi-rule"), dot = plot.querySelector(".zi-dot"), val = $("#ziVal"), when = $("#ziWhen"), sel = -1;
    var vals = rows.map(function (d) { return Number(d[key]) || 0; });
    var max = Math.max.apply(null, vals.concat([0])), top = Math.max(1, Math.ceil(Math.max(4, max * 1.15) / 3)) * 3;
    function show(i) {
      sel = i;
      if (i < 0) { rule.hidden = dot.hidden = true; val.textContent = total; when.textContent = range; return; }
      var x = rows.length > 1 ? i * 100 / (rows.length - 1) : 50, y = 100 - vals[i] / top * 100;
      rule.hidden = dot.hidden = false; rule.style.left = x + "%"; dot.style.left = x + "%"; dot.style.top = y + "%";
      val.textContent = vals[i]; when.textContent = dayLabel(rows[i].day, true);
    }
    function at(e) { var r = plot.getBoundingClientRect(); return Math.max(0, Math.min(rows.length - 1, Math.round((e.clientX - r.left) / r.width * (rows.length - 1)))); }
    plot.addEventListener("pointermove", function (e) { show(at(e)); });
    plot.addEventListener("pointerdown", function (e) { show(at(e)); });
    plot.addEventListener("pointerleave", function (e) { if (e.pointerType === "mouse") show(-1); });
    plot.addEventListener("keydown", function (e) {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") { e.preventDefault(); show(Math.max(0, Math.min(rows.length - 1, (sel < 0 ? rows.length - 1 : sel + (e.key === "ArrowRight" ? 1 : -1))))); }
      if (e.key === "Escape") show(-1);
    });
    plot.addEventListener("blur", function () { show(-1); });
  }

  // ---- logboek (niet te wissen) ----
  var KIND = { join: "Nieuw lid", claim: "Kaart naar de app", stamp: "Stempel", redeem: "Beloning ingewisseld", undo: "Ongedaan gemaakt" };
  async function logView(box, b, limit, compact) {
    if (!compact) box.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="lgBack">' + ICON.back + "Overzicht</button></p>" + panelTitle("Logboek", "Elke stempel, inwisseling en ongedaanmaking met wie, wat en wanneer. Niemand kan het logboek wissen, ook jij niet.") + '<div class="zk-panel" id="lgBody"><p class="zk-empty">Laden…</p></div>';
    if (!compact) $("#lgBack").addEventListener("click", function () { dash.sub = null; render(); });
    var body = compact ? box : $("#lgBody");
    try {
      var r = await rpc("pasr_business_log", { p_business: b.id, p_limit: limit }, true), ev = r.events || [];
      var rows = ev.map(function (x) {
        var what = KIND[x.kind] || x.kind;
        if (x.kind === "stamp") what = plural(x.amount || 1, "stempel", "stempels");
        if (x.stamps_after != null && x.kind !== "join" && x.kind !== "claim") what += " (" + x.stamps_before + " → " + x.stamps_after + ")";
        var who = x.by_role === "customer" ? "Klant" : esc(x.by_name || "—") + (x.by_role === "staff" ? ' <small>medewerker</small>' : "") + (x.device && !compact ? "<br><small>" + esc(x.device) + "</small>" : "");
        return { attr: x.undone ? ' class="undone"' : "", cells: [timeNl(x.at), esc(what) + (x.undone ? ' <small>ongedaan</small>' : ""), esc(x.card_name || "verwijderde kaart"), "…" + esc(x.member_suffix || ""), who] };
      });
      body.innerHTML = (compact ? "<h3>Logboek</h3>" : "") + (rows.length ? table(["Wanneer", "Wat", "Kaart", "Klant", "Door"], rows, compact ? "compact" : "") : '<p class="zk-empty">Nog niets gebeurd. Zodra je de eerste klant scant, staat het hier.</p>') +
        (compact && rows.length ? '<p class="zd-more"><button class="zk-btn ghost sm" type="button" id="lgAll">Hele logboek bekijken' + ICON.chevron + "</button></p>" : "") +
        (compact ? "" : '<p class="zd-help">Doorgestreept = ongedaan gemaakt. Je ziet de laatste ' + limit + " regels.</p>");
      var all = $("#lgAll", body); if (all) all.addEventListener("click", function () { dash.sub = "log"; render(); });
    } catch (e) { body.innerHTML = (compact ? "<h3>Logboek</h3>" : "") + '<p class="zk-empty">' + esc(nice(e)) + "</p>"; }
  }
  function timeNl(iso) { return iso ? new Date(iso).toLocaleString("nl-NL", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—"; }

  // ---- leden van één kaart ----
  async function membersView(panel, b) {
    var c = dash.edit;
    panel.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="mBack">' + ICON.back + "Overzicht</button></p>" +
      panelTitle("Leden van " + c.name, c.stamps_total + " stempels voor " + esc(c.reward)) + '<div class="zk-panel" id="mBody"><p class="zk-empty">Laden…</p></div>';
    $("#mBack").addEventListener("click", function () { dash.sub = null; render(); });
    try {
      var d = await rpc("pasr_business_members_list", { p_card: c.id, p_limit: 300 }, true);
      var rows = (d.members || []).map(function (m) {
        return { cells: [esc(m.code) + (m.app ? ' <span class="zk-pill on">app</span>' : ' <span class="zk-pill">browser</span>'), m.stamps_count + " / " + c.stamps_total, String(m.rewards_redeemed), nlDate(m.last_stamp_at), nlDate(m.created_at)] };
      });
      $("#mBody").innerHTML = '<p class="zd-sub">' + plural(d.total || 0, "lid", "leden") + " in totaal.</p>" +
        (rows.length ? table(["Klantcode", "Stempels", "Beloningen", "Laatste stempel", "Lid sinds"], rows) : '<p class="zk-empty">Nog geen leden. Deel de QR-code of de link om klanten te laten aansluiten.</p>') +
        '<p class="zd-help">Je ziet alleen de laatste tekens van de klantcode; Pasr bewaart geen namen of contactgegevens van je klanten.</p>';
    } catch (e) { $("#mBody").innerHTML = '<p class="zk-empty">' + esc(nice(e)) + "</p>"; }
  }

  // ---- Kaarten: maken, bewerken, publiceren, huisstijl, QR, link en flyer ----
  VIEWS.kaarten = function (panel, b) {
    if (dash.sub === "edit") return editView(panel, b);
    var cards = b.cards || [], approved = b.status === "approved";
    var add = cards.length < 5 ? '<button class="zk-btn" id="zkNew" type="button">' + ICON.plus + "Nieuwe kaart</button>" : "";
    var html = panelTitle("Kaarten", plural(cards.length, "kaart", "kaarten") + " van de 5" + (approved ? "" : " · online zetten kan na goedkeuring"), cards.length ? add : "");
    if (!cards.length) {
      html += '<div class="zk-panel zd-first"><div class="zd-first-card">' + stampCard({ name: "Koffiekaart", business: b.name, city: b.city, color: "#6A5CFF", stamps_total: 10, reward: "1 gratis koffie" }, 4) + "</div><div><h3>Je eerste stempelkaart</h3><p>Kies een naam, je logo en kleur, hoeveel stempels er op een kaart gaan en wat je klant daarvoor krijgt." +
        (b.website ? " We halen je logo en kleur alvast van " + esc(b.website.replace(/^https?:\/\//, "").replace(/\/.*$/, "")) + "." : "") + "</p>" + add + "</div></div>";
    } else {
      html += '<div class="zk-cards">' + cards.map(function (c) {
        return '<article class="zk-card" data-id="' + esc(c.id) + '" aria-labelledby="c-' + esc(c.id) + '">' + stampCard(c, null) + '<div class="zd-cardinfo">' +
          '<div class="zd-cardtitle"><h3 id="c-' + esc(c.id) + '">' + esc(c.name) + '</h3><span class="zk-pill' + (c.published ? " on" : "") + '">' + (c.published ? "Online" : "Concept") + "</span></div>" +
          '<p class="zd-sub">' + esc(c.stamps_total) + " stempels voor " + esc(c.reward) + "</p>" +
          '<div class="zk-stats"><span class="zk-stat"><b>' + (c.members || 0) + '</b><small>leden</small></span><span class="zk-stat"><b>' + (c.stamps || 0) + '</b><small>stempels</small></span><span class="zk-stat"><b>' + (c.rewards || 0) + "</b><small>beloningen</small></span></div>" +
          '<div class="zk-actions"><button class="zk-btn sm" type="button" data-act="edit">' + ICON.edit + "Bewerken</button>" +
          '<button class="zk-btn ghost sm" type="button" data-act="promo">' + ICON.download + 'Promotiemateriaal</button>' +
          (c.published ? '<button class="zk-btn ghost sm" type="button" data-act="share">' + ICON.qr + 'QR-code en link</button><a class="zk-btn ghost sm" href="/zakelijk/flyer/#' + esc(c.id) + '" target="_blank" rel="noopener">' + ICON.print + 'Flyer<span class="sr-only"> (opent in een nieuw venster)</span></a>'
            : approved ? '<button class="zk-btn ghost sm" type="button" data-act="publish">' + ICON.upload + "Online zetten</button>" : "") +
          '<button class="zk-btn ghost sm" type="button" data-act="members">' + ICON.users + "Leden</button></div></div></article>";
      }).join("") + "</div>";
    }
    panel.innerHTML = html;
    var nb = $("#zkNew"); if (nb) nb.addEventListener("click", function () { dash.edit = null; dash.sub = "edit"; render(); });
    panel.querySelectorAll(".zk-card button[data-act]").forEach(function (btn) {
      btn.addEventListener("click", async function () {
        var id = btn.closest(".zk-card").dataset.id, card = cards.filter(function (c) { return c.id === id; })[0];
        if (btn.dataset.act === "edit") { dash.edit = card; dash.sub = "edit"; render(); }
        if (btn.dataset.act === "share") shareModal(card, btn);
        if (btn.dataset.act === "promo") promoModal(card, btn);
        if (btn.dataset.act === "members") { dash.edit = card; dash.tab = "overzicht"; history.pushState(null, "", "#overzicht"); dash.sub = "members"; render(); }
        if (btn.dataset.act === "publish") {
          btn.disabled = true;
          try { await rpc("pasr_business_card_save", { p_card: { id: card.id, name: card.name, reward: card.reward, stamps_total: card.stamps_total, color: card.color, published: true } }, true); await refresh(); toast("Je kaart staat online"); }
          catch (e) { btn.disabled = false; toast(nice(e)); }
        }
      });
    });
  };

  function modal(label, html, opener) {
    var m = document.createElement("div");
    m.className = "zk-modal";
    m.innerHTML = '<div role="dialog" aria-modal="true" aria-label="' + esc(label) + '" tabindex="-1">' + html + "</div>";
    document.body.appendChild(m);
    var box = m.firstChild;
    var close = function () { m.remove(); document.removeEventListener("keydown", key); if (opener && opener.focus) opener.focus(); };
    function key(e) {
      if (e.key === "Escape") return close();
      if (e.key !== "Tab") return;
      var f = box.querySelectorAll("a[href], button:not([disabled]), input, select, textarea"); if (!f.length) return;
      if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus(); }
      else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus(); }
    }
    document.addEventListener("keydown", key);
    m.addEventListener("click", function (e) { if (e.target === m) close(); });
    var first = box.querySelector("button, a[href], input"); (first || box).focus();
    return { el: box, close: close };
  }
  function promoModal(card, opener) {
    var md = modal("Promotiemateriaal " + card.name,
      '<div id="zkPromoMount"></div><p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="promoClose">Sluiten</button></p>',
      opener);
    if (window.PasrPromo) window.PasrPromo.mount($("#zkPromoMount", md.el), card);
    else $("#zkPromoMount", md.el).textContent = "Promotiemateriaal is tijdelijk niet beschikbaar.";
    $("#promoClose", md.el).addEventListener("click", md.close);
  }
    function shareModal(card, opener) {
    var url = joinUrl(card.id);
    var md = modal("QR-code en link van " + card.name,
      '<h2>Laat klanten aansluiten</h2><p>Hang de QR-code bij de kassa of deel de link. Met Pasr opent de kaart in de app; zonder app werkt hij in de browser.</p>' +
      '<div class="zk-qr"><div class="qr" role="img" aria-label="QR-code naar ' + esc(url) + '">' + qrSvg(url) + '</div><div><div class="zk-link">' + esc(url) + '</div><div class="zk-actions" style="margin-top:10px">' +
      '<button class="zk-btn sm" type="button" id="mCopy">' + ICON.link + 'Kopieer link</button>' + (navigator.share ? '<button class="zk-btn ghost sm" type="button" id="mShare">Delen</button>' : "") +
      '<button class="zk-btn ghost sm" type="button" id="mPng">' + ICON.download + 'QR als afbeelding</button>' +
      '<a class="zk-btn ghost sm" href="/zakelijk/flyer/#' + esc(card.id) + '" target="_blank" rel="noopener">' + ICON.download + "Promotiemateriaal</a></div></div></div>" +
      '<p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="mClose">Sluiten</button></p>', opener);
    $("#mClose", md.el).addEventListener("click", md.close);
    $("#mCopy", md.el).addEventListener("click", function () { copy(url); });
    var sh = $("#mShare", md.el); if (sh) sh.addEventListener("click", function () { navigator.share({ title: card.name, text: "Spaar stempels bij " + card.business + " met Pasr.", url: url }).catch(function () {}); });
    $("#mPng", md.el).addEventListener("click", function () {
      var q = qrcode(0, "M"); q.addData(url); q.make();
      var a = document.createElement("a"); a.href = q.createDataURL(16, 4); a.download = "pasr-qr-" + card.name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + ".gif"; a.click();
    });
  }

  var SWATCHES = ["#6A5CFF", "#17162A", "#E30613", "#FF6B57", "#E2683C", "#F2B705", "#2ED3A6", "#12A77E", "#0A84FF", "#7B4B2A", "#AF52DE", "#FF375F"];

  function editView(panel, b) {
    var c = dash.edit || { name: "", reward: "", stamps_total: 10, color: "#6A5CFF", logo: null, published: false };
    var approved = b.status === "approved";
    var state = { name: c.name, reward: c.reward, stamps_total: c.stamps_total, color: c.color, logo: c.logo, business: b.name, city: b.city, text_color: c.id ? undefined : null };
    panel.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="cBack">' + ICON.back + "Kaarten</button></p>" +
      panelTitle(c.id ? "Kaart bewerken" : "Nieuwe kaart", c.id ? esc(c.name) : "Je ziet rechts meteen hoe je klant hem ziet.") +
      '<div class="zk-editor"><form id="zkCard" class="zk-panel zk-form" novalidate>' +
      '<label for="cName">Naam van de kaart</label><input id="cName" maxlength="40" placeholder="bijv. Koffiekaart" value="' + esc(c.name) + '" required>' +
      '<label for="cReward">Beloning</label><input id="cReward" maxlength="80" placeholder="bijv. 1 gratis koffie" value="' + esc(c.reward) + '" required>' +
      '<label for="cTotal">Aantal stempels: <output id="cTotOut" for="cTotal">' + c.stamps_total + '</output></label><input id="cTotal" type="range" min="2" max="30" value="' + c.stamps_total + '">' +
      '<fieldset class="zd-fs"><legend>Kleur</legend><span class="row"><input id="cColor" type="color" value="' + esc(c.color) + '" aria-label="Eigen kleur kiezen"><span class="swatches">' + SWATCHES.map(function (s) { return '<button type="button" data-c="' + s + '" style="background:' + s + '" aria-label="Kleur ' + s + '"></button>'; }).join("") + "</span></span></fieldset>" +
      '<div class="zk-brand" id="cBrand" role="status" aria-live="polite"></div>' +
      '<label for="cLogo">Logo <span class="zd-opt">(PNG of JPEG, vierkant werkt het best)</span></label><span class="row"><input id="cLogo" type="file" accept="image/png,image/jpeg,image/webp"><button type="button" class="zk-btn ghost sm" id="cNoLogo">Geen logo</button></span>' +
      '<label class="check"><input id="cPub" type="checkbox"' + (c.published && approved ? " checked" : "") + (approved ? "" : " disabled") + "> Online: klanten kunnen aansluiten" + (approved ? "" : " (kan na goedkeuring)") + "</label>" +
      '<div class="row"><button class="zk-btn" type="submit">Opslaan</button><button class="zk-btn ghost" type="button" id="cCancel">Annuleren</button>' + (c.id ? '<button class="zk-btn ghost danger" type="button" id="cDel">' + ICON.trash + "Verwijderen</button>" : "") + '</div><p class="zk-msg" id="cMsg" role="status" aria-live="polite"></p></form>' +
      '<div class="preview"><div id="cPrev" style="width:100%"></div><p class="zd-help">Zo ziet je klant de kaart in Pasr en in de browser.</p><div class="zi-seg" id="cDemo" role="group" aria-label="Voorbeeld"><button type="button" data-n="0" aria-pressed="false">Leeg</button><button type="button" data-n="half" aria-pressed="false">Half vol</button><button type="button" data-n="full" aria-pressed="false">Vol</button></div></div></div>';
    var demo = null;
    function draw() {
      var n = demo === "half" ? Math.floor(state.stamps_total / 2) : demo === "full" ? state.stamps_total : demo === 0 ? 0 : null;
      $("#cPrev").innerHTML = stampCard({ name: state.name || "Naam van de kaart", reward: state.reward || "Je beloning", stamps_total: state.stamps_total, color: state.color, logo: state.logo, business: state.business, city: state.city, text_color: state.text_color === undefined ? c.text_color : state.text_color }, n);
    }
    draw();
    // huisstijl van de website (functie business-brand): bij een nieuwe kaart vanzelf, anders met de knop
    async function fetchBrand(auto) {
      var box = $("#cBrand"); if (!box) return;
      if (!b.website) { box.innerHTML = auto ? "" : '<p class="small">Vul je website in bij <a href="#instellingen">Instellingen</a>, dan nemen we je logo en kleur automatisch over.</p>'; return; }
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
    if (!c.id || dash.rebrand) { dash.rebrand = false; fetchBrand(!c.id); }
    else $("#cBrand").innerHTML = b.website ? '<p class="small"><button type="button" class="zk-btn ghost sm" id="cRebrand">' + ICON.palette + "Huisstijl ophalen van je website</button></p>" : "";
    var rb0 = $("#cRebrand"); if (rb0) rb0.addEventListener("click", function () { fetchBrand(false); });
    $("#cName").addEventListener("input", function (e) { state.name = e.target.value; draw(); });
    $("#cReward").addEventListener("input", function (e) { state.reward = e.target.value; draw(); });
    $("#cTotal").addEventListener("input", function (e) { state.stamps_total = Number(e.target.value); $("#cTotOut").textContent = e.target.value; draw(); });
    $("#cColor").addEventListener("input", function (e) { state.color = e.target.value.toUpperCase(); state.text_color = null; draw(); });
    panel.querySelectorAll(".swatches button").forEach(function (s) { s.addEventListener("click", function () { state.color = s.dataset.c; state.text_color = null; $("#cColor").value = s.dataset.c; draw(); }); });
    $("#cDemo").querySelectorAll("button").forEach(function (s) {
      s.addEventListener("click", function () {
        demo = s.dataset.n === "0" ? 0 : s.dataset.n; draw();
        $("#cDemo").querySelectorAll("button").forEach(function (x) { x.setAttribute("aria-pressed", String(x === s)); });
      });
    });
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
    var back = function () { dash.sub = null; dash.edit = null; render(); };
    $("#cBack").addEventListener("click", back); $("#cCancel").addEventListener("click", back);
    var del = $("#cDel");
    if (del) del.addEventListener("click", function () {
      var md = modal("Kaart verwijderen", '<h2>' + esc(c.name) + ' verwijderen?</h2><p>Alle leden en stempels van deze kaart gaan ook weg; het logboek blijft staan. Dit kan niet ongedaan worden gemaakt.</p>' +
        '<p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="dNo">Annuleren</button><button class="zk-btn danger-solid" type="button" id="dYes">' + ICON.trash + "Verwijderen</button></p>", del);
      $("#dNo", md.el).addEventListener("click", md.close);
      $("#dYes", md.el).addEventListener("click", async function (ev) {
        ev.currentTarget.disabled = true;
        try { await rpc("pasr_business_card_delete", { p_card: c.id }, true); md.close(); dash.sub = null; dash.edit = null; await refresh(); toast("Kaart verwijderd"); }
        catch (e) { md.close(); setMsg($("#cMsg"), nice(e)); }
      });
    });
    $("#zkCard").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      if (!state.name.trim()) { $("#cName").focus(); return setMsg($("#cMsg"), "Geef de kaart een naam."); }
      if (!state.reward.trim()) { $("#cReward").focus(); return setMsg($("#cMsg"), "Vul de beloning in."); }
      var btn = ev.target.querySelector("button[type=submit]"); btn.disabled = true;
      try {
        var payload = { name: state.name, reward: state.reward, stamps_total: state.stamps_total, color: state.color.toUpperCase(), published: $("#cPub").checked, logo: state.logo || null };
        if (state.text_color !== undefined) payload.text_color = state.text_color;
        if (c.id) payload.id = c.id;
        await rpc("pasr_business_card_save", { p_card: payload }, true);
        dash.sub = null; dash.edit = null; await refresh(); toast("Kaart opgeslagen");
      } catch (e) { setMsg($("#cMsg"), /bad_logo/.test(e.message) ? "Dit logo werkt niet. Kies een PNG of JPEG." : /card_limit/.test(e.message) ? "Je kunt hoogstens 5 kaarten maken." : nice(e)); btn.disabled = false; }
    });
    $("#cName").focus({ preventScroll: true });
  }

  // ---- Scannen: zelfde scanner als pasr.nl/zakelijk/scan ----
  VIEWS.scannen = function (panel, b) {
    panel.innerHTML = panelTitle("Scannen", "Scan de QR-code van je klant, of typ de code. " + (b.role === "owner" ? "Werkt ook voor je medewerkers." : "Je geeft stempels voor " + esc(b.name) + ".")) + '<div id="zdScan" class="zk-scan zd-scan"></div>';
    mountScanner($("#zdScan"), { auto: false, zaak: b });
  };

  // ---- Medewerkers: uitnodigen en intrekken ----
  VIEWS.medewerkers = function (panel, b) {
    panel.innerHTML = panelTitle("Medewerkers", "Medewerkers loggen in met een eigen Pasr-account en kunnen alleen scannen: stempels geven, belonen en ongedaan maken.") +
      '<div class="zd-two"><div class="zk-panel"><h3>Medewerker uitnodigen</h3>' +
      '<form id="stInv" class="zk-form" novalidate><label for="stName">Naam</label><input id="stName" maxlength="60" required placeholder="bijv. Sanne" autocomplete="off">' +
      '<label for="stMail">E-mailadres <span class="zd-opt">(optioneel, alleen ter herkenning)</span></label><input id="stMail" type="email" maxlength="200" autocomplete="off">' +
      '<div class="row"><button class="zk-btn" type="submit">' + ICON.plus + 'Uitnodiging maken</button></div><p class="zk-msg" id="stMsg" role="status" aria-live="polite"></p></form><div id="stLink"></div></div>' +
      '<div class="zk-panel" id="stList"><h3>Wie kan scannen</h3><p class="zk-empty">Laden…</p></div></div>';
    $("#stInv").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      if (!$("#stName").value.trim()) { $("#stName").focus(); return setMsg($("#stMsg"), "Vul de naam van je medewerker in."); }
      var btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        var r = await rpc("pasr_business_staff_invite", { p_business: b.id, p_name: $("#stName").value, p_email: $("#stMail").value.trim() || null }, true);
        $("#stName").value = ""; $("#stMail").value = ""; setMsg($("#stMsg"), "");
        $("#stLink").innerHTML = '<div class="zd-invite"><div class="qr" role="img" aria-label="QR-code van de uitnodiging">' + qrSvg(r.link) + '</div><div><p><b>Uitnodiging klaar.</b> Stuur deze link naar je medewerker. Hij werkt 14 dagen en één keer.</p><div class="zk-link">' + esc(r.link) + "</div>" +
          '<div class="zk-actions"><button class="zk-btn sm" type="button" id="stCopy">' + ICON.link + "Kopieer link</button>" +
          (navigator.share ? '<button class="zk-btn ghost sm" type="button" id="stShare">Delen</button>' : "") + "</div></div></div>";
        $("#stCopy").addEventListener("click", function () { copy(r.link); });
        var sh = $("#stShare"); if (sh) sh.addEventListener("click", function () { navigator.share({ title: "Uitnodiging " + b.name, text: "Je bent uitgenodigd om stempels te geven bij " + b.name + " met Pasr Zakelijk.", url: r.link }).catch(function () {}); });
        $("#stCopy").focus();
        loadStaff();
      } catch (e) { setMsg($("#stMsg"), nice(e)); }
      btn.disabled = false;
    });
    async function loadStaff() {
      var box = $("#stList"); if (!box) return;
      try {
        var list = await rpc("pasr_business_staff_list", { p_business: b.id }, true);
        var rows = list.map(function (x) {
          var st = x.revoked ? "Ingetrokken " + nlDate(x.revoked_at) : x.pending ? (x.expired ? "Uitnodiging verlopen" : "Uitnodiging open") : "Actief sinds " + nlDate(x.accepted_at || x.created_at);
          var cls = x.revoked || x.expired ? "" : x.pending ? "wait" : "on";
          return { attr: x.revoked ? ' class="undone"' : "", cells: [
            "<b>" + esc(x.name || (x.role === "owner" ? "Jij" : "—")) + "</b>" + (x.email ? "<br><small>" + esc(x.email) + "</small>" : ""),
            x.role === "owner" ? "Eigenaar" : "Medewerker",
            '<span class="zk-pill ' + cls + '">' + esc(st) + "</span>",
            x.role !== "owner" && !x.revoked ? '<button class="zk-btn ghost sm danger" type="button" data-revoke="' + esc(x.id) + '" data-name="' + esc(x.name || "") + '">' + (x.pending ? "Uitnodiging intrekken" : "Toegang intrekken") + "</button>" : ""] };
        });
        box.innerHTML = "<h3>Wie kan scannen</h3>" + table(["Naam", "Rol", "Status", '<span class="sr-only">Actie</span>'], rows, "staff");
        box.querySelectorAll("button[data-revoke]").forEach(function (btn) {
          btn.addEventListener("click", function () {
            var md = modal("Toegang intrekken", "<h2>Toegang intrekken?</h2><p>" + esc(btn.dataset.name || "Deze medewerker") + " kan daarna niet meer scannen voor " + esc(b.name) + ". Het logboek blijft staan.</p>" +
              '<p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="rNo">Annuleren</button><button class="zk-btn danger-solid" type="button" id="rYes">Intrekken</button></p>', btn);
            $("#rNo", md.el).addEventListener("click", md.close);
            $("#rYes", md.el).addEventListener("click", async function (ev) {
              ev.currentTarget.disabled = true;
              try { await rpc("pasr_business_staff_revoke", { p_staff: btn.dataset.revoke }, true); md.close(); toast("Ingetrokken"); loadStaff(); }
              catch (e) { md.close(); toast(nice(e)); }
            });
          });
        });
      } catch (e) { box.innerHTML = '<h3>Wie kan scannen</h3><p class="zk-empty">' + esc(nice(e)) + "</p>"; }
    }
    loadStaff();
  };

  // ---- Instellingen: zaakgegevens, scannen, Vindbaar in Pasr en adres ----
  VIEWS.instellingen = function (panel, b) {
    panel.innerHTML = panelTitle("Instellingen", "Gegevens van je zaak en hoe scannen werkt.") +
      '<div class="zd-two">' +
      '<form id="bizForm" class="zk-panel zk-form" novalidate><h3>Gegevens van je zaak</h3>' + bizFields(b) +
      '<div class="row"><button class="zk-btn" type="submit">Opslaan</button></div><p class="zk-msg" id="bizMsg" role="status" aria-live="polite"></p><div id="bizBrand"></div></form>' +
      '<div class="zd-stack"><form id="setForm" class="zk-panel zk-form" novalidate><h3>Scannen</h3>' +
      '<label for="setCool">Afkoeltijd in minuten</label><input id="setCool" type="number" inputmode="numeric" min="0" max="1440" aria-describedby="setCoolHelp" value="' + esc(b.cooldown_minutes == null ? 5 : b.cooldown_minutes) + '">' +
      '<small id="setCoolHelp" class="zd-help">Zo lang na een stempel krijgt dezelfde klant geen nieuwe. 0 = uit, hoogstens 1440 (een dag).</small>' +
      '<label for="setMax">Hoogstens zoveel stempels per scan</label><input id="setMax" type="number" inputmode="numeric" min="1" max="30" aria-describedby="setMaxHelp" value="' + esc(b.max_per_scan == null ? 10 : b.max_per_scan) + '">' +
      '<small id="setMaxHelp" class="zd-help">Van 1 tot 30. Bij het scannen kies je zelf hoeveel, tot dit maximum.</small>' +
      '<div class="row"><button class="zk-btn" type="submit">Opslaan</button></div><p class="zk-msg" id="setMsg" role="status" aria-live="polite"></p></form>' +
      '<form id="findForm" class="zk-panel zk-form" novalidate><h3>Vindbaar in Pasr</h3>' +
      '<label class="check zd-switch"><input id="setListed" type="checkbox" role="switch"' + (b.listed === false ? "" : " checked") + '><span>Klanten vinden je stempelkaart in de app Pasr bij Kaart toevoegen › Stempelkaart</span></label>' +
      '<label for="setAddr">Adres <span class="zd-opt">(voor In de buurt)</span></label>' +
      '<div class="zd-combo"><input id="setAddr" maxlength="200" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="addrList" aria-describedby="addrHelp" placeholder="Straat en huisnummer, plaats" value="' + esc(b.address || "") + '">' +
      '<ul id="addrList" role="listbox" aria-label="Gevonden adressen" hidden></ul></div>' +
      '<small id="addrHelp" class="zd-help">' + locText(b.lat, b.lng) + "</small>" +
      '<div class="row"><button class="zk-btn" type="submit">Opslaan</button></div><p class="zk-msg" id="findMsg" role="status" aria-live="polite"></p></form></div></div>';
    $("#bizForm").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var btn = ev.target.querySelector("button[type=submit]"); btn.disabled = true;
      var oldWeb = b.website || "", args = bizArgs();
      try {
        await rpc("pasr_business_register", args, true);
        await refresh(); setMsg($("#bizMsg"), "Opgeslagen.", true);
        if (args.p_website && args.p_website !== oldWeb && (current().cards || []).length) {
          $("#bizBrand").innerHTML = '<div class="zd-hint"><p>Nieuwe website. Wil je je logo en kleur er opnieuw van ophalen voor je kaarten?</p><button class="zk-btn sm" type="button" id="bizRebrand">' + ICON.palette + "Huisstijl ophalen</button></div>";
          $("#bizRebrand").addEventListener("click", function () { dash.edit = current().cards[0]; dash.rebrand = true; dash.tab = "kaarten"; history.pushState(null, "", "#kaarten"); dash.sub = "edit"; render(); });
        }
      } catch (e) { setMsg($("#bizMsg"), /bad_name/.test(e.message) ? "Vul de naam van je zaak in (minstens 2 tekens)." : nice(e)); }
      btn.disabled = false;
    });
    $("#setForm").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var cd = Number($("#setCool").value), mx = Number($("#setMax").value);
      if (!Number.isInteger(cd) || cd < 0 || cd > 1440) { $("#setCool").focus(); return setMsg($("#setMsg"), "Afkoeltijd moet tussen 0 en 1440 minuten liggen."); }
      if (!Number.isInteger(mx) || mx < 1 || mx > 30) { $("#setMax").focus(); return setMsg($("#setMsg"), "Max per scan moet tussen 1 en 30 liggen."); }
      await saveSettings(ev.target, $("#setMsg"), { cooldown_minutes: cd, max_per_scan: mx });
    });
    // adres zoeken via de Locatieserver van PDOK (Kadaster): alleen Nederlandse adressen, geeft ook de locatie
    var addr = $("#setAddr"), list = $("#addrList"), picked = null, timer = null, active = -1, found = [];
    function closeList() { list.hidden = true; addr.setAttribute("aria-expanded", "false"); addr.removeAttribute("aria-activedescendant"); active = -1; }
    function choose(i) {
      var d = found[i]; if (!d) return;
      var m = /POINT\(([-\d.]+) ([-\d.]+)\)/.exec(d.centroide_ll || "");
      picked = { address: d.weergavenaam, lat: m ? Number(m[2]) : null, lng: m ? Number(m[1]) : null };
      addr.value = d.weergavenaam; closeList();
      $("#addrHelp").textContent = picked.lat != null ? "Locatie gevonden. Sla op om hem te bewaren." : locText(null);
    }
    addr.addEventListener("input", function () {
      picked = null; clearTimeout(timer);
      var q = addr.value.trim(); if (q.length < 4) return closeList();
      timer = setTimeout(async function () {
        try {
          var res = await fetch("https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?rows=6&fq=type:adres&fl=id,weergavenaam,centroide_ll&q=" + encodeURIComponent(q), { referrerPolicy: "no-referrer" });
          found = ((await res.json()).response || {}).docs || [];
        } catch (e) { found = []; }
        if (!found.length) return closeList();
        list.innerHTML = found.map(function (d, i) { return '<li role="option" id="addr-' + i + '" aria-selected="false" data-i="' + i + '">' + esc(d.weergavenaam) + "</li>"; }).join("");
        list.hidden = false; addr.setAttribute("aria-expanded", "true");
        list.querySelectorAll("li").forEach(function (li) { li.addEventListener("mousedown", function (e) { e.preventDefault(); choose(Number(li.dataset.i)); }); });
      }, 300);
    });
    addr.addEventListener("keydown", function (e) {
      if (list.hidden) return;
      var items = list.querySelectorAll("li");
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault(); active = (active + (e.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
        items.forEach(function (li, i) { li.setAttribute("aria-selected", String(i === active)); });
        addr.setAttribute("aria-activedescendant", "addr-" + active);
      } else if (e.key === "Enter" && active >= 0) { e.preventDefault(); choose(active); }
      else if (e.key === "Escape") closeList();
    });
    addr.addEventListener("blur", function () { setTimeout(closeList, 150); });
    $("#findForm").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var a = addr.value.replace(/\s+/g, " ").trim(), s = { listed: $("#setListed").checked };
      if (picked && picked.address === a) { s.address = a; s.lat = picked.lat; s.lng = picked.lng; }
      else if (a !== (b.address || "")) { s.address = a || null; s.lat = null; s.lng = null; }   // ander adres zonder gevonden locatie: oude locatie vervalt
      await saveSettings(ev.target, $("#findMsg"), s);
      $("#addrHelp").textContent = locText(current().lat, current().lng);
    });
    async function saveSettings(form, msg, settings) {
      var btn = form.querySelector("button[type=submit]"); btn.disabled = true;
      try {
        var nb = await rpc("pasr_business_settings_save", { p_business: b.id, p_settings: settings }, true);
        var me = current(); Object.keys(nb).forEach(function (k) { if (k !== "cards") me[k] = nb[k]; }); b = me;
        setMsg(msg, "Opgeslagen.", true);
      } catch (e) { setMsg(msg, nice(e)); }
      btn.disabled = false;
    }
  };
  function locText(lat, lng) {
    return lat != null && lng != null ? "Locatie bekend: je kaart verschijnt bij In de buurt. Kies een adres uit de lijst om hem te wijzigen."
      : "Typ je adres en kies het uit de lijst, dan verschijnt je kaart bij In de buurt. Zonder locatie ben je vindbaar op naam en plaats.";
  }

  // ---- Account: wachtwoord (bestaande Pasr-flow), uitloggen, account verwijderen ----
  VIEWS["mijn-account"] = function (panel, b) {
    var email = (session && session.email) || "";
    panel.innerHTML = panelTitle("Account", "Je Pasr-account, hetzelfde als in de app Pasr Zakelijk en in Pasr.") +
      '<div class="zd-two"><div class="zk-panel"><h3>Ingelogd als</h3><p class="zd-email">' + ICON.mail + esc(email) + "</p>" +
      '<h3>Wachtwoord</h3><p>Je krijgt een mail met een link om een nieuw wachtwoord te kiezen.</p><div class="zk-actions"><button class="zk-btn ghost" type="button" id="acPw">' + ICON.key + 'Stuur mail voor nieuw wachtwoord</button></div><p class="zk-msg" id="acMsg" role="status" aria-live="polite"></p>' +
      '<h3>Uitloggen</h3><div class="zk-actions"><button class="zk-btn ghost" type="button" id="acOut">' + ICON.logout + "Uitloggen op dit apparaat</button></div></div>" +
      '<div class="zk-panel zd-danger"><h3>Account verwijderen</h3><p>Je Pasr-account wordt verwijderd, ook in de app Pasr. Ben je eigenaar, dan verdwijnen ook je zaak, kaarten en leden. Dit kan niet ongedaan worden gemaakt.</p>' +
      '<p><a href="#account-verwijderen" id="acDel" class="zd-dangerlink">' + ICON.trash + "Account verwijderen…</a></p></div></div>";
    $("#acOut").addEventListener("click", logout);
    $("#acPw").addEventListener("click", async function (ev) {
      var btn = ev.currentTarget; btn.disabled = true;
      try { await http("auth/v1/recover?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: email }); setMsg($("#acMsg"), "Mail verstuurd naar " + email + ". Kijk ook in je spam.", true); }
      catch (e) { setMsg($("#acMsg"), nice(e)); }
      btn.disabled = false;
    });
    $("#acDel").addEventListener("click", function (e) {
      e.preventDefault();
      var opener = e.currentTarget;
      var md = modal("Account verwijderen", "<h2>Account verwijderen?</h2><p>Typ <b>VERWIJDER</b> om te bevestigen. " + (ownBiz() ? "Je zaak <b>" + esc(ownBiz().name) + "</b>, je kaarten en alle leden worden ook verwijderd." : "Je toegang als medewerker vervalt.") + "</p>" +
        '<form id="dForm" class="zk-form" novalidate><label for="dConfirm">Bevestiging</label><input id="dConfirm" autocomplete="off" autocapitalize="characters" spellcheck="false">' +
        '<p class="zk-msg" id="dMsg" role="status" aria-live="polite"></p><p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="dNo">Annuleren</button><button class="zk-btn danger-solid" type="submit" id="dYes">' + ICON.trash + "Definitief verwijderen</button></p></form>", opener);
      $("#dNo", md.el).addEventListener("click", md.close);
      $("#dConfirm", md.el).focus();
      $("#dForm", md.el).addEventListener("submit", async function (ev) {
        ev.preventDefault();
        if ($("#dConfirm", md.el).value.trim().toUpperCase() !== "VERWIJDER") { $("#dConfirm", md.el).focus(); return setMsg($("#dMsg", md.el), "Typ VERWIJDER om te bevestigen."); }
        $("#dYes", md.el).disabled = true;
        try {
          await rpc("pasr_delete_account", {}, true);
          md.close(); session = null; saveSession(null); dash.me = null; store(BIZ_KEY, null); navState();
          dashRoot().innerHTML = '<section class="auth ok zd-auth"><div class="badge">' + ICON.stamp + '</div><h1>Account verwijderd</h1><p>Je Pasr-account en alles wat erbij hoorde is verwijderd. Bedankt dat je Pasr gebruikte.</p><p><a class="zk-btn" href="/zakelijk/">Naar Pasr voor ondernemers</a></p></section>';
        } catch (e2) { $("#dYes", md.el).disabled = false; setMsg($("#dMsg", md.el), nice(e2)); }
      });
    });
  };

  // ---------------------------------------------------------------- join-pagina: pasr.nl/zakelijk/kaart/<id>/ (en de oude #<id>)
  async function joinPage() {
    var root = $("#zk-join");
    var fromPath = location.pathname.match(/^\/zakelijk\/kaart\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/?$/i);
    var id = fromPath ? fromPath[1].toLowerCase() : location.hash.slice(1).toLowerCase();
    // Oude link (#<id>): door naar de eigen pagina van de kaart, als die er is. Geen pagina (net gepubliceerd, of de
    // demo-kaart voor App Review): hier blijven, dan werkt hij gewoon zoals altijd.
    if (!fromPath && /^[0-9a-f-]{36}$/.test(id) && !/[?&]hier=1/.test(location.search)) {
      try {
        var head = await fetch("/zakelijk/kaart/" + id + "/", { method: "HEAD", cache: "no-store" });
        if (head.ok) { location.replace("/zakelijk/kaart/" + id + "/"); return; }
      } catch (e) { /* offline: gewoon hier */ }
    }
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
        '<p class="note">Deze kaart staat in deze browser. Met Bewaar in Pasr gaan je stempels mee naar de app. Met de gratis app Pasr (<a href="' + APP_STORE + '" rel="noopener">iPhone</a> of <a href="/android/">Android</a>) heb je hem altijd bij de hand, ook in Apple Wallet of Google Wallet.</p>';
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
        '<div class="actions"><a class="btn btn-primary" href="pasr://zakelijk#' + esc(id) + '">Open in Pasr</a><a class="btn btn-ghost" href="' + APP_STORE + '" rel="noopener">Pasr voor iPhone</a><a class="btn btn-ghost" href="/android/">Pasr voor Android</a></div>' +
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

  // ---------------------------------------------------------------- scanner (pasr.nl/zakelijk/scan en de tab Scannen)
  function codeFrom(text) {
    var t = String(text || "").trim().toUpperCase();
    var m = t.match(/PZ(?:[A-HJ-NP-Z2-9]{14}|[A-HJ-NP-Z2-9]{10})(?![A-HJ-NP-Z2-9])/);
    return m ? m[0] : null;
  }
  var scanner = null;   // { stop } van de scanner die nu loopt
  function stopScanner() { if (scanner) { scanner.stop(); scanner = null; } }

  /** Scanner in `root`. opts.auto = camera meteen aan (losse scanpagina); anders met de knop Camera aan. */
  function mountScanner(root, opts) {
    stopScanner();
    var DEVICE = "Webscanner";
    root.innerHTML =
      '<div class="zk-cam" id="sCam"><video id="sVideo" playsinline muted aria-hidden="true"></video><span class="frame" aria-hidden="true"></span>' +
      '<div class="zk-cam-off" id="sOff"><span>' + ICON.camera + '</span><p>Scan de QR-code op de kaart van je klant.</p><button class="zk-btn mint" type="button" id="sStart">' + ICON.camera + "Camera aan</button></div>" +
      '<span class="hint" id="sHint" aria-live="polite"></span></div>' +
      '<form id="sManual" class="zk-form zd-manual" novalidate><label for="sCode">Of typ de code van je klant</label><span class="row"><input id="sCode" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="PZ…" aria-describedby="sCodeHelp"><button class="zk-btn dark" type="submit">' + ICON.search + "Zoek</button></span>" +
      '<small id="sCodeHelp" class="zd-help">De code staat onder de QR-code en begint met PZ.</small></form>' +
      '<p class="zk-msg" id="sMsg" role="status" aria-live="assertive"></p><div id="sResult"></div>';
    var video = $("#sVideo", root), busy = false, last = "", lastAt = 0, stream = null, alive = true, undoTimer = null;
    var detector = ("BarcodeDetector" in window) ? new window.BarcodeDetector({ formats: ["qr_code"] }) : null;
    var canvas = document.createElement("canvas"), ctx = canvas.getContext("2d", { willReadFrequently: true });
    function stop() {
      alive = false; clearInterval(undoTimer);
      if (stream) { stream.getTracks().forEach(function (t) { t.stop(); }); stream = null; }
    }
    scanner = { stop: stop };

    async function show(code) {
      busy = true; setMsg($("#sMsg", root), "");
      try {
        var m = await rpc("pasr_business_scan", { p_code: code }, true);
        result(m);
        if (navigator.vibrate) navigator.vibrate(40);
      } catch (e) { setMsg($("#sMsg", root), nice(e)); $("#sResult", root).innerHTML = ""; }
      busy = false;
    }
    function result(m) {
      // aantal-kiezer: standaard 1, tot het maximum per scan van de zaak (1 tot 30)
      var amount = 1, maxAmt = Math.max(1, Math.min(30, Number(m.max_per_scan) || 10)), full = m.stamps_count >= m.stamps_total;
      var cool = m.cooldown_until && new Date(m.cooldown_until) > new Date();
      clearInterval(undoTimer);
      $("#sResult", root).innerHTML = '<div class="zk-result" id="sBox" tabindex="-1" aria-label="Resultaat van de scan">' + stampCard(m.card, Math.min(m.stamps_count, m.stamps_total)) +
        '<div class="big">' + m.stamps_count + " van " + m.stamps_total + " stempels</div>" +
        (full ? '<p class="zd-ready">' + ICON.gift + "Beloning klaar: <b>" + esc(m.reward) + "</b>" + (m.stamps_count > m.stamps_total ? " (" + (m.stamps_count - m.stamps_total) + " stempels blijven staan voor de volgende kaart)" : "") + "</p>" : "") +
        (cool ? '<p class="zk-msg bad">Afkoeltijd: deze klant kreeg net een stempel. De volgende kan vanaf ' + new Date(m.cooldown_until).toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" }) + ".</p>" : "") +
        '<div class="zk-amount"><label for="sAmt">Aantal stempels</label><span class="zk-stepper"><button class="zk-btn ghost" type="button" id="sMin" aria-label="Eén stempel minder" aria-controls="sAmt">−</button>' +
        '<input id="sAmt" type="number" inputmode="numeric" min="1" max="' + maxAmt + '" value="1">' +
        '<button class="zk-btn ghost" type="button" id="sPlus" aria-label="Eén stempel meer" aria-controls="sAmt">+</button></span><small>hoogstens ' + maxAmt + " per scan</small></div>" +
        '<div class="zk-actions zd-scanbtns"><button class="zk-btn mint" id="sStamp" type="button"' + (cool ? " disabled" : "") + ">" + ICON.stamp + '<span id="sStampTxt">Stempel erbij</span></button>' +
        '<button class="zk-btn coral" id="sRedeem" type="button"' + (full ? "" : " disabled") + ">" + ICON.gift + "Beloning inwisselen</button></div>" +
        (m.can_undo_event_id ? '<p class="zd-undo"><button class="zk-btn ghost sm" type="button" id="sUndo">' + ICON.undo + 'Ongedaan maken <span id="sUndoLeft"></span></button></p>' : "") +
        '<p class="zd-help">' + esc(m.card.business || "") + " · klant …" + esc(m.member_code_suffix || String(m.member_code || "").slice(-4)) + (m.rewards_redeemed ? " · " + m.rewards_redeemed + "× beloning gehad" : "") + "</p></div>";
      function setAmt(n) {
        amount = Math.max(1, Math.min(maxAmt, Math.round(Number(n)) || 1));
        $("#sAmt", root).value = amount;
        $("#sStampTxt", root).textContent = amount === 1 ? "Stempel erbij" : amount + " stempels erbij";
      }
      $("#sMin", root).addEventListener("click", function () { setAmt(amount - 1); });
      $("#sPlus", root).addEventListener("click", function () { setAmt(amount + 1); });
      $("#sAmt", root).addEventListener("change", function (e) { setAmt(e.target.value); });
      $("#sStamp", root).addEventListener("click", function (ev) { act(ev.currentTarget, "pasr_business_stamp", { p_code: m.member_code, p_amount: amount, p_device: DEVICE }, amount === 1 ? "Stempel gezet" : amount + " stempels gezet"); });
      $("#sRedeem", root).addEventListener("click", function (ev) {
        var btn = ev.currentTarget;
        var md = modal("Beloning inwisselen", "<h2>Beloning inwisselen?</h2><p>" + esc(m.reward) + ". Er gaan " + m.stamps_total + " stempels af.</p>" +
          '<p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="rwNo">Annuleren</button><button class="zk-btn coral" type="button" id="rwYes">' + ICON.gift + "Inwisselen</button></p>", btn);
        $("#rwNo", md.el).addEventListener("click", md.close);
        $("#rwYes", md.el).addEventListener("click", function () { md.close(); act(btn, "pasr_business_redeem", { p_code: m.member_code, p_device: DEVICE }, "Beloning ingewisseld"); });
      });
      var undo = $("#sUndo", root);
      if (undo) {
        // ongedaan maken kan 2 minuten na het eigen stempel (eigenaar: elk); de server beslist
        var until = Date.now() + 120000;
        if (!(m.event_id && m.event_id === m.can_undo_event_id) && m.last_stamp_at) until = Math.min(until, new Date(m.last_stamp_at).getTime() + 120000);
        var tickUndo = function () {
          var left = Math.round((until - Date.now()) / 1000);
          if (left <= 0 || !alive) { clearInterval(undoTimer); undo.remove(); return; }
          $("#sUndoLeft", root).textContent = "(" + Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0") + ")";
        };
        tickUndo(); undoTimer = setInterval(tickUndo, 1000);
        undo.addEventListener("click", function (ev) { act(ev.currentTarget, "pasr_business_undo", { p_event: m.can_undo_event_id, p_device: DEVICE }, "Ongedaan gemaakt"); });
      }
      var box = $("#sBox", root); box.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
    async function act(btn, fn, args, done) {
      btn.disabled = true;
      try { var m = await rpc(fn, args, true); result(m); $("#sBox", root).classList.add("zk-flash"); setMsg($("#sMsg", root), done, true); if (navigator.vibrate) navigator.vibrate(30); }
      catch (e) { btn.disabled = false; setMsg($("#sMsg", root), nice(e)); }
    }
    $("#sManual", root).addEventListener("submit", function (ev) {
      ev.preventDefault();
      var c = codeFrom($("#sCode", root).value.replace(/\s+/g, ""));
      if (!c) { $("#sCode", root).focus(); return setMsg($("#sMsg", root), "Een code begint met PZ en heeft 16 tekens (oudere codes 12)."); }
      show(c);
    });
    async function tick() {
      if (!stream || !alive) return;
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
    async function start() {
      $("#sHint", root).textContent = "Camera starten…";
      try {
        if (!window.jsQR && !detector) await loadScript("/assets/vendor/jsqr.min.js");
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false });
        if (!alive) return stop();
        video.srcObject = stream; await video.play();
        $("#sCam", root).classList.add("on"); $("#sHint", root).textContent = "Richt de camera op de QR-code van je klant";
        tick();
      } catch (e) {
        $("#sHint", root).textContent = "Geen camera: geef je browser toegang tot de camera, of typ de code hieronder.";
      }
    }
    $("#sStart", root).addEventListener("click", start);
    if (opts && opts.auto) start();
  }
  function loadScript(src) {
    return new Promise(function (ok, fail) { var s = document.createElement("script"); s.src = src; s.onload = ok; s.onerror = fail; document.head.appendChild(s); });
  }
  async function scanPage() {
    var root = $("#zk-scan");
    if (!ready) { root.innerHTML = "<p>Even niet beschikbaar.</p>"; return; }
    if (!session || !(await token())) {
      root.innerHTML = '<section class="auth"><h1>Eerst inloggen</h1><p>De scanner werkt met het account van je zaak, of met je eigen account als medewerker.</p><a class="zk-btn" href="/zakelijk/dashboard/">Inloggen</a></section>';
      return;
    }
    root.innerHTML = '<div class="zk-top"><div><span class="zk-kicker">Scanner</span><h1>Stempel geven</h1></div><a class="zk-btn ghost sm" href="/zakelijk/dashboard/">Dashboard</a></div><div id="sRoot"></div>';
    mountScanner($("#sRoot"), { auto: true });
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
        if (r.business.role === "owner") {
          // eigenaarsuitnodiging van Pasr (zaak klaargezet door het beheer): door naar het dashboard
          dash.me = null;
          return box("<h1>" + esc(r.business.name) + " is van jou</h1><p>Je bent nu eigenaar. In je dashboard beheer je je stempelkaarten, medewerkers en instellingen; met de scanner geef je stempels.</p>" +
            '<p style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center"><a class="zk-btn" href="/zakelijk/dashboard/">Naar je dashboard</a><a class="zk-btn ghost" href="' + appLink + '">Open in Pasr Zakelijk</a></p>');
        }
        box("<h1>Welkom bij " + esc(r.business.name) + "</h1><p>Je kunt nu stempels geven en belonen. Open de scanner op deze telefoon, of gebruik de app Pasr Zakelijk.</p>" +
          '<p style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center"><a class="zk-btn" href="/zakelijk/scan/">' + ICON.scan + 'Open de scanner</a><a class="zk-btn ghost" href="' + appLink + '">Open in Pasr Zakelijk</a></p>');
      } catch (e) { box("<h1>Dat lukte niet</h1><p>" + esc(nice(e)) + "</p>"); }
    }
    dash.afterLogin = accept;
    var owner = info.role === "owner";
    function intro() {
      box((owner
        ? "<h1>" + esc(info.business) + " staat voor je klaar</h1><p>Pasr heeft " + esc(info.business) + (info.city ? " in " + esc(info.city) : "") + " voor je klaargezet. Log in met je Pasr-account (of maak er gratis een) en je wordt eigenaar: je beheert de stempelkaarten, medewerkers en instellingen.</p>"
        : "<h1>Uitnodiging van " + esc(info.business) + "</h1><p>" + (info.name ? esc(info.name) + ", je" : "Je") + " bent uitgenodigd om stempels te geven bij " + esc(info.business) + (info.city ? " in " + esc(info.city) : "") + ". Je logt in met je eigen Pasr-account.</p>") +
        '<p style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center"><a class="zk-btn" href="' + appLink + '">Open in Pasr Zakelijk</a>' +
        '<button class="zk-btn ghost" type="button" id="invWeb">' + (owner ? (session ? "Zaak overnemen" : "Inloggen en zaak overnemen") : (session ? "Accepteren in de browser" : "Inloggen en accepteren")) + "</button></p>" +
        '<p style="font-size:14px">Nog geen Pasr Zakelijk? Download hem in de <a href="https://apps.apple.com/nl/app/pasrzakelijk/id6837907454" rel="noopener">App Store</a> of <a href="/zakelijk/download/">voor Android</a>, of gebruik de scanner in je browser.</p>');
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
    root.innerHTML = '<div class="pz-promo-intro"><h1>Promotiemateriaal</h1><p>Download professionele Pasr-banners van jouw echte stempelkaart in Licht en Donker.</p></div><div id="zkPromoPublic"></div>' +
      '<section class="pz-old-flyer"><h2>Flyer afdrukken</h2><p class="no-print"><button class="zk-btn" onclick="window.print()" type="button">' + ICON.print + 'Printen of bewaren als PDF</button></p>' +
      '<div class="flyer"><span class="zk-kicker">Digitale stempelkaart</span><h1>Spaar bij ' + esc(card.business) + '</h1>' +
      '<p style="font-size:20px;margin:0">' + card.stamps_total + ' stempels = <b>' + esc(card.reward) + '</b></p>' + stampCard(card, Math.ceil(card.stamps_total / 2)) +
      '<div class="qr">' + qrSvg(joinUrl(card.id)) + '</div><p style="margin:0;font-weight:700">Scan met je camera</p>' +
      '<ol><li>Scan de QR-code met de camera van je telefoon.</li><li>Bewaar de kaart in de gratis app Pasr, of gebruik hem in je browser.</li><li>Laat bij elke aankoop je kaart scannen voor een stempel.</li></ol>' +
      '<div class="foot"><img src="/assets/icon.png" alt="">pasr.nl</div></div></section>';
    if (window.PasrPromo) window.PasrPromo.mount($("#zkPromoPublic"), card, {print:true});
  
  }

  // ---------------------------------------------------------------- kop: na inloggen wordt Inloggen "Dashboard"
  function navState() {
    var a = $("[data-zk-login]"), s = $("[data-zk-signup]");
    if (!a) return;
    a.textContent = session ? "Dashboard" : "Inloggen";
    if (s) s.parentNode.hidden = !!session;
  }

  navState();
  var page = document.body.dataset.page;
  if (page === "zk-dashboard") {
    window.addEventListener("hashchange", function () { if (!session || dash.me) render(); });
    window.addEventListener("popstate", function () { dash.sub = null; dash.edit = null; render(); });
    render();
  }
  if (page === "zk-join") joinPage();
  if (page === "zk-scan") scanPage();
  if (page === "zk-flyer") flyerPage();
  if (page === "zk-invite") invitePage();
})();
