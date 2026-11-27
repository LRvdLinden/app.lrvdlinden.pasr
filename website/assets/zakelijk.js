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
    home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z"/></svg>',
    tag: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 12.2V4.5a1 1 0 0 1 1-1h7.7l8.3 8.3a1.4 1.4 0 0 1 0 2l-6.2 6.2a1.4 1.4 0 0 1-2 0z"/><circle cx="8" cy="8" r="1.4"/></svg>',
    code: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m8.5 7-5 5 5 5M15.5 7l5 5-5 5"/></svg>',
    calendar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
    pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.4"/></svg>',
    bars: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h16M6.5 16v-5M10.5 16V7M14.5 16v-7M18.5 16V5"/></svg>',
    more: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="5.5" cy="12" r="1.3" fill="currentColor"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/><circle cx="18.5" cy="12" r="1.3" fill="currentColor"/></svg>',
    bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0"/></svg>',
    down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="ic-down"><path d="m6 9 6 6 6-6"/></svg>',
    check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="ic-check"><path d="M5 12.5 10 17 19 7"/></svg>',
    ticket: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h13A1.5 1.5 0 0 1 20 7.5V10a2 2 0 0 0 0 4v2.5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 16.5V14a2 2 0 0 0 0-4z"/><path d="M14.5 6.5v11" stroke-dasharray="2 2.2"/></svg>',
    mcard: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M7 15h1M10 15h1M13 15h1M7 10h6"/></svg>',
    pct: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M19 5 5 19"/><circle cx="7" cy="7" r="2.2"/><circle cx="17" cy="17" r="2.2"/></svg>',
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
  window.PasrQrSvg = qrSvg;   // ook voor loyalty2.js (uitnodigingslink van een gezamenlijke actie)
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
    var meta = (s.user && s.user.user_metadata) || {}, first = String(meta.first_name || (session && session.first_name) || "").replace(/[<>]/g, "").trim().slice(0, 40);
    session = { access_token: s.access_token, refresh_token: s.refresh_token, expires_at: Date.now() + (s.expires_in || 3600) * 1000, email: (s.user && s.user.email) || (session && session.email) };
    if (first) session.first_name = first;
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
    var cm = communityError(e); if (cm) return cm;
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

  // Foutcodes van gezamenlijke acties (docs/community-invites.md); ook gebruikt door loyalty2.js.
  function communityError(e) {
    var m = String((e && e.message) || ""), h = String((e && e.hint) || "");
    var map = {
      invite_required: "Meedoen kan alleen met een uitnodiging van de organisator.",
      not_owner: "Alleen de eigenaar van de organiserende zaak kan dit doen.",
      already_participant: "Deze zaak doet al mee aan de actie.",
      invite_not_found: "Deze uitnodiging bestaat niet meer of is al beantwoord.",
      invite_expired: "Deze uitnodiging is verlopen. Vraag de organisator om een nieuwe.",
    };
    return map[m] || map[h] || "";
  }
  window.PasrCommunityError = communityError;

  // Uitnodiging voor een gezamenlijke actie (pasr.nl/zakelijk/uitnodiging/?t=<token>): het token blijft 14 dagen in deze
  // browser bewaard, zodat het na aanmelden, bevestigen en goedkeuren nog in het dashboard klaarstaat.
  var COMMUNITY_KEY = "pasr.zakelijk.community";
  function communityToken(v) {
    try {
      if (v === null) { localStorage.removeItem(COMMUNITY_KEY); return null; }
      if (v) { localStorage.setItem(COMMUNITY_KEY, JSON.stringify({ t: v, at: Date.now() })); return v; }
      var o = JSON.parse(localStorage.getItem(COMMUNITY_KEY) || "null");
      if (!o || !/^[0-9a-f]{64}$/.test(o.t) || Date.now() - o.at > 14 * 864e5) { localStorage.removeItem(COMMUNITY_KEY); return null; }
      return o.t;
    } catch (e) { return null; }
  }
  function communityPeriod(p) { return nlDate(p.starts_at) + " t/m " + nlDate(p.ends_at); }
  function communityCard(p) {
    var names = Array.isArray(p.participant_names) ? p.participant_names : [];
    return '<div class="zk-ci-card"><span class="zk-ci-kicker">' + ICON.users + "Gezamenlijke actie</span>" +
      "<h2>" + esc(p.title) + "</h2>" +
      '<dl class="zk-ci-list"><div><dt>Beloning</dt><dd>' + esc(p.reward) + "</dd></div>" +
      "<div><dt>Looptijd</dt><dd>" + esc(communityPeriod(p)) + "</dd></div>" +
      "<div><dt>Organisator</dt><dd>" + esc(p.initiator_name) + "</dd></div>" +
      (names.length ? "<div><dt>Doen mee</dt><dd>" + esc(names.join(", ")) + "</dd></div>" : "") + "</dl></div>";
  }
  // In het dashboard: een bewaarde uitnodiging bovenaan, met accepteren namens de gekozen zaak.
  async function communityBanner(b) {
    var t = communityToken();
    if (!t || b.role !== "owner" || b.status !== "approved") return;
    var p;
    try { p = await rpc("pasr_business_community_invite_preview", { p_token: t }); } catch (e) { return; }
    if (!p || p.status !== "invited") { communityToken(null); return; }
    var panel = $("#zd-panel");
    if (!panel || $("#zkCiBanner")) return;
    var box = document.createElement("div");
    box.id = "zkCiBanner"; box.className = "zd-state zk-ci-banner"; box.setAttribute("role", "status");
    box.innerHTML = '<span class="zd-state-ic">' + ICON.users + "</span><div><h2>Uitnodiging voor \u201c" + esc(p.title) + "\u201d</h2>" +
      "<p>" + esc(p.initiator_name) + " nodigt je uit voor een gezamenlijke actie: " + esc(p.reward) + ". Looptijd " + esc(communityPeriod(p)) + ".</p>" +
      '<p class="zk-ci-actions"><button class="zk-btn sm" type="button" id="zkCiYes">Accepteren met ' + esc(b.name) + "</button>" +
      '<button class="zk-btn ghost sm" type="button" id="zkCiNo">Niet nu</button></p><p class="zk-msg" id="zkCiMsg" role="status"></p></div>';
    panel.parentNode.insertBefore(box, panel);
    $("#zkCiNo").addEventListener("click", function () { communityToken(null); box.remove(); });
    $("#zkCiYes").addEventListener("click", async function (ev) {
      var btn = ev.currentTarget; btn.disabled = true;
      try {
        await rpc("pasr_business_community_accept_token", { p_business: b.id, p_token: t }, true);
        communityToken(null); box.remove(); toast("Je doet mee aan " + p.title); go("gezamenlijke-acties");
      } catch (e) {
        setMsg($("#zkCiMsg"), nice(e)); btn.disabled = false;
        if (/invite_(expired|not_found)|already_participant/.test(String(e.message || ""))) communityToken(null);
      }
    });
  }

  // ---------------------------------------------------------------- dashboard: pasr.nl/zakelijk/dashboard/
  // Alles wat de app Pasr Zakelijk kan, met dezelfde databasefuncties. Ingelogd is het een app-scherm: werkbalk (zaakkiezer,
  // zoeken, Scannen, meldingen, account), een zijbalk in groepen en op een telefoon een onderbalk zoals de app.
  // Onderdelen staan in TABS; een nieuw onderdeel = een regel in TABS plus een functie in VIEWS.
  // Eigenaar: alles. Medewerker: alleen Scannen. Geblokkeerde zaak: alleen Account. Meerdere zaken: zaakkiezer.
  var dash = { me: null, bizId: null, tab: null, sub: null, edit: null, chart: { days: 30, metric: "stamps", prev: false }, today: { days: 30 }, filter: "alles", extra: null };
  var BIZ_KEY = "pasr.zakelijk.biz";
  // group: "" = bovenaan, "foot" = onderaan de zijbalk, "mobile" = alleen via de onderbalk, "none" = alleen via de werkbalk
  var TABS = [
    { id: "vandaag", label: "Vandaag", icon: "home", owner: true, group: "" },
    { id: "stempelkaarten", label: "Stempelkaarten", icon: "card", owner: true, group: "Klantenbinding" },
    { id: "klantenkaarten", label: "Klantenkaarten", icon: "mcard", owner: true, group: "Klantenbinding", isNew: true },
    { id: "tickets", label: "Tickets", icon: "ticket", owner: true, group: "Klantenbinding", isNew: true },
    { id: "kortingsbonnen", label: "Kortingsbonnen", icon: "tag", owner: true, group: "Klantenbinding" },
    { id: "actiecodes", label: "Actiecodes", icon: "code", owner: true, group: "Klantenbinding" },
    { id: "gezamenlijke-acties", label: "Gezamenlijke acties", icon: "users", owner: true, group: "Klantenbinding", badge: "invites" },
    { id: "beloningen", label: "Beloningen", icon: "gift", owner: true, group: "Klantenbinding" },
    { id: "inzichten", label: "Inzichten", icon: "bars", owner: true, group: "Groei" },
    { id: "marketing", label: "Marketingkalender", icon: "calendar", owner: true, group: "Groei" },
    { id: "promotiemateriaal", label: "Promotiemateriaal", icon: "download", owner: true, group: "Groei" },
    { id: "vestigingen", label: "Vestigingen", icon: "pin", owner: true, group: "Je zaak" },
    { id: "medewerkers", label: "Medewerkers", icon: "user", owner: true, group: "Je zaak" },
    { id: "instellingen", label: "Instellingen", icon: "gear", owner: true, group: "Je zaak" },
    { id: "prullenbak", label: "Prullenbak", icon: "trash", owner: true, group: "foot" },
    { id: "mijn-account", label: "Account", icon: "user", owner: true, group: "foot" },
    { id: "scannen", label: "Scannen", icon: "scan", group: "none" },
    { id: "alle-acties", label: "Acties", icon: "card", owner: true, group: "mobile" },
    { id: "meer", label: "Meer", icon: "more", owner: true, group: "mobile" },
  ];
  var GROUPS = ["Klantenbinding", "Groei", "Je zaak"];
  // Oude adressen (mails, apps, bladwijzers) blijven werken: #overzicht opent Vandaag, enzovoort.
  var ALIAS = { overzicht: "vandaag", kaarten: "stempelkaarten", samenwerkingen: "gezamenlijke-acties", verwijderd: "prullenbak",
    acties: "beloningen", promotie: "promotiemateriaal", account: "mijn-account", bedrijfsinzichten: "inzichten" };
  // onderdelen die op een telefoon onder Acties vallen (de rest onder Meer)
  var UNDER_ACTS = ["alle-acties", "stempelkaarten", "klantenkaarten", "tickets", "kortingsbonnen", "actiecodes", "gezamenlijke-acties"];
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
  // Anti-bot (zoals pasr.nl/account): twee honeypots die een mens niet ziet, tekstveld "hp_extra" en vinkje
  // "nieuwsbrief_extra" ("Stuur mij aanbiedingen"). Is een van beide ingevuld, dan doen we alsof het gelukt is (inloggen:
  // dezelfde melding als een fout wachtwoord) en sturen we niets naar de server. Geen tijdmeting: snel is geen bot.
  var HP_HTML = '<div class="hp-field" aria-hidden="true"><label>Laat dit veld leeg<input type="text" name="hp_extra" tabindex="-1" autocomplete="off" data-1p-ignore data-lpignore="true" data-bwignore></label><label><input type="checkbox" name="nieuwsbrief_extra" value="1" tabindex="-1" autocomplete="off"> Stuur mij aanbiedingen</label></div>';
  function isBot(scope) {
    var t = scope.querySelector('input[name="hp_extra"]'), c = scope.querySelector('input[name="nieuwsbrief_extra"]');
    return !!(t && t.value.trim()) || !!(c && c.checked);
  }
  function loginView(mode) {
    var signup = mode === "signup", forgot = mode === "forgot";
    dashRoot().innerHTML =
      '<section class="auth zd-auth"><div class="badge">' + ICON.stamp + "</div>" +
      "<h1>" + (signup ? "Gratis aanmelden" : forgot ? "Wachtwoord vergeten" : "Inloggen voor ondernemers") + "</h1>" +
      "<p>" + (signup ? "Maak een gratis Pasr-account met het e-mailadres van je zaak. Daarna meld je je zaak aan en maak je je stempelkaart, klantenkaart, event of actie." : forgot ? "Vul je e-mailadres in. Je krijgt een mail om een nieuw wachtwoord te kiezen." : "Log in met je Pasr-account, hetzelfde als in de app Pasr Zakelijk.") + "</p>" +
      '<form id="zkAuth" class="zk-form" novalidate>' +
      (signup ? '<label for="zkName">Je voornaam</label><input id="zkName" autocomplete="given-name" maxlength="40" required>' : "") +
      '<label for="zkEmail">E-mailadres</label><input id="zkEmail" type="email" autocomplete="email" required>' +
      (forgot ? "" : '<label for="zkPw">Wachtwoord</label><input id="zkPw" type="password" autocomplete="' + (signup ? "new-password" : "current-password") + '" minlength="8" required' + (signup ? ' aria-describedby="zkPwHelp"' : "") + ">" +
        (signup ? '<small id="zkPwHelp" class="zd-help">Minstens 8 tekens.</small>' : "")) +
      HP_HTML +
      '<button class="zk-btn" type="submit">' + (signup ? "Account maken" : forgot ? "Stuur mail" : "Inloggen") + '</button><p class="zk-msg" id="zkMsg" role="status" aria-live="polite"></p></form>' +
      '<p class="switch">' +
      (signup ? 'Al een account? <a href="#inloggen">Inloggen</a>' : forgot ? '<a href="#inloggen">Terug naar inloggen</a>' : 'Nog geen account? <a href="#account">Gratis aanmelden</a> · <a href="#vergeten">Wachtwoord vergeten?</a>') + "</p></section>";
    $("#zkAuth").addEventListener("submit", async function (ev) {
      ev.preventDefault();
      var msg = $("#zkMsg"), btn = ev.target.querySelector("button");
      var email = $("#zkEmail").value.trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { $("#zkEmail").focus(); return setMsg(msg, "Dit e-mailadres klopt niet."); }
      var checkEmail = function () {
        dashRoot().innerHTML = '<section class="auth ok zd-auth"><div class="badge">' + ICON.mail + "</div><h1>Check je mail</h1><p>We hebben een mail gestuurd naar " + esc(email) +
          '. Tik op de knop in die mail om je e-mailadres te bevestigen. Kom daarna terug en log hier in om je zaak aan te melden.</p><p><a class="zk-btn" href="#inloggen">Naar inloggen</a></p></section>';
      };
      if (isBot(ev.target)) {   // bot (honeypot ingevuld): doe alsof, stuur niets
        if (forgot) return setMsg(msg, "Als er een account met dit adres is, staat er nu een mail in je inbox.", true);
        if (signup) { if (!$("#zkName").value.trim() || $("#zkPw").value.length < 8) return setMsg(msg, "Vul alle velden in."); return checkEmail(); }
        return setMsg(msg, "E-mailadres of wachtwoord klopt niet.");
      }
      btn.disabled = true;
      try {
        if (forgot) {
          await http("auth/v1/recover?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: email });
          setMsg(msg, "Als er een account met dit adres is, staat er nu een mail in je inbox.", true);
        } else if (signup) {
          var name = $("#zkName").value.replace(/[<>]/g, "").replace(/\s+/g, " ").trim().slice(0, 40), pw = $("#zkPw").value;
          if (!name) { btn.disabled = false; $("#zkName").focus(); return setMsg(msg, "Vul je voornaam in."); }
          if (pw.length < 8) { btn.disabled = false; $("#zkPw").focus(); return setMsg(msg, "Kies een wachtwoord van minstens 8 tekens."); }
          var data = { first_name: name, app: "zakelijk" };
          await http("auth/v1/signup?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: email, password: pw, data: data });
          checkEmail();
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
        dash.bizId = nb.id; store(BIZ_KEY, nb.id); dash.sub = null; dash.tab = "stempelkaarten";
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
  // ---- app-scherm: werkbalk, zijbalk, onderbalk ----
  function shellOn(on) { document.body.classList.toggle("zd3-on", !!on); }
  function initial() {
    var n = String((session && (session.first_name || session.email)) || "?").trim();
    return (n.charAt(0) || "?").toUpperCase();
  }
  function isApp(b) { return b.role === "owner" && b.status !== "blocked"; }
  function roleText(b) { return b.role === "owner" ? "Eigenaar" : "Medewerker"; }
  function bizFace(b, small) {
    return '<span class="zd3-bizlogo' + (small ? " sm" : "") + '" style="background:' + colorOf(b) + '" aria-hidden="true">' + logoOf(b) + "</span>" +
      '<span class="zd3-bizname"><b>' + esc(b.name) + "</b><small>" + esc([b.city, roleText(b)].filter(Boolean).join(" · ")) + "</small></span>";
  }
  // Zaakkiezer: wisselen tussen je zaken (eigenaar of medewerker) en, zonder eigen zaak, er een aanmelden.
  function bizPicker(b) {
    var list = bizList(), own = ownBiz();
    if (list.length < 2 && own) return '<div class="zd3-biz"><div class="zd3-bizbtn is-static">' + bizFace(b) + "</div></div>";
    var items = list.map(function (x) {
      return '<li><button type="button" data-biz="' + esc(x.id) + '" aria-current="' + (x.id === b.id) + '">' + bizFace(x, true) + (x.id === b.id ? ICON.check : "") + "</button></li>";
    }).join("") + (own ? "" : '<li><button type="button" data-biz="__new"><span class="zd3-bizlogo sm add" aria-hidden="true">' + ICON.plus + '</span><span class="zd3-bizname"><b>Nieuwe zaak aanmelden</b><small>Gratis, we keuren elke zaak met de hand</small></span></button></li>');
    return '<div class="zd3-biz zd3-pop"><button type="button" class="zd3-bizbtn zd3-toggle" id="zdBizBtn" aria-expanded="false" aria-controls="zdBizMenu">' +
      '<span class="sr-only">Zaak kiezen. Nu: </span>' + bizFace(b) + ICON.down + '</button><ul class="zd3-menu zd3-bizmenu" id="zdBizMenu" hidden>' + items + "</ul></div>";
  }
  function topbar(b, tabs) {
    var app = isApp(b), has = function (id) { return tabs.some(function (t) { return t.id === id; }); };
    var mac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || "");
    return '<header class="zd3-top">' +
      '<a class="zd3-brand" href="/zakelijk/"><img src="/assets/icon.png" alt="" width="30" height="30"><span>pasr</span><em class="zk-tag">Zakelijk</em><span class="sr-only"> (naar de website)</span></a>' +
      bizPicker(b) +
      (app ? '<div class="zd3-search" role="search"><label class="sr-only" for="zdSearch">Zoek in je dashboard</label>' + ICON.search +
        '<input id="zdSearch" type="search" autocomplete="off" spellcheck="false" placeholder="Zoek een actie, code, kaart of onderdeel…" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="zdSearchList">' +
        '<kbd aria-hidden="true">' + (mac ? "⌘K" : "Ctrl K") + '</kbd><ul class="zd3-menu zd3-results" id="zdSearchList" role="listbox" aria-label="Zoekresultaten" hidden></ul></div>' : '<span class="zd3-fill"></span>') +
      (has("scannen") ? '<a class="zd3-scan" href="#scannen" data-go="scannen">' + ICON.scan + "<span>Scannen</span></a>" : "") +
      (app ? '<div class="zd3-pop zd3-bell"><button type="button" class="zd3-icon zd3-toggle" id="zdBell" aria-expanded="false" aria-controls="zdBellMenu"><span class="sr-only" id="zdBellLabel">Meldingen</span>' + ICON.bell + '<span class="zd3-dot" hidden></span></button>' +
        '<div class="zd3-menu zd3-bellmenu" id="zdBellMenu" hidden><h2>Meldingen</h2><div id="zdBellList"><p class="zd3-muted">Laden…</p></div></div></div>' : "") +
      '<div class="zd3-pop zd3-me"><button type="button" class="zd3-avatar zd3-toggle" id="zdMe" aria-expanded="false" aria-controls="zdMeMenu"><span class="sr-only">Account en uitloggen</span><span aria-hidden="true">' + esc(initial()) + "</span></button>" +
      '<ul class="zd3-menu zd3-memenu" id="zdMeMenu" hidden><li class="zd3-menuhead"><small>Ingelogd als</small><b>' + esc((session && session.email) || "") + "</b></li>" +
      (has("mijn-account") ? '<li><a href="#mijn-account" data-go="mijn-account">' + ICON.user + "Account</a></li>" : "") +
      '<li><button type="button" id="zkOut">' + ICON.logout + "Uitloggen</button></li></ul></div></header>";
  }
  function navLink(t, cls) {
    var on = t.id === dash.tab;
    return '<li><a href="#' + t.id + '" data-go="' + t.id + '"' + (cls ? ' class="' + cls + '"' : "") + (on ? ' aria-current="page"' : "") + ">" + ICON[t.icon] +
      "<span>" + esc(t.label) + "</span>" + (t.isNew ? '<span class="zd3-new">Nieuw</span>' : "") + (t.badge ? '<span class="zd3-badge" data-badge="' + t.badge + '" hidden></span>' : "") + ICON.chevron + "</a></li>";
  }
  function sideNav(tabs) {
    var by = {};
    tabs.forEach(function (t) { (by[t.group] = by[t.group] || []).push(t); });
    var html = '<nav class="zd3-side" aria-label="Onderdelen van je dashboard"><div class="zd3-sidein">';
    if (by[""]) html += "<ul>" + by[""].map(function (t) { return navLink(t); }).join("") + "</ul>";
    GROUPS.forEach(function (g, i) {
      if (by[g]) html += '<h2 class="zd3-group" id="zdg' + i + '">' + esc(g) + '</h2><ul aria-labelledby="zdg' + i + '">' + by[g].map(function (t) { return navLink(t); }).join("") + "</ul>";
    });
    if (by.foot) html += '<ul class="zd3-foot">' + by.foot.map(function (t) { return navLink(t); }).join("") + "</ul>";
    return html + "</div></nav>";
  }
  function tabBar() {
    var acts = UNDER_ACTS.indexOf(dash.tab) >= 0, more = ["vandaag", "scannen", "inzichten"].indexOf(dash.tab) < 0 && !acts;
    function item(id, icon, label, on, cls) {
      return '<li><a href="#' + id + '" data-go="' + id + '"' + (cls ? ' class="' + cls + '"' : "") + (on ? ' aria-current="page"' : "") + "><span class=\"zd3-tbic\">" + ICON[icon] + "</span><span>" + label + "</span>" +
        (id === "meer" ? '<span class="zd3-badge sm" data-badge="invites" hidden></span>' : "") + "</a></li>";
    }
    return '<nav class="zd3-tabbar" aria-label="Snelmenu"><ul>' +
      item("vandaag", "home", "Vandaag", dash.tab === "vandaag") + item("alle-acties", "card", "Acties", acts) +
      item("scannen", "scan", "Scannen", dash.tab === "scannen", "zd3-tbscan") + item("inzichten", "bars", "Inzichten", dash.tab === "inzichten") +
      item("meer", "more", "Meer", more) + "</ul></nav>";
  }
  function closeMenus(except, refocus) {
    document.querySelectorAll(".zd3-toggle[aria-expanded=true]").forEach(function (btn) {
      if (btn === except) return;
      btn.setAttribute("aria-expanded", "false");
      var m = document.getElementById(btn.getAttribute("aria-controls")); if (m) m.hidden = true;
      if (refocus) btn.focus();
    });
  }
  function go(tab) {
    dash.sub = null; dash.edit = null;
    if (location.hash !== "#" + tab) history.pushState(null, "", "#" + tab);
    dash.tab = tab; render(); focusPanel();
  }
  function focusPanel() {
    var p = $("#zd-panel"); if (!p) return;
    p.focus({ preventScroll: true });
    window.scrollTo(0, 0);
  }
  function openCard(card) {
    dash.tab = "stempelkaarten"; history.pushState(null, "", "#stempelkaarten");
    dash.edit = card || null; dash.sub = "edit"; render(); focusPanel();
  }
  function openNewCard(b) {
    if ((b.cards || []).length >= 5) { toast("Je kunt hoogstens 5 stempelkaarten maken."); return go("stempelkaarten"); }
    openCard(null);
  }

  // Extra gegevens voor werkbalk, Vandaag en Acties: bonnen, codes, gezamenlijke acties en uitnodigingen (max. een minuut bewaard).
  function loadExtra(b, fresh) {
    var x = dash.extra;
    if (!fresh && x && x.biz === b.id && Date.now() - x.at < 60000) return x.p;
    var p = Promise.allSettled([
      rpc("pasr_business_coupon_list", { p_business: b.id }, true),
      rpc("pasr_business_promo_list", { p_business: b.id }, true),
      rpc("pasr_business_community_list", { p_business: b.id }, true),
      rpc("pasr_business_community_my_invites", { p_business: b.id }, true),
      rpc("pasr_business_events", { p_business: b.id }, true),
      rpc("pasr_business_member_cards", { p_business: b.id }, true),
    ]).then(function (r) {
      function v(i) { return r[i].status === "fulfilled" && Array.isArray(r[i].value) ? r[i].value : null; }
      var alive = function (row) { return !row.deleted; };
      return { coupons: v(0) && v(0).filter(alive), codes: v(1) && v(1).filter(alive), community: v(2), invites: v(3) || [],
        events: v(4) || [], memberCards: v(5) || [] };
    });
    dash.extra = { biz: b.id, at: Date.now(), p: p };
    return p;
  }
  var DAY = 864e5;
  function money(type, v) { return type === "percent" ? Number(v || 0).toLocaleString("nl-NL") + "%" : new Intl.NumberFormat("nl-NL", { style: "currency", currency: "EUR" }).format(Number(v || 0)); }
  function daysLeft(iso) { return Math.max(0, Math.ceil((Date.parse(iso) - Date.now()) / DAY)); }
  function inDays(n) { return n <= 0 ? "vandaag" : n === 1 ? "morgen" : "over " + n + " dagen"; }
  function couponState(c) {
    var now = Date.now();
    if (Date.parse(c.ends_at) <= now) return ["Verlopen", ""];
    if (!c.public) return ["Gepauzeerd", "wait"];
    if (Date.parse(c.starts_at) > now) return ["Gepland", "wait"];
    return ["Online", "on"];
  }
  function codeState(c) {
    var now = Date.now();
    if (Date.parse(c.ends_at) <= now) return ["Verlopen", ""];
    if (!c.active) return ["Gepauzeerd", "wait"];
    if (Number(c.used_count || 0) >= Number(c.max_uses || 0)) return ["Op", ""];
    if (Date.parse(c.starts_at) > now) return ["Gepland", "wait"];
    return ["Actief", "on"];
  }
  function communityState(c) {
    if (c.state === "waiting") {
      var n = Math.max(0, Number(c.min_participants || 0) - Number(c.accepted_count || 0));
      return [n ? "Wacht op " + plural(n, "zaak", "zaken") : "Wacht op deelnemers", "wait"];
    }
    return { active: ["Actief", "on"], ended: ["Afgelopen", ""], cancelled: ["Gestopt", ""] }[c.state] || [c.state || "—", ""];
  }
  var KIND_COLOR = { coupon: "#C2361F", code: "#4A3CE0", community: "#087554", event: "#1F3A5F", mcard: "#8A4B1F" };
  /** Alle acties van de zaak als rijen: stempelkaarten, kortingsbonnen, actiecodes en gezamenlijke acties. */
  function actionRows(b, x) {
    var rows = (b.cards || []).map(function (c) {
      return { kind: "card", title: c.name, sub: "Stempelkaart · " + plural(Number(c.stamps_total) || 0, "stempel", "stempels"),
        state: c.published ? ["Online", "on"] : ["Concept", ""], count: c.published ? plural(c.members || 0, "lid", "leden") : "—",
        color: /^#[0-9a-f]{6}$/i.test(c.color || "") ? c.color : "#6A5CFF", icon: "card", live: !!c.published, run: function () { openCard(c); } };
    });
    (x.coupons || []).forEach(function (c) {
      var s = couponState(c);
      rows.push({ kind: "coupon", title: c.title, sub: "Kortingsbon · " + money(c.discount_type, c.discount_value) + " · t/m " + nlDate(c.ends_at), state: s,
        count: Number(c.claimed || 0) + " bewaard", color: KIND_COLOR.coupon, icon: "tag", live: s[1] === "on", run: function () { go("kortingsbonnen"); } });
    });
    (x.codes || []).forEach(function (c) {
      var s = codeState(c);
      rows.push({ kind: "code", title: c.title, sub: "Actiecode " + c.code + " · t/m " + nlDate(c.ends_at), state: s,
        count: Number(c.used_count || 0) + "/" + Number(c.max_uses || 0) + " gebruikt", color: KIND_COLOR.code, icon: "code", live: s[1] === "on", run: function () { go("actiecodes"); } });
    });
    (x.memberCards || []).filter(function (c) { return c.status !== "archived"; }).forEach(function (c) {
      rows.push({ kind: "mcard", title: c.name, sub: "Klantenkaart · " + plural(Number(c.members || 0), "lid", "leden") + (c.discount_now && window.PasrTK ? " · " + window.PasrTK.pct(c.discount_now.percent) : ""),
        state: c.status === "published" ? ["Online", "on"] : ["Concept", ""], count: plural(Number(c.members || 0), "lid", "leden"),
        color: /^#[0-9a-f]{6}$/i.test(c.color || "") ? c.color : KIND_COLOR.mcard, icon: "mcard", live: c.status === "published",
        run: function () { go("klantenkaarten"); dash.sub = "mc-edit"; dash.mcCard = c; render(); } });
    });
    (x.events || []).filter(function (e) { return e.status !== "cancelled" && Date.parse(e.ends_at) > Date.now(); }).forEach(function (e) {
      var s = window.PasrTK ? window.PasrTK.eventState(e) : [e.status, ""];
      rows.push({ kind: "event", title: e.name, sub: "Event · " + (window.PasrTK ? window.PasrTK.dShort(e.starts_at) + " " + window.PasrTK.hm(e.starts_at) : nlDate(e.starts_at)) + " · " + Number(e.registered || 0) + "/" + e.capacity + " aangemeld",
        state: s, count: Number(e.registered || 0) + "/" + e.capacity, color: /^#[0-9a-f]{6}$/i.test(e.color || "") ? e.color : KIND_COLOR.event, icon: "ticket",
        live: e.status === "published", run: function () { go("tickets"); dash.sub = "tk-event"; dash.tkEvent = e; render(); } });
    });
    (x.community || []).forEach(function (c) {
      var s = communityState(c);
      rows.push({ kind: "community", title: c.name, sub: "Gezamenlijke actie · " + plural(Number(c.accepted_count || 0), "zaak", "zaken"), state: s,
        count: c.claims_here ? c.claims_here + "× uitgegeven" : "—", color: KIND_COLOR.community, icon: "users",
        live: c.state === "waiting" || c.state === "active", run: function () { go("gezamenlijke-acties"); } });
    });
    return rows;
  }
  function rowList(rows, cls) {
    return '<ul class="zd3-rows' + (cls ? " " + cls : "") + '">' + rows.map(function (r, i) {
      return '<li><button type="button" class="zd3-row" data-row="' + i + '"><span class="zd3-sw" style="background:' + esc(r.color) + '" aria-hidden="true">' + ICON[r.icon] + "</span>" +
        '<span class="zd3-rt"><b>' + esc(r.title) + "</b><small>" + esc(r.sub) + "</small></span>" +
        '<span class="zk-pill ' + r.state[1] + '">' + esc(r.state[0]) + '</span><span class="zd3-rn">' + esc(r.count) + "</span>" + ICON.chevron + "</button></li>";
    }).join("") + "</ul>";
  }
  function bindRows(box, rows) {
    box.querySelectorAll("[data-row]").forEach(function (btn) { btn.addEventListener("click", function () { rows[Number(btn.dataset.row)].run(); }); });
  }
  /** Te doen: echte openstaande punten (uitnodigingen, concepten, bijna verlopen bonnen en codes, wachtende acties, goedkeuring). */
  function todoItems(b, x) {
    var out = [], week = Date.now() + 7 * DAY;
    if (b.status === "pending") out.push({ icon: "clock", tone: "warn", html: "Je zaak <b>wacht op goedkeuring</b>", sub: "We bekijken je aanmelding, meestal binnen een werkdag. Je krijgt een mail.", tab: "instellingen" });
    (x.invites || []).forEach(function (v) {
      var n = Array.isArray(v.participant_names) ? v.participant_names.length : 0;
      out.push({ icon: "users", tone: "coral", html: "Uitnodiging: <b>" + esc(v.title) + "</b>", sub: [v.initiator_name ? v.initiator_name + " nodigt je uit" : "", n ? plural(n, "zaak doet", "zaken doen") + " mee" : ""].filter(Boolean).join(" · "),
        label: "Bekijken", tab: "gezamenlijke-acties" });
    });
    if (b.status === "approved") (b.cards || []).filter(function (c) { return !c.published; }).forEach(function (c) {
      out.push({ icon: "card", tone: "iris", html: "<b>" + esc(c.name) + "</b> staat nog in concept", sub: "Zet hem online zodat klanten hem kunnen toevoegen", label: "Online zetten", tab: "stempelkaarten",
        run: async function (btn) {
          btn.disabled = true;
          try { await rpc("pasr_business_card_save", { p_card: { id: c.id, name: c.name, reward: c.reward, stamps_total: c.stamps_total, color: c.color, published: true } }, true); await refresh(); toast("Je kaart staat online"); }
          catch (e) { btn.disabled = false; toast(nice(e)); }
        } });
    });
    (x.coupons || []).filter(function (c) { var e = Date.parse(c.ends_at); return c.public && e > Date.now() && e <= week; }).forEach(function (c) {
      out.push({ icon: "tag", tone: "mint", html: "Kortingsbon <b>" + esc(c.title) + "</b> loopt " + inDays(daysLeft(c.ends_at)) + " af", sub: Number(c.claimed || 0) + " bewaard · " + Number(c.redeemed || 0) + " gebruikt", label: "Verlengen", tab: "kortingsbonnen" });
    });
    (x.codes || []).filter(function (c) { var e = Date.parse(c.ends_at); return c.active && e > Date.now() && e <= week; }).forEach(function (c) {
      out.push({ icon: "code", tone: "mint", html: "Actiecode <b>" + esc(c.code) + "</b> loopt " + inDays(daysLeft(c.ends_at)) + " af", sub: plural(Number(c.used_count || 0), "keer", "keer") + " gebruikt", label: "Verlengen", tab: "actiecodes" });
    });
    if (window.PasrTK) window.PasrTK.todo(b, x, { esc: esc }).forEach(function (t) {
      if (t.tkEvent) t.run = function () { go("tickets"); dash.sub = t.edit ? "tk-edit" : "tk-event"; dash.tkEvent = t.tkEvent; render(); focusPanel(); };
      if (t.mcCard) t.run = function () { go("klantenkaarten"); dash.sub = "mc-edit"; dash.mcCard = t.mcCard; render(); focusPanel(); };
      out.push(t);
    });
    (x.community || []).filter(function (c) { return c.state === "waiting"; }).forEach(function (c) {
      var org = c.role === "owner" || c.is_lead;
      out.push({ icon: "users", tone: "iris", html: "<b>" + esc(c.name) + "</b>: " + esc(communityState(c)[0].toLowerCase()), sub: org ? "Nodig meer zaken uit om de actie te starten" : "De actie start zodra genoeg zaken meedoen",
        label: org ? "Uitnodigen" : "Bekijken", tab: "gezamenlijke-acties" });
    });
    return out;
  }
  function todoHtml(items, compact) {
    return '<ul class="zd3-todo' + (compact ? " compact" : "") + '">' + items.map(function (t, i) {
      var body = '<span class="zd3-tic ' + t.tone + '" aria-hidden="true">' + ICON[t.icon] + '</span><span class="zd3-rt"><span class="zd3-tt">' + t.html + "</span>" + (t.sub ? "<small>" + esc(t.sub) + "</small>" : "") + "</span>";
      if (compact) return '<li><a href="#' + t.tab + '" data-go="' + t.tab + '">' + body + ICON.chevron + "</a></li>";
      return "<li>" + body + (t.label ? '<button type="button" class="zk-btn ghost sm" data-todo="' + i + '">' + esc(t.label) + "</button>" : "") + "</li>";
    }).join("") + "</ul>";
  }
  function updateShell(b, x) {
    if (current() !== b) return;
    var n = (x.invites || []).length;
    document.querySelectorAll("[data-badge=invites]").forEach(function (el) { el.hidden = !n; el.innerHTML = n + '<span class="sr-only"> ' + (n === 1 ? "open uitnodiging" : "open uitnodigingen") + "</span>"; });
    var items = todoItems(b, x), list = $("#zdBellList"), dot = $(".zd3-bell .zd3-dot"), label = $("#zdBellLabel");
    if (dot) dot.hidden = !items.length;
    if (label) label.textContent = items.length ? "Meldingen, " + plural(items.length, "punt", "punten") + " te doen" : "Meldingen, niets te doen";
    if (list) list.innerHTML = items.length ? todoHtml(items, true) : '<p class="zd3-muted">Niets te doen. Alles is bij.</p>';
  }

  // ---- zoeken in de werkbalk: onderdelen, stempelkaarten, kortingsbonnen, actiecodes en gezamenlijke acties ----
  function norm(s) { return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
  function bindSearch(b) {
    var input = $("#zdSearch"), list = $("#zdSearchList"); if (!input) return;
    var index = null, hits = [], active = -1;
    function build(x) {
      var out = tabsFor(b).filter(function (t) { return t.group !== "mobile"; }).map(function (t) { return { label: t.label, kind: "Onderdeel", run: function () { go(t.id); } }; });
      out.push({ label: "Logboek", kind: "Onderdeel", run: function () { go("vandaag"); dash.sub = "log"; render(); } });
      out.push({ label: "Nieuwe stempelkaart", kind: "Aanmaken", run: function () { openNewCard(b); } });
      out.push({ label: "Nieuw event", extra: "tickets aanmelden", kind: "Aanmaken", run: function () { go("tickets"); dash.sub = "tk-edit"; dash.tkEvent = null; render(); } });
      out.push({ label: "Nieuwe klantenkaart", extra: "barcode", kind: "Aanmaken", run: function () { go("klantenkaarten"); dash.sub = "mc-edit"; dash.mcCard = null; render(); } });
      (x.events || []).forEach(function (e) { out.push({ label: e.name, extra: e.address, kind: "Event", run: function () { go("tickets"); dash.sub = "tk-event"; dash.tkEvent = e; render(); } }); });
      (x.memberCards || []).forEach(function (c) { out.push({ label: c.name, kind: "Klantenkaart", run: function () { go("klantenkaarten"); dash.sub = "mc-edit"; dash.mcCard = c; render(); } }); });
      (b.cards || []).forEach(function (c) { out.push({ label: c.name, extra: c.reward, kind: "Stempelkaart", run: function () { openCard(c); } }); });
      (x.coupons || []).forEach(function (c) { out.push({ label: c.title, kind: "Kortingsbon", run: function () { go("kortingsbonnen"); } }); });
      (x.codes || []).forEach(function (c) { out.push({ label: c.code + " · " + c.title, kind: "Actiecode", run: function () { go("actiecodes"); } }); });
      (x.community || []).forEach(function (c) { out.push({ label: c.name, extra: c.reward, kind: "Gezamenlijke actie", run: function () { go("gezamenlijke-acties"); } }); });
      return out;
    }
    function close() { list.hidden = true; input.setAttribute("aria-expanded", "false"); input.removeAttribute("aria-activedescendant"); active = -1; }
    function mark(i) {
      active = i;
      list.querySelectorAll("[role=option]").forEach(function (li, j) { li.setAttribute("aria-selected", String(j === i)); });
      if (i >= 0) { input.setAttribute("aria-activedescendant", "zds-" + i); var el = $("#zds-" + i); if (el) el.scrollIntoView({ block: "nearest" }); }
    }
    function choose(i) { var h = hits[i]; if (!h) return; input.value = ""; close(); h.run(); }
    function show() {
      var q = norm(input.value.trim());
      if (!q) return close();
      hits = (index || []).filter(function (h) { return norm(h.label + " " + (h.extra || "") + " " + h.kind).indexOf(q) >= 0; }).slice(0, 8);
      list.innerHTML = hits.length ? hits.map(function (h, i) { return '<li role="option" id="zds-' + i + '" aria-selected="false" data-i="' + i + '"><b>' + esc(h.label) + "</b><small>" + esc(h.kind) + "</small></li>"; }).join("")
        : '<li class="zd3-none" role="option" aria-disabled="true" aria-selected="false">Niets gevonden voor “' + esc(input.value.trim()) + "”</li>";
      list.hidden = false; input.setAttribute("aria-expanded", "true"); mark(hits.length ? 0 : -1);
    }
    input.addEventListener("focus", function () { loadExtra(b).then(function (x) { index = build(x); if (document.activeElement === input && input.value) show(); }); });
    input.addEventListener("input", function () { if (!index) index = build({}); show(); });
    input.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); if (list.hidden) show(); if (hits.length) mark((active + (e.key === "ArrowDown" ? 1 : -1) + hits.length) % hits.length); }
      else if (e.key === "Enter") { if (active >= 0) { e.preventDefault(); choose(active); } }
      else if (e.key === "Escape") { if (!list.hidden) { e.stopPropagation(); close(); } else { input.value = ""; input.blur(); } }
    });
    input.addEventListener("blur", function () { setTimeout(close, 150); });
    list.addEventListener("mousedown", function (e) { var li = e.target.closest("[data-i]"); if (li) { e.preventDefault(); choose(Number(li.dataset.i)); } });
  }

  function bindShell(b) {
    bindUser(); bindSearch(b);
    dashRoot().querySelectorAll("[data-biz]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        closeMenus();
        if (btn.dataset.biz === "__new") { dash.sub = "register"; return render(); }
        if (btn.dataset.biz === b.id) return;
        dash.bizId = btn.dataset.biz; store(BIZ_KEY, btn.dataset.biz); dash.tab = null; dash.sub = null; dash.extra = null;
        history.replaceState(null, "", location.pathname); render(); toast("Gewisseld naar " + current().name);
      });
    });
  }
  var shellEvents = false;
  function shellListeners() {
    if (shellEvents) return; shellEvents = true;
    dashRoot().addEventListener("click", function (e) {
      var t = e.target.closest(".zd3-toggle");
      if (t) {
        var open = t.getAttribute("aria-expanded") !== "true", m = document.getElementById(t.getAttribute("aria-controls"));
        closeMenus(t); t.setAttribute("aria-expanded", String(open)); if (m) m.hidden = !open;
        return;
      }
      var g = e.target.closest("[data-go]");
      if (g && !(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); closeMenus(); go(g.dataset.go); }
    });
    document.addEventListener("click", function (e) { if (!e.target.closest(".zd3-pop")) closeMenus(); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && document.querySelector(".zd3-toggle[aria-expanded=true]")) {
        var open = document.querySelector(".zd3-toggle[aria-expanded=true]"); closeMenus(); open.focus(); return;
      }
      if ((e.metaKey || e.ctrlKey) && !e.altKey && String(e.key).toLowerCase() === "k") {
        var s = $("#zdSearch");
        if (s && s.offsetParent) { e.preventDefault(); s.focus(); s.select(); }
      }
    });
  }

  function render() {
    stopScanner();
    if (!ready) { shellOn(false); dashRoot().innerHTML = '<section class="auth err"><h1>Binnenkort</h1><p>Pasr voor ondernemers komt binnenkort.</p></section>'; return; }
    var h = location.hash.replace("#", "");
    if (!session) { shellOn(false); return loginView(h === "account" ? "signup" : h === "vergeten" ? "forgot" : "login"); }
    if (!dash.me) { shellOn(false); dashRoot().innerHTML = '<p class="zk-empty">Laden…</p>'; return refresh(); }
    if (dash.sub === "register" || !bizList().length) { shellOn(false); return registerView(); }
    var b = current(); dash.bizId = b.id;
    if (ALIAS[h]) { h = ALIAS[h]; history.replaceState(null, "", location.pathname + location.search + "#" + h); }
    var tabs = tabsFor(b), ids = tabs.map(function (t) { return t.id; });
    if (ids.indexOf(h) >= 0) dash.tab = h;
    if (ids.indexOf(dash.tab) < 0) dash.tab = b.role === "owner" ? (b.status === "blocked" ? "mijn-account" : (b.cards || []).length ? "vandaag" : "stempelkaarten") : "scannen";
    var tab = tabs.filter(function (t) { return t.id === dash.tab; })[0], app = isApp(b);
    var side = tabs.filter(function (t) { return t.group !== "mobile" && t.group !== "none"; });
    shellOn(true); shellListeners();
    dashRoot().innerHTML = '<div class="zd3 ' + (app ? "zd3--app" : "zd3--solo") + '">' + topbar(b, tabs) +
      '<div class="zd3-body">' + (app ? sideNav(side) : "") + '<div class="zd3-main">' + (dash.tab === "vandaag" && b.status === "pending" ? "" : banner(b)) +
      '<section id="zd-panel" class="zd-panel zd3-panel" aria-label="' + esc(tab.label) + '" tabindex="-1"></section></div></div>' + (app ? tabBar() : "") + "</div>";
    document.title = tab.label + " · " + b.name + " | Pasr voor ondernemers";
    bindShell(b);
    var panel = $("#zd-panel");
    if (b.status === "blocked" && b.role !== "owner") { panel.innerHTML = '<p class="zk-empty">Er is hier nu niets te doen.</p>'; return; }
    (VIEWS[tab.id] || function () {})(panel, b);
    communityBanner(b);
    if (app) loadExtra(b).then(function (x) { updateShell(b, x); });
  }
  async function refresh() {
    dash.extra = null;
    try { dash.me = await rpc("pasr_business_me", {}, true); }
    catch (e) {
      if (e.status === 401) { session = null; saveSession(null); navState(); }
      dash.me = null;
      if (session) { shellOn(false); dashRoot().innerHTML = '<div class="zd-state blocked" role="alert"><div><h2>Niet opgehaald</h2><p>' + esc(nice(e)) + '</p><p><button class="zk-btn" type="button" id="zdRetry">Opnieuw proberen</button></p></div></div>'; $("#zdRetry").addEventListener("click", refresh); return; }
    }
    render();
  }
  // ---- Prullenbak: verwijderde stempelkaarten, kortingsbonnen en actiecodes; hier definitief verwijderen ----
  async function mountTrash(root, business) {
    var kindLabels = { card: "Stempelkaart", coupon: "Kortingsbon", code: "Actiecode" };
    root.className = "pz2-panel";
    root.innerHTML = '<h3>Verwijderde items</h3><p role="status">Laden…</p>';
    var message = root.querySelector("[role=status]");
    try {
      var rows = await rpc("pasr_business_trash", { p_business: business.id }, true);
      if (!root.isConnected) return;
      message.textContent = rows.length ? "" : "De prullenbak is leeg.";
      if (!rows.length) return;
      var label = "Definitief verwijderen";
      var controls = document.createElement("div");
      controls.className = "zk-actions";
      controls.innerHTML = '<label><input type="checkbox" data-all> Alles selecteren</label> ' +
        '<button type="button" class="zk-btn ghost danger" data-bulk disabled> Selectie ' + label.toLowerCase() + "</button>";
      root.append(controls);
      var all = controls.querySelector("[data-all]");
      var bulk = controls.querySelector("[data-bulk]");
      var checks = [];
      var busy = false;
      function update() {
        var count = checks.filter(function (check) { return check.checked; }).length;
        all.checked = count === rows.length;
        all.indeterminate = count > 0 && count < rows.length;
        bulk.disabled = busy || count === 0;
      }
      async function remove(indices) {
        if (busy || !indices.length) return;
        if (!window.confirm(indices.length + " item(s) definitief verwijderen? Dit kan niet ongedaan worden gemaakt.")) return;
        busy = true;
        update();
        try {
          await rpc("pasr_business_delete_items", {
            p_business: business.id, p_permanent: true,
            p_items: indices.map(function (i) { return { id: rows[i].id, kind: rows[i].kind }; })
          }, true);
          await refresh();
          toast("Definitief verwijderd");
        } catch (e) {
          message.textContent = nice(e);
          busy = false;
          update();
        }
      }
      all.addEventListener("change", function () {
        checks.forEach(function (check) { check.checked = all.checked; });
        update();
      });
      bulk.addEventListener("click", function () {
        remove(rows.flatMap(function (_, i) { return checks[i].checked ? [i] : []; }));
      });
      rows.forEach(function (row, i) {
        var entry = document.createElement("article");
        entry.className = "pz2-coupon";
        entry.style.touchAction = "pan-y";
        entry.innerHTML = '<label><input type="checkbox"> <b>' + esc(row.title) + "</b> · " +
          esc(kindLabels[row.kind] || row.kind) + '</label> <button type="button" class="zk-btn ghost danger">' + label + "</button>";
        root.append(entry);
        var check = entry.querySelector("input");
        var button = entry.querySelector("button");
        checks.push(check);
        check.addEventListener("change", update);
        button.addEventListener("click", function () { remove([i]); });
        var start;
        entry.addEventListener("pointerdown", function (event) {
          if (event.target.closest("button,input") || !event.isPrimary) return;
          start = { x: event.clientX, y: event.clientY };
        });
        entry.addEventListener("pointercancel", function () { start = null; });
        entry.addEventListener("pointerup", function (event) {
          if (start && start.x - event.clientX > 55 && Math.abs(start.y - event.clientY) < 32) {
            button.classList.remove("ghost");
            button.classList.add("danger-solid");
            button.focus({ preventScroll: true });
          }
          start = null;
        });
      });
    } catch (e) { message.textContent = nice(e); }
  }

  VIEWS.prullenbak = function (panel, business) {
    panel.innerHTML = panelTitle("Prullenbak", "Verwijderde stempelkaarten, kortingsbonnen en actiecodes. Klanten zien ze niet meer; hier verwijder je ze definitief.") + '<section id="zdTrash"></section>';
    mountTrash($("#zdTrash"), business);
  };
  VIEWS.beloningen = function (panel, b) {
    if (window.PasrLoyalty2) window.PasrLoyalty2.settings(panel, b, rpc);
    else panel.textContent = "De instellingen zijn tijdelijk niet beschikbaar.";
  };
  VIEWS.vestigingen = function (panel, b) {
    if (window.PasrLoyalty2) window.PasrLoyalty2.locations(panel, b, rpc);
    else panel.textContent = "Vestigingen zijn tijdelijk niet beschikbaar.";
  };
  VIEWS.marketing = function (panel, b) {
    if (window.PasrLoyalty2) window.PasrLoyalty2.marketing(panel, b, rpc);
    else panel.textContent = "De marketingkalender is tijdelijk niet beschikbaar.";
  };
  // Inzichten: de cijfers over klantenbinding en bonnen, de grafiek per dag en het overzicht van je zakelijke producten.
  VIEWS.inzichten = function (panel, b) {
    panel.innerHTML = '<div id="inzTop"></div><div class="zd-insights" id="ovChart"><p class="zk-empty">Laden…</p></div>' +
      '<section class="pz2-panel"><h3>Overzicht zakelijke producten</h3><div id="ovBusinessProducts">Laden…</div></section>';
    var top = $("#inzTop");
    if (window.PasrLoyalty2) window.PasrLoyalty2.insights(top, b, rpc);
    else top.textContent = "Inzichten zijn tijdelijk niet beschikbaar.";
    drawInsights(b);
    loadExtra(b).then(function (x) {
      var el = $("#ovBusinessProducts"); if (!el) return;
      var cards = b.cards || [], coupons = x.coupons, codes = x.codes;
      el.innerHTML = '<div class="zd-kpis"><div class="zd-kpi"><small>Stempelkaarten online</small><b>' + cards.filter(function (c) { return c.published; }).length + "</b></div>" +
        '<div class="zd-kpi k1"><small>Actieve kortingsbonnen</small><b>' + (coupons ? coupons.filter(function (c) { return couponState(c)[1] === "on"; }).length : "–") + "</b></div>" +
        '<div class="zd-kpi k2"><small>Actieve actiecodes</small><b>' + (codes ? codes.filter(function (c) { return codeState(c)[1] === "on"; }).length : "–") + "</b></div>" +
        '<div class="zd-kpi k3"><small>Codegebruik totaal</small><b>' + (codes ? codes.reduce(function (n, c) { return n + Number(c.used_count || 0); }, 0) : "–") + "</b></div></div>";
    });
  };
  VIEWS["gezamenlijke-acties"] = function (panel, b) {
    if (window.PasrLoyalty2) window.PasrLoyalty2.community(panel, b, rpc);
    else panel.textContent = "Gezamenlijke acties konden niet worden geladen. Ververs de pagina.";
  };
  // ---- Tickets en Klantenkaarten (tickets-klantenkaart.js, docs/tickets-klantenkaart.md) ----
  function tkHelpers() {
    return { rpc: rpc, esc: esc, ICON: ICON, toast: toast, nice: nice, modal: modal, panelTitle: panelTitle, table: table, setMsg: setMsg, copy: copy,
      go: go, render: function () { render(); focusPanel(); }, state: dash, invalidate: function () { dash.extra = null; } };
  }
  VIEWS.tickets = function (panel, b) {
    if (window.PasrTK) window.PasrTK.tickets(panel, b, tkHelpers());
    else panel.textContent = "Tickets konden niet worden geladen. Ververs de pagina.";
  };
  VIEWS.klantenkaarten = function (panel, b) {
    if (window.PasrTK) window.PasrTK.cards(panel, b, tkHelpers());
    else panel.textContent = "Klantenkaarten konden niet worden geladen. Ververs de pagina.";
  };
  VIEWS.actiecodes = function (panel, b) {
    if (window.PasrPromoCodes) window.PasrPromoCodes.mount(panel, b, rpc);
    else panel.textContent = "Actiecodes kunnen niet worden geladen.";
  };
  VIEWS.promotiemateriaal = async function(panel,b) {
    panel.innerHTML=panelTitle("Promotiemateriaal","Kies een bestaande stempelkaart, kortingscoupon of actiecode. Download PNG's of een complete ZIP.")+
      '<section class="pz2-panel"><label class="pz2-field">Actie<select id="zkPromoProduct"><option value="">Producten laden…</option></select></label>'+
      '<p id="zkPromoStatus" role="status"></p><div id="zkPromoHub"></div></section>';
    var picker=$("#zkPromoProduct"),status=$("#zkPromoStatus"),target=$("#zkPromoHub"),products=[];
    (b.cards||[]).forEach(function(c){products.push({kind:"Stempelkaart",title:c.name,raw:Object.assign({},c,{business:b.name})});});
    var responses=await Promise.allSettled([
      rpc("pasr_business_coupon_list",{p_business:b.id},true),
      rpc("pasr_business_promo_list",{p_business:b.id},true)
    ]);
    if(responses[0].status==="fulfilled")responses[0].value.forEach(function(c){
      products.push({kind:"Kortingscoupon",title:c.title,raw:Object.assign({},c,{kind:"coupon",business:b.name,color:"#6A5CFF"})});
    });else status.textContent="Kortingscoupons konden niet worden geladen. ";
    if(responses[1].status==="fulfilled")responses[1].value.forEach(function(c){
      products.push({kind:"Actiecode",title:c.title+" · "+c.code,raw:Object.assign({},c,{kind:"code",business:b.name,color:"#6A5CFF"})});
    });else status.textContent+="Actiecodes konden niet worden geladen.";
    picker.innerHTML='<option value="">Kies een actie</option>'+products.map(function(p,i){
      return '<option value="'+i+'">'+esc(p.kind)+' · '+esc(p.title)+'</option>';
    }).join("");
    picker.addEventListener("change",function(){
      target.innerHTML="";
      if(picker.value==="")return;
      var p=products[Number(picker.value)];
      if(window.PasrPromo)window.PasrPromo.mount(target,p.raw);
      else target.textContent="Generator kon niet worden geladen.";
    });
  };
  VIEWS.kortingsbonnen = function (panel, b) {
    if (window.PasrLoyalty2) window.PasrLoyalty2.coupons(panel, b, rpc);
    else { panel.textContent = "Kortingsbonnen zijn tijdelijk niet beschikbaar."; return; }
    couponPreview(panel, b);
  };
  // Live voorbeeld van de kortingsbon in de huisstijl van de zaak, naast het formulier (zonder echte QR- of barcode).
  function couponPreview(panel, b) {
    var form = $("#pz2Coupon", panel);
    if (!form) {
      var mo = new MutationObserver(function () { if ($("#pz2Coupon", panel)) { mo.disconnect(); couponPreview(panel, b); } });
      mo.observe(panel, { childList: true, subtree: true }); setTimeout(function () { mo.disconnect(); }, 10000);
      return;
    }
    if (form.dataset.zdPreview) return;
    form.dataset.zdPreview = "1";
    var card = (b.cards || []).filter(function (c) { return c.logo; })[0] || (b.cards || [])[0] || {};
    var color = /^#[0-9a-f]{6}$/i.test(card.color || "") ? card.color : "#6A5CFF";
    var box = document.createElement("section");
    box.className = "pz2-panel zd-preview-panel";
    box.innerHTML = '<h3>Live voorbeeld in je huisstijl</h3><p class="zd-preview-sub">Voorbeeld van de uitstraling. Een unieke QR-code ontstaat pas wanneer een klant de bon bewaart.</p>' +
      '<div class="zd-coupon-preview" style="--coupon-color:' + color + '"><div class="zd-coupon-top"><div class="zd-coupon-business">' + (card.logo ? '<img src="' + imgSrc(card.logo) + '" alt="">' : "") + "<span>" + esc(b.name) + "</span></div>" +
      '<div class="zd-coupon-value"></div><div class="zd-coupon-desc"></div></div><div class="zd-coupon-bottom"><span></span><strong>pasr.</strong></div></div>' +
      '<p class="zd-coupon-note">Kleur en logo volgen je stempelkaart. Voor dit voorbeeld worden geen QR- of barcodes uitgegeven.</p>';
    form.after(box);
    var value = $(".zd-coupon-value", box), desc = $(".zd-coupon-desc", box), terms = $(".zd-coupon-bottom span", box);
    function update() {
      var f = new FormData(form), amount = Number(f.get("discount_value") || 0);
      value.textContent = money(f.get("discount_type"), amount).toUpperCase() + " KORTING";
      desc.textContent = String(f.get("title") || "Nieuwe kortingsbon");
      var min = Number(f.get("min_spend") || 0), end = f.get("ends_at");
      terms.textContent = (min > 0 ? "Vanaf " + money("amount", min) + " · " : "") + (end ? "Geldig t/m " + new Date(end + "T12:00:00").toLocaleDateString("nl-NL") : "");
    }
    form.addEventListener("input", update); form.addEventListener("change", update); update();
  }
  function panelTitle(title, sub, actions) {
    return '<div class="zd-ptitle"><div><h2 id="zd-title">' + esc(title) + "</h2>" + (sub ? '<p class="zd-sub">' + sub + "</p>" : "") + "</div>" + (actions || "") + "</div>";
  }
  function table(cols, rows, cls) {
    return '<div class="zd-tablewrap"><table class="zk-table zd-table ' + (cls || "") + '"><thead><tr>' + cols.map(function (c) { return '<th scope="col">' + c + "</th>"; }).join("") + "</tr></thead><tbody>" +
      rows.map(function (r) { return "<tr" + (r.attr || "") + ">" + r.cells.map(function (c, i) { return '<td data-label="' + esc(cols[i].replace(/<[^>]+>/g, "")) + '"><span>' + c + "</span></td>"; }).join("") + "</tr>"; }).join("") +
      "</tbody></table></div>";
  }

  // ---- Vandaag: begroeting, snelknoppen, cijfers met trend, Te doen, grafiek, je acties en wat er aan de toonbank gebeurde ----
  var METRICS = { stamps: ["Stempels", "stempels", "#12A77E", "#2ED3A6"], rewards: ["Beloningen", "beloningen", "#D2412E", "#FF6B57"], new_members: ["Nieuwe leden", "leden", "#4A3CE0", "#6A5CFF"] };
  var PERIODS = [[7, "W", "Week"], [30, "M", "Maand"], [90, "K", "Kwartaal"], [365, "J", "Jaar"]];
  function sumOf(arr, k) { return arr.reduce(function (a, d) { return a + (Number(d[k]) || 0); }, 0); }
  VIEWS.vandaag = function (panel, b) {
    if (dash.sub === "log") return logView(panel, b, 300);
    var now = new Date(), hr = now.getHours();
    var hello = hr < 6 ? "Goedenacht" : hr < 12 ? "Goedemorgen" : hr < 18 ? "Goedemiddag" : "Goedenavond";
    var name = session && session.first_name;
    var date = now.toLocaleDateString("nl-NL", { weekday: "long", day: "numeric", month: "long" });
    function quick(act, icon, label) { return '<button type="button" class="zd3-qbtn" data-quick="' + act + '">' + ICON[icon] + "<span>" + label + "</span></button>"; }
    panel.innerHTML = '<div class="zd3-hello"><div><p class="zd3-date">' + esc(date.charAt(0).toUpperCase() + date.slice(1)) + '</p><h2 id="zd-title">' + hello + (name ? ", " + esc(name) : "") + "</h2></div>" +
      '<div class="zd3-quick" role="group" aria-label="Nieuw maken">' + quick("card", "plus", "Stempelkaart") + quick("mcard", "mcard", "Klantenkaart") + quick("event", "ticket", "Event") +
      quick("kortingsbonnen", "tag", "Kortingsbon") + quick("actiecodes", "code", "Actiecode") + quick("gezamenlijke-acties", "users", "Gezamenlijke actie") + "</div></div>" +
      '<div class="zd3-kpis" id="tdKpi">' + ["Stempels", "Beloningen", "Nieuwe leden", "Terugkerend (90 d)"].map(function (t, i) {
        return '<div class="zd3-kpi"><small>' + t + (i < 3 ? '<span class="zd3-kpiw"> deze week</span>' : "") + "</small><b>–</b></div>";
      }).join("") + "</div>" +
      '<div class="zd3-kpis tk-kpirow" id="tdTk" hidden></div>' +
      '<div class="zd3-grid">' +
      '<section class="zd3-card zd3-todocard" id="tdTodo" aria-labelledby="tdTodoH"><div class="zd3-cardhead"><h3 id="tdTodoH">Te doen</h3></div><p class="zd3-muted">Laden…</p></section>' +
      '<section class="zd3-card zd3-chartcard" id="tdChart" aria-labelledby="tdChartH"><div class="zd3-cardhead"><h3 id="tdChartH">Stempels</h3></div><p class="zd3-muted">Laden…</p></section>' +
      '<section class="zd3-card" id="tdActs" aria-labelledby="tdActsH"><div class="zd3-cardhead"><h3 id="tdActsH">Je acties</h3><button type="button" class="zk-btn sm" id="tdNew">' + ICON.plus + 'Nieuw</button></div><div class="zd3-slot"><p class="zd3-muted">Laden…</p></div></section>' +
      '<section class="zd3-card" id="tdLog" aria-labelledby="tdLogH"><div class="zd3-cardhead"><h3 id="tdLogH">Vandaag aan de toonbank</h3></div><p class="zd3-muted">Laden…</p></section>' +
      '<section class="zd3-card" id="tdEvents" aria-labelledby="tdEvH" hidden><div class="zd3-cardhead"><h3 id="tdEvH">Komende events</h3><a class="zk-btn ghost sm" href="#tickets" data-go="tickets">Alle events' + ICON.chevron + '</a></div><div class="zd3-slot"></div></section></div>';
    panel.querySelectorAll("[data-quick]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var q = btn.dataset.quick;
        if (q === "card") openNewCard(b);
        else if (q === "mcard") { go("klantenkaarten"); dash.sub = "mc-edit"; dash.mcCard = null; render(); }
        else if (q === "event") { go("tickets"); dash.sub = "tk-edit"; dash.tkEvent = null; render(); }
        else go(q);
      });
    });
    $("#tdNew").addEventListener("click", function (ev) { createModal(b, ev.currentTarget); });
    todayKpis(b);
    drawToday(b);
    counterLog($("#tdLog"), b);
    loadExtra(b, true).then(function (x) {
      updateShell(b, x);
      var todo = $("#tdTodo", panel), acts = $("#tdActs", panel); if (!todo || !acts || !acts.isConnected || !acts.querySelector(".zd3-slot")) return;
      var items = todoItems(b, x);
      todo.innerHTML = '<div class="zd3-cardhead"><h3 id="tdTodoH">Te doen' + (items.length ? ' <span class="zd3-count">' + items.length + "</span>" : "") + "</h3></div>" +
        (items.length ? todoHtml(items) : '<p class="zd3-empty">' + ICON.check + "Niets te doen. Alles is bij.</p>");
      todo.querySelectorAll("[data-todo]").forEach(function (btn) {
        btn.addEventListener("click", function () { var t = items[Number(btn.dataset.todo)]; if (t.run) t.run(btn); else go(t.tab); });
      });
      if (window.PasrTK) {
        var tiles = window.PasrTK.kpiTiles(x, { esc: esc, ICON: ICON }), tk = $("#tdTk", panel), evc = $("#tdEvents", panel);
        if (tk && tiles) { tk.innerHTML = tiles; tk.hidden = false; }
        if (evc && ((x.events || []).length || (x.memberCards || []).length)) {
          evc.hidden = false; evc.querySelector(".zd3-slot").innerHTML = window.PasrTK.upcoming(x, { esc: esc });
          var upl = (x.events || []).filter(function (e) { return e.status !== "cancelled" && Date.parse(e.ends_at) > Date.now(); });
          evc.querySelectorAll("[data-upc]").forEach(function (u) { u.addEventListener("click", function () { var e = upl[Number(u.dataset.upc)]; go("tickets"); dash.sub = "tk-event"; dash.tkEvent = e; render(); }); });
        }
      }
      var rows = actionRows(b, x).sort(function (p, q) { return (q.live ? 1 : 0) - (p.live ? 1 : 0); }), shown = rows.slice(0, 6);
      acts.querySelector(".zd3-slot").outerHTML = shown.length ? rowList(shown) + (rows.length > shown.length ? '<p class="zd-more"><a class="zk-btn ghost sm" href="#alle-acties" data-go="alle-acties">Alle ' + rows.length + " acties" + ICON.chevron + "</a></p>" : "")
        : '<p class="zd3-empty">Nog geen acties. Maak je eerste stempelkaart, kortingsbon of actiecode.</p>';
      bindRows(acts, shown);
    });
  };
  async function todayKpis(b) {
    var box = $("#tdKpi"); if (!box) return;
    var res = await Promise.allSettled([rpc("pasr_business_stats", { p_business: b.id, p_days: 14 }, true), rpc("pasr_business_loyalty_insights", { p_business: b.id }, true)]);
    box = $("#tdKpi"); if (!box) return;
    var cells = box.querySelectorAll(".zd3-kpi");
    // vergelijken kan pas als de zaak de hele vorige week al bestond
    var compare = !b.created_at || Date.now() - Date.parse(b.created_at) >= 14 * DAY;
    function trend(cur, prev) {
      if (!compare) return "";
      var d = cur - prev;
      if (!d) return '<span class="zd3-trend">Gelijk aan vorige week</span>';
      var pct = prev ? Math.round(Math.abs(d) / prev * 100) + "%" : String(Math.abs(d));
      return '<span class="zd3-trend ' + (d > 0 ? "up" : "down") + '"><span aria-hidden="true">' + (d > 0 ? "▲" : "▼") + "</span> " + (d > 0 ? "+" : "−") + pct +
        ' <span class="zd3-trendlbl">t.o.v. vorige week</span><span class="sr-only"> (' + (d > 0 ? "meer" : "minder") + " dan vorige week: " + prev + ")</span></span>";
    }
    if (res[0].status === "fulfilled") {
      var all = (res[0].value && res[0].value.days) || [], cur = all.slice(-7), prev = all.slice(0, Math.max(0, all.length - 7));
      ["stamps", "rewards", "new_members"].forEach(function (k, i) {
        var c = sumOf(cur, k), p = sumOf(prev, k);
        cells[i].innerHTML = "<small>" + cells[i].querySelector("small").innerHTML + "</small><b>" + c.toLocaleString("nl-NL") + "</b>" + (prev.length === 7 ? trend(c, p) : "");
      });
    } else for (var i = 0; i < 3; i++) cells[i].insertAdjacentHTML("beforeend", '<span class="zd3-trend">' + esc(nice(res[0].reason)) + "</span>");
    if (res[1].status === "fulfilled") {
      var x = res[1].value || {}, members = Number(x.members || 0), ret = Number(x.returning_customers_90d || 0);
      cells[3].innerHTML = "<small>Terugkerend (90 d)</small><b>" + (members ? Math.round(ret / members * 100) + "%" : ret.toLocaleString("nl-NL")) + "</b>" +
        '<span class="zd3-trend">' + (members ? ret.toLocaleString("nl-NL") + " van " + plural(members, "klant", "klanten") : "klanten met 2+ stempelacties") + "</span>";
    }
  }
  async function drawToday(b) {
    var box = $("#tdChart"); if (!box) return;
    var days = dash.today.days, m = METRICS.stamps, data;
    try { data = await rpc("pasr_business_stats", { p_business: b.id, p_days: days }, true); }
    catch (e) { box.innerHTML = '<div class="zd3-cardhead"><h3 id="tdChartH">Stempels</h3></div><p class="zk-empty">' + esc(nice(e)) + "</p>"; return; }
    box = $("#tdChart"); if (!box) return;
    var rows = data.days || [], total = sumOf(rows, "stamps");
    var range = rows.length ? dayLabel(rows[0].day) + " – " + dayLabel(rows[rows.length - 1].day) : "";
    box.innerHTML = '<div class="zd3-cardhead"><div><h3 id="tdChartH">Stempels</h3><p class="zd3-chartval"><b id="ziVal">' + total + '</b> stempels · <span id="ziWhen">' + esc(range) + "</span></p></div>" +
      '<div class="zi-seg" role="group" aria-label="Periode">' + [[7, "7 d", "7 dagen"], [30, "30 d", "30 dagen"], [365, "Jaar", "Een jaar"]].map(function (p) {
        return '<button type="button" data-d="' + p[0] + '" aria-pressed="' + (p[0] === days) + '" aria-label="' + p[2] + '">' + p[1] + "</button>";
      }).join("") + "</div></div>" + chartHtml(rows, "stamps", m) +
      '<p class="sr-only">Stempels: ' + total + " in " + esc(range) + ".</p>";
    box.querySelectorAll("[data-d]").forEach(function (x) { x.addEventListener("click", function () { dash.today.days = Number(x.dataset.d); drawToday(b).then(function () { var f = $('#tdChart [data-d="' + x.dataset.d + '"]'); if (f) f.focus(); }); }); });
    bindChart(box, rows, "stamps", m, total, range);
  }
  // Wat er vandaag aan de toonbank gebeurde (uit het logboek); is het vandaag nog stil, dan de laatste gebeurtenissen.
  async function counterLog(box, b) {
    var head = '<div class="zd3-cardhead"><h3 id="tdLogH">Vandaag aan de toonbank</h3></div>';
    try {
      var r = await rpc("pasr_business_log", { p_business: b.id, p_limit: 12 }, true), ev = r.events || [];
      if (!box.isConnected) return;
      var today = new Date().toDateString();
      var todays = ev.filter(function (x) { return new Date(x.at).toDateString() === today; });
      var list = todays.length ? todays.slice(0, 6) : ev.slice(0, 4);
      var rows = list.map(function (x) {
        var what = x.kind === "stamp" ? ((x.amount || 1) > 1 ? x.amount + " stempels gezet" : "Stempel gezet") : (KIND[x.kind] || x.kind);
        var d = new Date(x.at), t = todays.length ? d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" }) : d.toLocaleDateString("nl-NL", { day: "numeric", month: "short" });
        var sub = [x.card_name || "verwijderde kaart", x.by_role === "customer" ? "" : "door " + (x.by_name || "—")].filter(Boolean).join(" · ");
        return '<li class="' + (x.undone ? "undone" : "") + '"><time datetime="' + esc(x.at) + '">' + esc(t) + "</time><span><b>" + esc(what) + (x.undone ? " <small>(ongedaan)</small>" : "") + "</b><small>" + esc(sub) + "</small></span></li>";
      }).join("");
      box.innerHTML = head + (todays.length ? "" : '<p class="zd3-muted">' + (ev.length ? "Vandaag nog niets gebeurd. Dit was het laatst:" : "Nog niets gebeurd. Zodra je de eerste klant scant, staat het hier.") + "</p>") +
        (rows ? '<ol class="zd3-timeline">' + rows + "</ol>" : "") +
        (ev.length ? '<p class="zd-more"><button class="zk-btn ghost sm" type="button" id="lgAll">Hele logboek bekijken' + ICON.chevron + "</button></p>" : "");
      var all = $("#lgAll", box); if (all) all.addEventListener("click", function () { dash.sub = "log"; render(); focusPanel(); });
    } catch (e) { box.innerHTML = head + '<p class="zk-empty">' + esc(nice(e)) + "</p>"; }
  }

  // ---- Acties (telefoon): alles op één lijst met filters ----
  var FILTERS = [["alles", "Alles"], ["card", "Stempelkaarten"], ["mcard", "Klantenkaarten"], ["event", "Tickets"], ["coupon", "Bonnen"], ["code", "Codes"], ["community", "Samen"]];
  VIEWS["alle-acties"] = function (panel, b) {
    panel.innerHTML = panelTitle("Acties", "Je stempelkaarten, klantenkaarten, events, kortingsbonnen, actiecodes en gezamenlijke acties.", '<button class="zk-btn" type="button" id="aaNew">' + ICON.plus + "Nieuw</button>") +
      '<div class="zd3-chips" role="group" aria-label="Soort actie">' + FILTERS.map(function (f) { return '<button type="button" data-f="' + f[0] + '" aria-pressed="' + (dash.filter === f[0]) + '">' + f[1] + "</button>"; }).join("") + "</div>" +
      '<div id="aaList" aria-live="polite"><p class="zd3-muted">Laden…</p></div>';
    $("#aaNew").addEventListener("click", function (ev) { createModal(b, ev.currentTarget); });
    var data = null;
    function draw() {
      var box = $("#aaList"); if (!box || !data) return;
      var rows = actionRows(b, data).filter(function (r) { return dash.filter === "alles" || r.kind === dash.filter; });
      var hero = (dash.filter === "alles" || dash.filter === "card") ? (b.cards || []).filter(function (c) { return c.published; })[0] || (b.cards || [])[0] : null;
      var heroRow = hero ? rows.filter(function (r) { return r.kind === "card" && r.title === hero.name; })[0] : null;
      if (heroRow) rows.splice(rows.indexOf(heroRow), 1);
      box.innerHTML = (hero ? '<button type="button" class="zd3-hero" id="aaHero"><span class="sr-only">' + esc(hero.name) + " openen</span>" + stampCard(hero, null) + "</button>" : "") +
        (rows.length ? rowList(rows, "boxed") : hero ? "" : '<p class="zd3-empty">' + (dash.filter === "alles" ? "Nog geen acties. Tik op Nieuw om te beginnen." : "Geen acties van deze soort.") + "</p>");
      bindRows(box, rows);
      var hb = $("#aaHero"); if (hb) hb.addEventListener("click", function () { openCard(hero); });
    }
    panel.querySelectorAll("[data-f]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        dash.filter = btn.dataset.f;
        panel.querySelectorAll("[data-f]").forEach(function (x) { x.setAttribute("aria-pressed", String(x === btn)); });
        draw();
      });
    });
    loadExtra(b, true).then(function (x) { data = x; updateShell(b, x); draw(); });
  };
  // ---- Meer (telefoon): de overige onderdelen in groepen ----
  VIEWS.meer = function (panel, b) {
    var skip = ["vandaag", "alle-acties", "meer", "scannen", "inzichten", "stempelkaarten"];
    var tabs = tabsFor(b).filter(function (t) { return skip.indexOf(t.id) < 0; });
    var html = panelTitle("Meer", "");
    GROUPS.concat(["foot"]).forEach(function (g, i) {
      var list = tabs.filter(function (t) { return t.group === g; });
      if (!list.length) return;
      html += '<h3 class="zd3-group" id="mg' + i + '">' + (g === "foot" ? "Overig" : esc(g)) + '</h3><ul class="zd3-morelist" aria-labelledby="mg' + i + '">' + list.map(function (t) { return navLink(t); }).join("") + "</ul>";
    });
    panel.innerHTML = html;
    loadExtra(b).then(function (x) { updateShell(b, x); });
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
    if (!compact) box.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="lgBack">' + ICON.back + "Vandaag</button></p>" + panelTitle("Logboek", "Elke stempel, inwisseling en ongedaanmaking met wie, wat en wanneer. Niemand kan het logboek wissen, ook jij niet.") + '<div class="zk-panel" id="lgBody"><p class="zk-empty">Laden…</p></div>';
    if (!compact) $("#lgBack").addEventListener("click", function () { dash.sub = null; render(); focusPanel(); });
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
    panel.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="mBack">' + ICON.back + "Stempelkaarten</button></p>" +
      panelTitle("Leden van " + c.name, c.stamps_total + " stempels voor " + esc(c.reward)) + '<div class="zk-panel" id="mBody"><p class="zk-empty">Laden…</p></div>';
    $("#mBack").addEventListener("click", function () { dash.sub = null; dash.edit = null; render(); focusPanel(); });
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

  // ---- Stempelkaarten: maken, bewerken, publiceren, huisstijl, QR, link, flyer, leden en verwijderen (naar de Prullenbak) ----
  function createModal(b, opener) {
    var cards = b.cards || [];
    var md = modal("Wat wil je aanmaken?",
      '<h2>Wat wil je aanmaken?</h2><p>Kies een actie voor ' + esc(b.name) + '.</p>' +
      '<div class="zd-modal-foot zd3-create">' +
      '<button class="zk-btn" id="zkCreateCard" type="button"' + (cards.length >= 5 ? ' disabled' : '') + '>' + ICON.card + 'Stempelkaart</button>' +
      '<button class="zk-btn" id="zkCreateMcard" type="button">' + ICON.mcard + 'Klantenkaart</button>' +
      '<button class="zk-btn" id="zkCreateEvent" type="button">' + ICON.ticket + 'Event met tickets</button>' +
      '<button class="zk-btn" id="zkCreateCoupon" type="button">' + ICON.tag + 'Kortingsbon</button>' +
      '<button class="zk-btn" id="zkCreatePromo" type="button">' + ICON.code + 'Actiecode</button>' +
      '<button class="zk-btn" id="zkCreateCommunity" type="button">' + ICON.users + 'Gezamenlijke actie</button>' +
      '<button class="zk-btn" id="zkCreateAction" type="button"' + (!cards.length ? ' disabled' : '') + '>' + ICON.gift + 'Beloning</button>' +
      '<button class="zk-btn ghost" id="zkCreateClose" type="button">Annuleren</button></div>' +
      (cards.length >= 5 ? '<p class="zd-help">Je hebt al 5 stempelkaarten, het maximum.</p>' : ""), opener);
    $("#zkCreateCard", md.el).addEventListener("click", function () { md.close(); openCard(null); });
    $("#zkCreateCoupon", md.el).addEventListener("click", function () { md.close(); go("kortingsbonnen"); });
    $("#zkCreateMcard", md.el).addEventListener("click", function () { md.close(); go("klantenkaarten"); dash.sub = "mc-edit"; dash.mcCard = null; render(); });
    $("#zkCreateEvent", md.el).addEventListener("click", function () { md.close(); go("tickets"); dash.sub = "tk-edit"; dash.tkEvent = null; render(); });
    $("#zkCreatePromo", md.el).addEventListener("click", function () { md.close(); go("actiecodes"); });
    $("#zkCreateCommunity", md.el).addEventListener("click", function () { md.close(); go("gezamenlijke-acties"); });
    $("#zkCreateAction", md.el).addEventListener("click", function () { md.close(); go("beloningen"); });
    $("#zkCreateClose", md.el).addEventListener("click", md.close);
  }
  function deleteCard(c, opener, after) {
    var md = modal("Stempelkaart verwijderen", '<h2>' + esc(c.name) + ' verwijderen?</h2><p>De kaart gaat naar de Prullenbak en klanten zien hem niet meer. Definitief verwijderen doe je in de Prullenbak; het logboek blijft altijd staan.</p>' +
      '<p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="dNo">Annuleren</button><button class="zk-btn danger-solid" type="button" id="dYes">' + ICON.trash + "Naar de Prullenbak</button></p>", opener);
    $("#dNo", md.el).addEventListener("click", md.close);
    $("#dYes", md.el).addEventListener("click", async function (ev) {
      ev.currentTarget.disabled = true;
      try { await rpc("pasr_business_card_delete", { p_card: c.id }, true); md.close(); dash.sub = null; dash.edit = null; await refresh(); toast("Verplaatst naar de Prullenbak"); }
      catch (e) { md.close(); if (after) after(nice(e)); else toast(nice(e)); }
    });
  }
  VIEWS.stempelkaarten = function (panel, b) {
    if (dash.sub === "edit") return editView(panel, b);
    if (dash.sub === "members" && dash.edit) return membersView(panel, b);
    var cards = b.cards || [], approved = b.status === "approved";
    var add = '<button class="zk-btn" id="zkNew" type="button">' + ICON.plus + "Nieuw</button>";
    var html = panelTitle("Stempelkaarten", plural(cards.length, "stempelkaart", "stempelkaarten") + " van de 5" + (approved ? "" : " · online zetten kan na goedkeuring"), cards.length ? add : "");
    if (!cards.length) {
      html += '<div class="zk-panel zd-first"><div class="zd-first-card">' + stampCard({ name: "Koffiekaart", business: b.name, city: b.city, color: "#6A5CFF", stamps_total: 10, reward: "1 gratis koffie" }, 4) + "</div><div><h3>Je eerste stempelkaart</h3><p>Kies een naam, je logo en kleur, hoeveel stempels er op een kaart gaan en wat je klant daarvoor krijgt." +
        (b.website ? " We halen je logo en kleur alvast van " + esc(b.website.replace(/^https?:\/\//, "").replace(/\/.*$/, "")) + "." : "") + "</p>" +
        '<button class="zk-btn" id="zkFirst" type="button">' + ICON.plus + "Stempelkaart ontwerpen</button></div></div>";
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
          '<button class="zk-btn ghost sm" type="button" data-act="members">' + ICON.users + "Leden</button>" +
          '<button class="zk-btn ghost sm danger" type="button" data-act="delete">' + ICON.trash + 'Verwijderen<span class="sr-only"> ' + esc(c.name) + "</span></button></div></div></article>";
      }).join("") + "</div>";
    }
    panel.innerHTML = html;
    var nb = $("#zkNew"); if (nb) nb.addEventListener("click", function () { createModal(b, nb); });
    var first = $("#zkFirst"); if (first) first.addEventListener("click", function () { openCard(null); });
    panel.querySelectorAll(".zk-card button[data-act]").forEach(function (btn) {
      btn.addEventListener("click", async function () {
        var id = btn.closest(".zk-card").dataset.id, card = cards.filter(function (c) { return c.id === id; })[0];
        if (btn.dataset.act === "edit") { dash.edit = card; dash.sub = "edit"; render(); focusPanel(); }
        if (btn.dataset.act === "share") shareModal(card, btn);
        if (btn.dataset.act === "promo") promoModal(card, btn);
        if (btn.dataset.act === "members") { dash.edit = card; dash.sub = "members"; render(); focusPanel(); }
        if (btn.dataset.act === "delete") deleteCard(card, btn);
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
    panel.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="cBack">' + ICON.back + "Stempelkaarten</button></p>" +
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
    var back = function () { dash.sub = null; dash.edit = null; render(); focusPanel(); };
    $("#cBack").addEventListener("click", back); $("#cCancel").addEventListener("click", back);
    var del = $("#cDel");
    if (del) del.addEventListener("click", function () { deleteCard(c, del, function (m) { setMsg($("#cMsg"), m); }); });
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
          $("#bizRebrand").addEventListener("click", function () { dash.edit = current().cards[0]; dash.rebrand = true; dash.tab = "stempelkaarten"; history.pushState(null, "", "#stempelkaarten"); dash.sub = "edit"; render(); });
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
    var referral = new URLSearchParams(location.search).get("ref");
    if(referral && !/^PR[0-9A-F]{30}$/i.test(referral)) referral = null;
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
        '<div class="actions"><a class="btn btn-primary" href="pasr://zakelijk?ref=' + encodeURIComponent(referral || "") + '#' + esc(id) + '">Open in Pasr</a><a class="btn btn-ghost" href="' + APP_STORE + '" rel="noopener">Pasr voor iPhone</a><a class="btn btn-ghost" href="/android/">Pasr voor Android</a></div>' +
        '<p class="note">Geen app? <button class="zk-btn sm" id="jJoin" type="button">Gebruik de kaart in je browser</button></p>' +
        (referral ? '<p class="zd-help">Vriendenactie: de bonus komt pas na je eerste aankoop. Log in met je Pasr-account.</p>' +
        '<form id="jReferralLogin" class="zk-form" style="max-width:410px"><label>E-mail<input name="email" type="email" autocomplete="email" required></label>' +
        '<label>Wachtwoord<input name="password" type="password" autocomplete="current-password" required></label>' + HP_HTML + '<button class="zk-btn ghost" type="submit">Inloggen</button></form>' : '') +
        '<span id="jHp">' + HP_HTML + "</span>" +
        '<p class="zk-msg" id="jMsg" role="status"></p>' +
        '<p class="note" style="font-size:14px">Je krijgt een anonieme lidcode; Pasr vraagt geen naam of e-mailadres. <a href="/privacy/#stempelkaarten-van-ondernemers">Privacy</a></p>';
      var loginForm = $("#jReferralLogin");
      if (loginForm) loginForm.addEventListener("submit", async function (ev) {
        ev.preventDefault();
        if (isBot(loginForm)) return setMsg($("#jMsg"), "E-mailadres of wachtwoord klopt niet.");   // bot: niets versturen
        try {
          keep(await http("auth/v1/token?grant_type=password", {
            email: loginForm.elements.email.value.trim(), password: loginForm.elements.password.value
          }));
          loginForm.innerHTML = '<p class="zd-ready">Ingelogd! Je kunt nu deelnemen aan de vriendenactie.</p>';
          setMsg($("#jMsg"), "Ingelogd", true);
        } catch(e) { setMsg($("#jMsg"), nice(e)); }
      });
      $("#jJoin").addEventListener("click", async function (ev) {
        ev.target.disabled = true;
        // bot: er gaat niets naar de server en er komt geen melding; de knop werkt na even weer
        if (isBot($("#jHp"))) return setTimeout(function () { ev.target.disabled = false; }, 1500);
        try {
          var m;
          if (referral) {
            if (!await token()) throw new Error("Log eerst in bij Pasr om de vriendenuitnodiging te gebruiken.");
            m = await rpc("pasr_business_referral_join",{p_card:id,p_token:referral},true);
          } else {
            m = await rpc("pasr_business_join",{p_card:id});
          }
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
    var coupon = t.match(/PC[A-HJ-NP-Z2-9]{22}(?![A-HJ-NP-Z2-9])/);
    if (coupon) return coupon[0];
    var m = t.match(/PZ(?:[A-HJ-NP-Z2-9]{14}|[A-HJ-NP-Z2-9]{10})(?![A-HJ-NP-Z2-9])/);
    return m ? m[0] : null;
  }
  /** Ticketcode (base32) of kaartnummer van een klantenkaart met barcode (KS-000124, EAN-13). */
  function otherCode(text) {
    var t = String(text || "").trim().toUpperCase().replace(/\s+/g, "");
    if (!window.PasrTK || /^P[CZ]/.test(t)) return null;
    return /^[A-Z0-9-]{4,40}$/.test(t) ? t : null;
  }
  var scanner = null;   // { stop } van de scanner die nu loopt
  function stopScanner() { if (scanner) { scanner.stop(); scanner = null; } }

  /** Scanner in `root`. opts.auto = camera meteen aan (losse scanpagina); anders met de knop Camera aan. */
  function mountScanner(root, opts) {
    stopScanner();
    var DEVICE = "Webscanner";
    var selectedLocation = "";
    root.innerHTML =
      '<div class="pz2-controls" id="pz2ScanLocations" hidden><label>Stempels voor vestiging <select id="pz2ScanLocation"><option value="">Geen vestiging geselecteerd</option></select></label></div>'+
      '<div class="zk-cam" id="sCam"><video id="sVideo" playsinline muted aria-hidden="true"></video><span class="frame" aria-hidden="true"></span>' +
      '<div class="zk-cam-off" id="sOff"><span>' + ICON.camera + '</span><p>Scan de QR-code op de kaart van je klant.</p><button class="zk-btn mint" type="button" id="sStart">' + ICON.camera + "Camera aan</button></div>" +
      '<span class="hint" id="sHint" aria-live="polite"></span></div>' +
      '<div class="pz2-controls tk-pick" id="tkPickBox" hidden></div>' +
      '<form id="sManual" class="zk-form zd-manual" novalidate><label for="sCode">Of typ de code van je klant</label><span class="row"><input id="sCode" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="PZ…, ticketcode of kaartnummer" aria-describedby="sCodeHelp"><button class="zk-btn dark" type="submit">' + ICON.search + "Zoek</button></span>" +
      '<small id="sCodeHelp" class="zd-help">Stempelkaart: begint met PZ. Ook tickets van je events en je klantenkaarten met barcode werken hier.</small></form>' +
      '<p class="zk-msg" id="sMsg" role="status" aria-live="assertive"></p><div id="sResult"></div>';
    if (opts.zaak && opts.zaak.id) {
      rpc("pasr_business_locations_list",{p_business:opts.zaak.id},true).then(function(rows){
        if(!Array.isArray(rows)||!rows.some(function(x){return x.active;}))return;
        var box=$("#pz2ScanLocations",root),select=$("#pz2ScanLocation",root);
        rows.filter(function(x){return x.active;}).forEach(function(l){
          var opt=document.createElement("option");opt.value=l.id;opt.textContent=l.name;select.appendChild(opt);
        });
        var key="pasr.zakelijk.scan.location."+opts.zaak.id;
        var prior=store(key);if(rows.some(function(x){return x.id===prior && x.active;})){select.value=prior;selectedLocation=prior;}
        box.hidden=false;
        select.addEventListener("change",function(){selectedLocation=select.value;store(key,selectedLocation);});
      }).catch(function(){/* Scanner blijft beschikbaar zonder filiaalkeuze. */});
    }
    var video = $("#sVideo", root), busy = false, last = "", lastAt = 0, stream = null, alive = true, undoTimer = null;
    var detector = null;
    if ("BarcodeDetector" in window) {
      // klantenkaarten met barcode: ook Code 128 en EAN-13 (als de browser ze kent)
      try { detector = new window.BarcodeDetector({ formats: ["qr_code", "code_128", "ean_13"] }); }
      catch (e) { try { detector = new window.BarcodeDetector({ formats: ["qr_code"] }); } catch (e2) { detector = null; } }
    }
    // tickets en klantenkaarten (tickets-klantenkaart.js): welke zaak, en eventueel welk event aan de deur
    var tkZaak = opts.zaak && opts.zaak.id ? opts.zaak.id : null, tkEvent = dash.scanEvent || null;
    function withZaak() {
      if (tkZaak) return Promise.resolve(tkZaak);
      return rpc("pasr_business_me", {}, true).then(function (me) {
        var list = (me && me.businesses) || [], id = store(BIZ_KEY);
        var z = list.filter(function (x) { return x.id === id; })[0] || list[0];
        tkZaak = z ? z.id : null; return tkZaak;
      });
    }
    if (window.PasrTK) withZaak().then(function (z) { if (z) window.PasrTK.eventPicker($("#tkPickBox", root), tkHelpers(), z, function (v) { tkEvent = v; dash.scanEvent = v; }, tkEvent); }).catch(function () {});
    var canvas = document.createElement("canvas"), ctx = canvas.getContext("2d", { willReadFrequently: true });
    function stop() {
      alive = false; clearInterval(undoTimer);
      if (stream) { stream.getTracks().forEach(function (t) { t.stop(); }); stream = null; }
    }
    scanner = { stop: stop };

    async function show(code) {
      busy = true; setMsg($("#sMsg", root), "");
      try {
        if (!/^P[CZ]/.test(code) && window.PasrTK) {
          var z = await withZaak();
          if (!z) { setMsg($("#sMsg", root), "Geen zaak gevonden voor dit account."); busy = false; return; }
          await window.PasrTK.scan($("#sResult", root), tkHelpers(), z, code, tkEvent);
          busy = false; return;
        }
        if (/^PC[A-HJ-NP-Z2-9]{22}$/.test(code)) {
          var coupon = await rpc("pasr_business_coupon_check",{p_code:code},true);
          var amount = coupon.discount_type === "percent" ? coupon.discount_value + "%" :
            new Intl.NumberFormat("nl-NL",{style:"currency",currency:"EUR"}).format(coupon.discount_value);
          $("#sResult",root).innerHTML =
            '<div class="pz2-panel"><h2>Kortingsbon · '+esc(coupon.business)+'</h2>' +
            '<h3>'+esc(coupon.title)+'</h3><p><strong>'+esc(amount)+' korting</strong></p>' +
            '<p>Minimale besteding: € '+esc(coupon.min_spend)+'. '+esc(coupon.description)+'</p>' +
            (coupon.valid ? '<button class="zk-btn mint" type="button" id="pz2RedeemScan">Korting gegeven · verzilver bon</button>' :
              '<p class="zk-msg bad">Bon al gebruikt of niet meer geldig.</p>') + '</div>';
          var redeemButton=$("#pz2RedeemScan",root);
          if (redeemButton) redeemButton.addEventListener("click",async function(){
            if(!confirm("Weet je zeker dat je deze korting hebt gegeven? Na verzilveren kan deze code niet opnieuw gebruikt worden.")) return;
            redeemButton.disabled=true;
            try {
              await rpc("pasr_business_coupon_redeem",{p_code:code},true);
              setMsg($("#sMsg",root),"Kortingsbon verzilverd",true);
              $("#sResult",root).innerHTML='<p class="zd-ready">Deze kortingsbon is gebruikt.</p>';
            } catch(e) { redeemButton.disabled=false;setMsg($("#sMsg",root),nice(e)); }
          });
          busy=false;return;
        }
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
        '<div id="pz2Milestones" class="pz2-milestones" aria-live="polite"></div>' +
        '<div id="pz2Community" class="pz2-milestones" aria-live="polite"></div>' +
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
      $("#sStamp", root).addEventListener("click", function(ev){
        var args={p_code:m.member_code,p_amount:amount,p_device:DEVICE};
        if(selectedLocation)args.p_location=selectedLocation;
        act(ev.currentTarget,selectedLocation?"pasr_business_stamp_location":"pasr_business_stamp",
          args,amount===1?"Stempel gezet":amount+" stempels gezet");
      });
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
      if (m.member_code) {
        rpc("pasr_business_reward_progress",{p_code:m.member_code},true).then(function(list){
          var el = $("#pz2Milestones",root);
          if(!el || !Array.isArray(list) || !list.length) return;
          el.innerHTML = '<h3>Tussentijdse beloningen</h3>' + list.map(function(r){
            return '<div class="pz2-milestone"><span><b>'+esc(r.stamps)+' stempels</b> · '+esc(r.title)+'</span>' +
              '<button class="zk-btn ghost sm" data-milestone="'+r.stamps+'"'+(r.available?'':' disabled')+'>' +
              (r.available?'Uitgeven':'Niet beschikbaar')+'</button></div>';
          }).join("");
          el.querySelectorAll("button:not([disabled])").forEach(function(btn){
            btn.addEventListener("click",async function(){
              if(!confirm("Tussentijdse beloning definitief uitgeven?")) return;
              btn.disabled=true;
              try {
                var fresh=await rpc("pasr_business_reward_claim",
                  {p_code:m.member_code,p_stamps:Number(btn.dataset.milestone)},true);
                result(fresh);toast("Tussentijdse beloning uitgegeven");
              } catch(e){btn.disabled=false;toast(nice(e));}
            });
          });
        }).catch(function(){});
      }
      // gezamenlijke winkelstraatacties van deze zaak met de voortgang van deze klant (eigenaar en medewerkers)
      var zaakId = m.business_id || (opts.zaak && opts.zaak.id);
      if (m.member_code && zaakId) {
        rpc("pasr_business_community_member",{p_business:zaakId,p_member_code:m.member_code},true).then(function(list){
          var el = $("#pz2Community",root);
          if(!el || !Array.isArray(list) || !list.length) return;
          el.innerHTML = '<h3>Gezamenlijke acties</h3>' + list.map(function(c){
            var ready = !c.claimed && Number(c.visited) >= Number(c.required);
            return '<div class="pz2-milestone"><span><b>'+esc(c.name)+'</b> · '+esc(c.reward)+'<br><small>'+
              (c.claimed?'Al uitgegeven':esc(Math.min(Number(c.visited)||0,Number(c.required)||0))+' van '+esc(c.required)+' winkels bezocht')+'</small></span>' +
              '<button class="zk-btn ghost sm" data-community="'+esc(c.id)+'"'+(ready?'':' disabled')+'>' +
              (c.claimed?'Uitgegeven':(ready?'Uitgeven':'Nog niet'))+'</button></div>';
          }).join("");
          el.querySelectorAll("button:not([disabled])").forEach(function(btn){
            btn.addEventListener("click",async function(){
              if(!confirm("Gezamenlijke beloning uitgeven? Dit kan maar één keer per klant.")) return;
              btn.disabled=true;
              try {
                var r=await rpc("pasr_business_community_claim",
                  {p_campaign:btn.dataset.community,p_business:zaakId,p_member_code:m.member_code},true);
                btn.textContent="Uitgegeven";
                setMsg($("#sMsg", root), "Gezamenlijke beloning uitgegeven: "+(r.reward||"beloning"), true);
              } catch(e){btn.disabled=false;setMsg($("#sMsg", root), nice(e));}
            });
          });
        }).catch(function(){});
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
      var raw = $("#sCode", root).value.replace(/\s+/g, "");
      var c = codeFrom(raw) || otherCode(raw);
      if (!c) { $("#sCode", root).focus(); return setMsg($("#sMsg", root), "Een stempelkaart begint met PZ; een kortingsbon met PC. Tickets en klantenkaarten: typ de code of het kaartnummer."); }
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
        var c = codeFrom(text) || otherCode(text);
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
    root.innerHTML = '<div class="zk-top"><div><span class="zk-kicker">Scanner</span><h1>Scannen</h1></div><a class="zk-btn ghost sm" href="/zakelijk/dashboard/">Dashboard</a></div><div id="sRoot"></div>';
    mountScanner($("#sRoot"), { auto: true });
  }

  // ---------------------------------------------------------------- uitnodiging gezamenlijke actie: ?t=<token>
  async function communityInvitePage(t) {
    function box(html) { dashRoot().innerHTML = '<section class="auth zk-ci">' + '<div class="badge">' + ICON.users + "</div>" + html + "</section>"; }
    if (!ready) return box("<h1>Even niet beschikbaar</h1><p>Probeer het later opnieuw.</p>");
    var p;
    try { p = await rpc("pasr_business_community_invite_preview", { p_token: t }); } catch (e) { return box("<h1>Niet opgehaald</h1><p>Geen verbinding met Pasr. Laad de pagina opnieuw.</p>"); }
    var st = p && p.status;
    if (st !== "invited") {
      communityToken(null);
      var why = st === "used" ? "Deze uitnodiging is al gebruikt door een zaak." : st === "expired" ? "Deze uitnodiging is verlopen of de actie loopt niet meer." :
        st === "revoked" ? "De organisator heeft deze uitnodiging ingetrokken." : "Deze link klopt niet.";
      return box("<h1>Uitnodiging niet meer geldig</h1><p>" + why + " Vraag de organisator om een nieuwe link.</p>" +
        '<p class="zk-ci-actions"><a class="zk-btn ghost" href="/zakelijk/">Over Pasr voor ondernemers</a></p>');
    }
    communityToken(t);
    document.title = "Uitnodiging: " + p.title + " | Pasr Zakelijk";
    var intro = "<h1>Je bent uitgenodigd</h1><p>" + esc(p.initiator_name) + " nodigt je zaak uit voor een gezamenlijke klantenactie met Pasr. " +
      "Klanten sparen bij alle deelnemende zaken samen voor \u00e9\u00e9n beloning; er worden geen klantgegevens tussen zaken gedeeld.</p>" + communityCard(p);
    async function accept(bizId, btn) {
      try {
        await rpc("pasr_business_community_accept_token", { p_business: bizId, p_token: t }, true);
        communityToken(null);
        box("<h1>Je doet mee</h1><p>Je zaak doet nu mee aan \u201c" + esc(p.title) + "\u201d. Zodra genoeg zaken meedoen, start de actie en zien klanten hem in Pasr. Je krijgt dan een mail en een melding.</p>" +
          '<p class="zk-ci-actions"><a class="zk-btn" href="/zakelijk/dashboard/#gezamenlijke-acties">Naar Gezamenlijke acties</a></p>');
      } catch (e) {
        if (e.status === 401) { session = null; saveSession(null); navState(); return show(); }
        if (/invite_(expired|not_found)/.test(String(e.message || ""))) communityToken(null);
        setMsg($("#zkCiMsg"), nice(e));
        if (btn) btn.disabled = false;
      }
    }
    async function show() {
      if (!session || !(await token())) {
        dash.afterLogin = show;
        box(intro + '<p class="zk-ci-actions"><button class="zk-btn" type="button" id="ciLogin">Inloggen en accepteren</button>' +
          '<a class="zk-btn ghost" href="/zakelijk/dashboard/#account">Gratis aanmelden</a></p>' +
          '<p class="zk-ci-note">Nog geen zaak in Pasr? Meld je gratis aan. Na de goedkeuring van je zaak staat de uitnodiging in deze browser klaar in je dashboard.</p>');
        $("#ciLogin").addEventListener("click", function () { location.hash = "inloggen"; loginView("login"); });
        return;
      }
      var me = null;
      try { me = await rpc("pasr_business_me", {}, true); } catch (e) { /* hieronder: geen zaak */ }
      var own = ((me && me.businesses) || []).filter(function (x) { return x.role === "owner"; });
      var ok = own.filter(function (x) { return x.status === "approved"; });
      if (!own.length) {
        return box(intro + "<p>Je hebt nog geen zaak in Pasr. Meld je zaak gratis aan; na de goedkeuring (meestal binnen een werkdag) staat de uitnodiging klaar in je dashboard.</p>" +
          '<p class="zk-ci-actions"><a class="zk-btn" href="/zakelijk/dashboard/">Zaak aanmelden</a></p>');
      }
      if (!ok.length) {
        return box(intro + "<p>Je zaak wacht nog op goedkeuring. Zodra Pasr je zaak heeft goedgekeurd, accepteer je de uitnodiging in je dashboard.</p>" +
          '<p class="zk-ci-actions"><a class="zk-btn" href="/zakelijk/dashboard/">Naar je dashboard</a></p>');
      }
      box(intro + (ok.length > 1 ? '<label class="zk-ci-pick" for="ciBiz">Meedoen met</label><select id="ciBiz">' +
          ok.map(function (x) { return '<option value="' + esc(x.id) + '">' + esc(x.name) + (x.city ? " \u00b7 " + esc(x.city) : "") + "</option>"; }).join("") + "</select>" : "") +
        '<p class="zk-ci-actions"><button class="zk-btn" type="button" id="ciYes">Accepteren' + (ok.length === 1 ? " met " + esc(ok[0].name) : "") + "</button>" +
        '<a class="zk-btn ghost" href="/zakelijk/dashboard/#gezamenlijke-acties">Later beslissen</a></p><p class="zk-msg" id="zkCiMsg" role="status" aria-live="polite"></p>');
      $("#ciYes").addEventListener("click", function (ev) {
        var btn = ev.currentTarget, pick = $("#ciBiz");
        btn.disabled = true;
        accept(pick ? pick.value : ok[0].id, btn);
      });
    }
    window.addEventListener("hashchange", function () {
      var h = location.hash.replace("#", "");
      if (h === "account") loginView("signup"); else if (h === "vergeten") loginView("forgot"); else if (h === "inloggen") loginView("login");
    });
    show();
  }

  // ---------------------------------------------------------------- uitnodiging medewerker: pasr.nl/zakelijk/uitnodiging/#<code>
  async function invitePage() {
    var ct = new URLSearchParams(location.search).get("t");
    if (ct && /^[0-9a-f]{64}$/i.test(ct)) return communityInvitePage(ct.toLowerCase());
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
