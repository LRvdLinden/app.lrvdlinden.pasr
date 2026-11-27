/* Aanmelden voor een gratis event: https://pasr.nl/add/e/<event-id> (en /aanmelden/#<event-id>). Gemaakt door
   tools/make_add.py. Haalt het event op met pasr_event_public (openbaar, zonder persoonsgegevens) en meldt aan met
   pasr_event_register. Voornaam, achternaam, e-mail en geboortedatum zijn verplicht en gaan alleen naar de organisator.
   Daarna: bevestiging met de knop "Voeg toe aan Pasr" (add-link van het ticket) en "Open in Pasr".
   Anti-bot (zoals pasr.nl/account): verborgen veld "website" en de invultijd. Ingevuld of sneller dan MIN_MS: we tonen
   de bevestiging, maar sturen niets naar de server. De invultijd gaat mee als p_fill_ms (server: 20261127-antibot-forms.sql). */
(function () {
  "use strict";
  var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  var $ = function (id) { return document.getElementById(id); };
  var TZ = "Europe/Amsterdam";
  var MIN_MS = 3000;   // vier velden invullen kan een mens niet sneller
  var HP = '<div class="hp-field" aria-hidden="true"><label>Laat dit veld leeg<input type="text" name="website" tabindex="-1" autocomplete="off"></label></div>';
  var ICON = {
    cal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
    pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.4"/></svg>',
    clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>',
    lock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3"/></svg>',
    users: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5M16 4.8a3.5 3.5 0 0 1 0 6.4M18.5 14.8c1.6.9 2.6 2.6 3 5.2"/></svg>'
  };

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function hex(c, fb) { return /^#[0-9A-Fa-f]{6}$/.test(c || "") ? c : fb; }
  function light(c) { var r = parseInt(c.substr(1, 2), 16), g = parseInt(c.substr(3, 2), 16), b = parseInt(c.substr(5, 2), 16); return 0.2126 * r + 0.7152 * g + 0.0722 * b > 160; }
  function logoSrc(v) {
    if (!v || typeof v !== "string") return null;
    if (/^(\/9j\/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$/.test(v) && v.length < 400000) return "data:image/" + (v.indexOf("/9j/") === 0 ? "jpeg" : "png") + ";base64," + v;
    return null;
  }
  function fmt(iso, o) { if (!iso) return ""; var d = new Date(iso); if (isNaN(d)) return ""; o.timeZone = TZ; return new Intl.DateTimeFormat("nl-NL", o).format(d); }
  function day(iso) { return fmt(iso, { weekday: "long", day: "numeric", month: "long", year: "numeric" }); }
  function dayShort(iso) { return fmt(iso, { weekday: "short", day: "numeric", month: "short" }); }
  function time(iso) { return fmt(iso, { hour: "2-digit", minute: "2-digit" }); }
  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

  // datum (jjjj-mm-dd) in de tijdzone van de bezoeker, n dagen vanaf vandaag
  function localDay(n) { var d = new Date(); d.setDate(d.getDate() + (n || 0)); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
  var BIRTH_MIN = "1900-01-01";

  // Nieuwe parameters (p_fill_ms) eerst; kent de server ze nog niet (PGRST202, website eerder online dan de backend),
  // dan dezelfde aanroep zonder.
  function rpcCompat(name, body, extra) {
    var all = {}; Object.keys(body).forEach(function (k) { all[k] = body[k]; }); Object.keys(extra).forEach(function (k) { all[k] = extra[k]; });
    return rpc(name, all).catch(function (x) { if (x && x.code === "PGRST202") return rpc(name, body); throw x; });
  }

  function rpc(name, body) {
    var cfg = window.PASR_ACCOUNT || {};
    if (!cfg.url || !cfg.key) return Promise.reject(new Error("offline"));
    return fetch(cfg.url.replace(/\/$/, "") + "/rest/v1/rpc/" + name, {
      method: "POST", headers: { apikey: cfg.key, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(body || {}), credentials: "omit"
    }).then(function (r) {
      return r.text().then(function (t) {
        var j = null; try { j = t ? JSON.parse(t) : null; } catch (e) { j = null; }
        if (!r.ok) { var err = new Error((j && (j.hint || j.message)) || ("http " + r.status)); err.status = r.status; err.code = j && j.code; throw err; }
        return j;
      });
    });
  }

  function eventId() {
    var m = location.pathname.match(/^\/add\/e\/([^/?#]+)\/?$/);
    var id = m ? m[1] : decodeURIComponent(location.hash.replace(/^#\/?/, "")) || new URLSearchParams(location.search).get("id") || "";
    id = id.replace(/^e\//, "").toLowerCase();
    return UUID.test(id) ? id : null;
  }

  var ev = null, id = eventId();
  var ERR = {
    event_full: "Helaas, het event is vol.",
    signup_closed: "Aanmelden is gesloten.",
    too_many: "Met dit e-mailadres kun je niet meer tickets aanmelden. Er geldt een maximum per persoon.",
    invalid_input: "Controleer je gegevens: alle velden zijn verplicht en je geboortedatum ligt in het verleden.",
    event_cancelled: "Dit event gaat niet door.",
    event_not_found: "Dit event bestaat niet (meer).",
    rate_limited: "Even rustig aan: probeer het over een paar minuten opnieuw."
  };

  function header(e) {
    var color = hex(e.color, "#6A5CFF"), head = $("ev-head");
    head.style.setProperty("--ev", color);
    head.style.setProperty("--evt", light(color) ? "#17162A" : "#FFFFFF");
    if (/^https:\/\//.test(e.header_url || "")) { head.style.setProperty("--evimg", 'url("' + e.header_url.replace(/["\\]/g, "") + '")'); head.classList.add("has-img"); }
    var logo = logoSrc(e.business_logo);
    $("ev-biz").innerHTML = '<span class="ev-bizlogo" aria-hidden="true">' + (logo ? '<img alt="" src="' + esc(logo) + '">' : esc(String(e.business_name || "?").charAt(0).toUpperCase())) + "</span><span>" + esc(e.business_name) + (e.business_city ? " · " + esc(e.business_city) : "") + "</span>";
    $("ev-title").textContent = e.name;
    var when = [cap(dayShort(e.starts_at)), time(e.starts_at) + (e.ends_at ? "–" + time(e.ends_at) : ""), e.address].filter(Boolean).join(" · ");
    $("ev-when").textContent = when;
    document.title = "Aanmelden: " + e.name + " | Pasr";
  }

  function info(e) {
    var rows = [
      [ICON.cal, "Datum", cap(day(e.starts_at))],
      [ICON.clock, "Tijd", time(e.starts_at) + (e.ends_at ? " – " + time(e.ends_at) : "") + (e.doors_at ? " · deuren open " + time(e.doors_at) : "")],
    ];
    if (e.address) rows.push([ICON.pin, "Locatie", '<a href="https://maps.apple.com/?q=' + encodeURIComponent(e.address) + '" rel="noopener">' + esc(e.address) + "</a>", true]);
    var spots = Number(e.spots_left || 0);
    rows.push([ICON.users, "Plekken", e.status === "cancelled" ? "Afgelast" : spots > 0 ? (spots <= 25 ? "Nog " + spots + " " + (spots === 1 ? "plek" : "plekken") + " vrij" : "Plek genoeg") : (e.waitlist ? "Vol · wachtlijst open" : "Vol")]);
    $("ev-info").innerHTML = (e.description ? '<p class="ev-desc">' + esc(e.description) + "</p>" : "") +
      '<dl class="ev-facts">' + rows.map(function (r) { return "<div><dt>" + r[0] + "<span>" + r[1] + "</span></dt><dd>" + (r[3] ? r[2] : esc(r[2])) + "</dd></div>"; }).join("") + "</dl>" +
      '<p class="ev-free">Gratis · alleen aanmelden</p>';
  }

  function closed(e, title, text) {
    $("ev-box").innerHTML = '<div class="ev-card ev-closed"><h2>' + esc(title) + "</h2><p>" + esc(text) + "</p></div>";
  }

  function form(e) {
    if (e.status === "cancelled") return closed(e, "Dit event gaat niet door", e.cancel_message ? "Bericht van " + e.business_name + ": “" + e.cancel_message + "”" : e.business_name + " heeft het event afgelast.");
    if (!e.signup_open) return closed(e, "Aanmelden is gesloten", "Je kunt je niet meer aanmelden voor dit event.");
    var types = (e.ticket_types || []).filter(function (t) { return t && t.id; });
    var full = Number(e.spots_left || 0) <= 0;
    if (full && !e.waitlist) return closed(e, "Het event is vol", "Alle plekken zijn vergeven en er is geen wachtlijst.");
    var max = Math.max(1, Math.min(20, Number(e.max_per_person) || 4));
    var color = hex(e.color, "#6A5CFF");
    var typeHtml = types.length > 1
      ? '<fieldset class="ev-types"><legend>Ticketsoort</legend>' + types.map(function (t, i) {
          var none = Number(t.available) <= 0;
          return '<label class="ev-type"><input type="radio" name="type" value="' + esc(t.id) + '"' + (i === 0 ? " checked" : "") + '><span><b>' + esc(t.name) + "</b><small>" + (none ? (e.waitlist ? "vol · wachtlijst" : "vol") : t.available <= 25 ? "nog " + t.available + " vrij" : "gratis") + "</small></span></label>";
        }).join("") + "</fieldset>"
      : '<input type="hidden" name="type" value="' + esc(types[0] ? types[0].id : "") + '">';
    $("ev-box").innerHTML = '<form class="ev-card ev-form" id="ev-form" novalidate style="--ev:' + color + ";--evt:" + (light(color) ? "#17162A" : "#FFFFFF") + '">' +
      "<h2>" + (full ? "Op de wachtlijst" : "Gratis aanmelden") + "</h2>" +
      (full ? '<p class="ev-note">Het event is vol. Meld je aan voor de wachtlijst: komt er een plek vrij, dan krijg je meteen je ticket per mail.</p>' : "") +
      '<div class="ev-row2"><label>Voornaam<input name="first" autocomplete="given-name" required maxlength="60"></label>' +
      '<label>Achternaam<input name="last" autocomplete="family-name" required maxlength="60"></label></div>' +
      '<label>E-mailadres<input name="email" type="email" autocomplete="email" inputmode="email" required maxlength="200"></label>' +
      '<label>Geboortedatum<span class="ev-date is-empty" data-ph="dd-mm-jjjj"><input name="birth" type="date" autocomplete="bday" required value="" placeholder="dd-mm-jjjj" min="' + BIRTH_MIN + '" max="' + localDay(-1) + '" aria-describedby="ev-birth-help"></span>' +
      '<small class="ev-help" id="ev-birth-help">Dag, maand en jaar, bijvoorbeeld 14-03-1991</small></label>' +
      typeHtml +
      '<div class="ev-count"><span id="ev-count-l">Aantal tickets</span><span class="ev-stepper" role="group" aria-labelledby="ev-count-l">' +
      '<button type="button" data-step="-1" aria-label="Eén ticket minder">−</button><output id="ev-n" aria-live="polite">1</output>' +
      '<button type="button" data-step="1" aria-label="Eén ticket meer">+</button></span><small>hoogstens ' + max + " per persoon</small></div>" +
      '<p class="ev-privacy">' + ICON.lock + "<span>Je gegevens gaan alleen naar " + esc(e.business_name) + " voor dit event. Op het ticket staat alleen je naam; de QR-code bevat geen persoonsgegevens. Na het event worden ze gewist.</span></p>" +
      HP + '<p class="ev-err" id="ev-err" role="alert" hidden></p>' +
      '<button class="ev-submit" type="submit" id="ev-submit">' + (full ? "Op de wachtlijst" : "Gratis aanmelden") + "</button></form>";
    var n = 1, out = $("ev-n"), shown = Date.now();
    // lege datum: eigen tekst dd-mm-jjjj op telefoons (iOS toont anders de datum van vandaag in een leeg veld)
    var bf = $("ev-form").birth, wrap = bf.parentNode;
    if (window.matchMedia && matchMedia("(pointer: coarse)").matches) wrap.classList.add("ev-date-ph");
    var sync = function () { wrap.classList.toggle("is-empty", !bf.value); };
    bf.value = ""; sync(); bf.addEventListener("input", sync); bf.addEventListener("change", sync); bf.addEventListener("blur", sync);
    $("ev-box").querySelectorAll("[data-step]").forEach(function (b) {
      b.addEventListener("click", function () { n = Math.max(1, Math.min(max, n + Number(b.dataset.step))); out.textContent = n; });
    });
    $("ev-form").addEventListener("submit", function (ev2) {
      ev2.preventDefault();
      var f = ev2.target, err = $("ev-err"), btn = $("ev-submit");
      var first = f.first.value.trim(), last = f.last.value.trim(), email = f.email.value.trim(), birth = f.birth.value;
      var typeEl = f.querySelector('[name="type"]:checked') || f.querySelector('[name="type"]');
      // geboortedatum: echte datum, niet vandaag of later, niet voor 1900
      var birthOk = /^\d{4}-\d{2}-\d{2}$/.test(birth) && birth >= BIRTH_MIN && birth < localDay(0) && !isNaN(new Date(birth + "T12:00:00Z"));
      var bad = !first ? f.first : !last ? f.last : !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ? f.email : !birthOk ? f.birth : null;
      f.querySelectorAll("[aria-invalid]").forEach(function (x) { x.removeAttribute("aria-invalid"); });
      if (bad) {
        bad.setAttribute("aria-invalid", "true"); bad.focus(); err.hidden = false;
        err.textContent = bad === f.birth ? (birth && birth >= localDay(0) ? "Je geboortedatum moet in het verleden liggen: vandaag of later kan niet." : "Vul je geboortedatum in (dd-mm-jjjj).") : ERR.invalid_input;
        return;
      }
      err.hidden = true; btn.disabled = true; btn.textContent = "Bezig…";
      var fill = Date.now() - shown;
      if (f.website.value || fill < MIN_MS) {   // bot: doe alsof, stuur niets
        return setTimeout(function () { done(e, { status: full ? "waitlist" : "registered", tickets: [] }, email, first); }, 600);
      }
      rpcCompat("pasr_event_register", { p_event: e.id, p_first_name: first, p_last_name: last, p_email: email, p_birth_date: birth,
        p_ticket_type: typeEl && typeEl.value ? typeEl.value : null, p_count: n }, { p_fill_ms: Math.min(fill, 2147483647) })
        .then(function (r) { done(e, r, email, first); })
        .catch(function (x) {
          btn.disabled = false; btn.textContent = full ? "Op de wachtlijst" : "Gratis aanmelden";
          err.hidden = false;
          var code = String(x && x.message || "");
          err.textContent = ERR[code] || (code === "offline" ? "Aanmelden kan nu niet. Probeer het later nog eens." : "Er ging iets mis. Probeer het nog eens.");
          if (code === "too_many") err.textContent = "Met dit e-mailadres kun je hoogstens " + max + " tickets aanmelden.";
        });
    });
  }

  function ics(e) {
    var stamp = function (iso) { return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, ""); };
    var line = function (s) { return String(s || "").replace(/[\\,;]/g, function (c) { return "\\" + c; }).replace(/\n/g, "\\n"); };
    var body = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Pasr//Event//NL", "BEGIN:VEVENT", "UID:" + e.id + "@pasr.nl",
      "DTSTAMP:" + stamp(new Date().toISOString()), "DTSTART:" + stamp(e.starts_at), "DTEND:" + stamp(e.ends_at || e.starts_at),
      "SUMMARY:" + line(e.name), "LOCATION:" + line(e.address), "DESCRIPTION:" + line("Je ticket staat in Pasr en in je mail."),
      "URL:https://pasr.nl/add/e/" + e.id, "END:VEVENT", "END:VCALENDAR"].join("\r\n");
    return "data:text/calendar;charset=utf-8," + encodeURIComponent(body);
  }

  function done(e, r, email, first) {
    var list = (r && r.tickets) || [], wait = r && r.status === "waitlist", link = r && r.add_link;
    var tid = list[0] && list[0].ticket_id, code = list[0] && list[0].code;
    var open = tid ? "pasr://add/t/" + encodeURIComponent(tid) + "?c=" + encodeURIComponent(code) : "pasr://";
    var color = hex(e.color, "#6A5CFF");
    var qr = "";
    if (!wait && code && window.qrcode) {
      try { var q = window.qrcode(0, "M"); q.addData(code); q.make(); qr = q.createSvgTag({ cellSize: 4, margin: 2, scalable: true }); } catch (x) { qr = ""; }
    }
    $("ev-box").innerHTML = '<div class="ev-card ev-done" tabindex="-1" id="ev-done">' +
      '<span class="ev-ok' + (wait ? " wait" : "") + '">' + (wait ? ICON.clock : ICON.check) + "</span>" +
      "<h2>" + (wait ? "Je staat op de wachtlijst" : "Je bent aangemeld") + "</h2>" +
      "<p>" + (wait
        ? (list.length > 1 ? list.length + " plekken" : "Je plek") + " op de wachtlijst voor " + esc(e.name) + ". Komt er een plek vrij, dan mailen we je ticket naar " + esc(email) + "."
        : (list.length > 1 ? list.length + " tickets" : "Je ticket") + " voor " + esc(e.name) + ". We hebben " + (list.length > 1 ? "ze" : "hem") + " ook naar " + esc(email) + " gemaild.") + "</p>" +
      '<div class="ev-mini" style="--ev:' + color + ";--evt:" + (light(color) ? "#17162A" : "#FFFFFF") + '"><div><small>' + esc(e.business_name) + "</small><b>" + esc(e.name) + "</b><span>" +
      esc(cap(dayShort(e.starts_at)) + " · " + time(e.starts_at)) + (list.length > 1 ? " · " + list.length + "×" : "") + "</span>" + (first ? "<em>" + esc(first) + "</em>" : "") + "</div>" +
      (qr ? '<span class="ev-qr" role="img" aria-label="QR-code van je ticket">' + qr + "</span>" : "") + "</div>" +
      (link ? '<p class="ev-badge"><a class="pasr-add-badge" href="' + esc(link) + '"><picture><source srcset="/badge/nl/wit.svg" media="(prefers-color-scheme: dark)">' +
        '<img src="/badge/nl/zwart.svg" alt="Voeg toe aan Pasr" width="150" height="52"></picture></a></p>' : "") +
      '<p class="ev-actions"><a class="btn btn-primary" href="' + esc(open) + '">Open in Pasr</a>' +
      '<a class="btn btn-ghost" download="' + esc(e.name.replace(/[^\w\- ]+/g, "").slice(0, 40) || "event") + '.ics" href="' + ics(e) + '">' + ICON.cal + "Zet in je agenda</a></p>" +
      '<p class="ta-small">Met Pasr heb je je ticket offline bij de hand, met een herinnering de dag ervoor. Nog geen Pasr? Download hem hieronder en tik daarna op <i>Voeg toe aan Pasr</i>.</p></div>';
    var d = $("ev-done"); if (d) { d.focus({ preventScroll: true }); d.scrollIntoView({ behavior: "smooth", block: "start" }); }
  }

  if (!id) {
    $("ev-title").textContent = "Geen event in deze link";
    $("ev-biz").textContent = "Pasr";
    $("ev-info").innerHTML = "";
    return closed(null, "Link onvolledig", "Open de link uit de mail, van de website of de QR-code van de organisator opnieuw.");
  }
  rpc("pasr_event_public", { p_event: id }).then(function (e) {
    if (!e || !e.id) {
      $("ev-title").textContent = "Event niet gevonden";
      $("ev-biz").textContent = "Pasr";
      $("ev-info").innerHTML = "";
      return closed(null, "Dit event is niet (meer) online", "Vraag de organisator om een nieuwe link.");
    }
    ev = e; header(e); info(e); form(e);
  }).catch(function () {
    $("ev-title").textContent = "Aanmelden kan nu niet";
    $("ev-biz").textContent = "Pasr";
    $("ev-info").innerHTML = "";
    closed(null, "Even geen verbinding", "We konden het event nu niet ophalen. Probeer het zo nog eens.");
  });
})();
