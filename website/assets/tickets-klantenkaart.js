/* Pasr Zakelijk-dashboard: Tickets (gratis events met aanmelding) en Klantenkaarten (eigen klantenkaart met barcode).
   Onder Klantenbinding, naast de stempelkaarten. Alles via de RPC's uit docs/tickets-klantenkaart.md; de tabellen zelf
   zijn dicht. zakelijk.js roept window.PasrTK.tickets(panel, zaak, h) en .cards(panel, zaak, h) aan; h bevat de hulpjes
   van het dashboard (rpc, esc, ICON, toast, modal, panelTitle, go, refresh, state). Persoonsgegevens (naam, e-mail,
   geboortedatum) ziet alleen de eigenaar, in de lijst met aanmeldingen en de CSV-export. */
(function () {
  "use strict";
  var TZ = "Europe/Amsterdam";
  var COLORS = ["#6A5CFF", "#1F3A5F", "#17162A", "#E2683C", "#8A4B1F", "#12A77E", "#0A84FF", "#C2361F", "#AF52DE", "#F2B705"];
  var DAYS = ["ma", "di", "wo", "do", "vr", "za", "zo"];
  var TKICON = {
    ticket: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7.5A1.5 1.5 0 0 1 5.5 6h13A1.5 1.5 0 0 1 20 7.5V10a2 2 0 0 0 0 4v2.5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 16.5V14a2 2 0 0 0 0-4z"/><path d="M14.5 6.5v11" stroke-dasharray="2 2.2"/></svg>',
    mcard: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M7 15h1M10 15h1M13 15h1M7 10h6"/></svg>',
    pct: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M19 5 5 19"/><circle cx="7" cy="7" r="2.2"/><circle cx="17" cy="17" r="2.2"/></svg>',
    star: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8L3.5 9.7l5.9-.9z"/></svg>',
    idcard: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2.5"/><circle cx="9" cy="11" r="2"/><path d="M6 16c.6-1.4 1.7-2 3-2s2.4.6 3 2M15 10h3M15 13h3"/></svg>',
    csv: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 4v11M7 10.5l5 5 5-5M4 20h16"/></svg>',
    x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg>'
  };

  // ---------------------------------------------------------------- tijd (Nederlandse tijd, ook als de browser elders staat)
  function parts(iso) {
    var d = new Date(iso); if (isNaN(d)) return null;
    var p = {}; new Intl.DateTimeFormat("en-GB", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .formatToParts(d).forEach(function (x) { p[x.type] = x.value; });
    return { date: p.year + "-" + p.month + "-" + p.day, time: p.hour + ":" + p.minute };
  }
  function offset(y, mo, d) {
    function lastSunday(m) { var l = new Date(Date.UTC(y, m, 0)); return l.getUTCDate() - l.getUTCDay(); }
    var summer = (mo > 3 && mo < 10) || (mo === 3 && d >= lastSunday(3)) || (mo === 10 && d < lastSunday(10));
    return summer ? "+02:00" : "+01:00";
  }
  /** "2026-12-19" + "16:00" (Nederlandse tijd) -> ISO met offset */
  function nlIso(date, time) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date || "") || !/^\d{2}:\d{2}$/.test(time || "")) return null;
    var a = date.split("-").map(Number);
    return date + "T" + time + ":00" + offset(a[0], a[1], a[2]);
  }
  function addDay(date) { var d = new Date(date + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + 1); return d.toISOString().slice(0, 10); }
  function fmt(iso, o) { if (!iso) return ""; var d = new Date(iso); if (isNaN(d)) return ""; o.timeZone = TZ; return new Intl.DateTimeFormat("nl-NL", o).format(d); }
  function dShort(iso) { return fmt(iso, { weekday: "short", day: "numeric", month: "short" }); }
  function dLong(iso) { return fmt(iso, { weekday: "long", day: "numeric", month: "long", year: "numeric" }); }
  function hm(iso) { return fmt(iso, { hour: "2-digit", minute: "2-digit" }); }
  function dmy(date) { return date ? fmt(date + "T12:00:00Z", { day: "numeric", month: "short" }) : ""; }
  function today() { return parts(new Date().toISOString()).date; }

  // ---------------------------------------------------------------- algemeen
  function hex(c, fb) { return /^#[0-9A-Fa-f]{6}$/.test(c || "") ? c.toUpperCase() : fb; }
  function textOn(c) { var v = parseInt(c.slice(1), 16), r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255; return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.62 ? "#17162A" : "#FFFFFF"; }
  function bizColor(b) { var c = (b.cards || [])[0]; return hex(c && c.color, "#6A5CFF"); }
  function bizLogo(b) { var c = (b.cards || []).filter(function (x) { return x.logo; })[0]; return c ? c.logo : null; }
  function imgSrc(b64) { return b64 ? "data:image/" + (b64.indexOf("/9j/") === 0 ? "jpeg" : "png") + ";base64," + b64 : ""; }
  var ERR = {
    not_owner: "Alleen de eigenaar van de zaak kan dit.", event_not_found: "Dit event bestaat niet (meer).", invalid_input: "Controleer de velden: iets ontbreekt of klopt niet.",
    event_cancelled: "Dit event is afgelast en kan niet meer worden gewijzigd.", business_not_approved: "Online zetten kan pas als je zaak is goedgekeurd.",
    card_not_found: "Deze klantenkaart bestaat niet (meer).", barcode_type_locked: "Het soort barcode ligt vast zodra er leden zijn.",
    not_enough: "Nog niet genoeg gespaard voor de beloning.", invalid_code: "Deze code is niet (meer) geldig."
  };
  function err(e, h) { var k = String((e && (e.hint || e.message)) || ""); return ERR[k] || h.nice(e); }
  function pct(v) { var n = Number(v); return isFinite(n) && n > 0 ? n.toLocaleString("nl-NL", { maximumFractionDigits: 2 }) + "%" : ""; }
  function plural(n, a, b) { return n + " " + (n === 1 ? a : b); }

  // ---------------------------------------------------------------- live ticketvoorbeeld (zoals in Pasr en Wallet)
  function qrFake(esc) {
    // voorbeeld-QR (geen echte code): vaste puntjes, zodat niemand denkt dat dit een geldig ticket is
    if (window.qrcode) { try { var q = window.qrcode(0, "M"); q.addData("PASR-VOORBEELD-TICKET"); q.make(); return q.createSvgTag({ cellSize: 4, margin: 0, scalable: true }); } catch (e) { /* niets */ } }
    return "";
  }
  function ticketPreview(s, b, esc) {
    var color = hex(s.color, bizColor(b)), t = textOn(color), logo = bizLogo(b);
    var start = s.date && s.start ? nlIso(s.date, s.start) : null;
    return '<div class="tk-ticket" style="--tc:' + color + ";--tt:" + t + '">' +
      '<div class="tk-ticket-top"><span class="tk-logo">' + (logo ? '<img alt="" src="' + imgSrc(logo) + '">' : esc(String(b.name || "?").charAt(0))) + "</span>" +
      '<span class="tk-tbiz"><small>' + esc(b.name) + "</small><b>" + esc(s.name || "Naam van je event") + '</b></span><em>Gratis ticket</em></div>' +
      '<dl class="tk-tfields"><div><dt>Datum</dt><dd>' + esc(start ? dShort(start) : "—") + "</dd></div><div><dt>Tijd</dt><dd>" + esc((s.start || "—") + (s.end ? "–" + s.end : "")) + "</dd></div>" +
      "<div><dt>Deuren</dt><dd>" + esc(s.doors || "—") + "</dd></div><div><dt>Naam</dt><dd>Anna de Vries</dd></div><div><dt>Soort</dt><dd>" + esc((s.types[0] && s.types[0].name) || "Toegang") + "</dd></div>" +
      '<div class="wide"><dt>Locatie</dt><dd>' + esc(s.address || "—") + "</dd></div></dl>" +
      '<div class="tk-tqr"><span>' + qrFake(esc) + "</span><small>VOORBEELD</small></div>" +
      '<div class="tk-tfoot"><span>1 van 2</span><span class="tk-dots"><i></i><i></i></span></div></div>';
  }

  // ================================================================= TICKETS
  function tickets(panel, b, h) {
    var st = h.state;
    if (st.sub === "tk-edit") return eventEdit(panel, b, h);
    if (st.sub === "tk-event" && st.tkEvent) return eventDetail(panel, b, h);
    var esc = h.esc;
    panel.innerHTML = h.panelTitle("Tickets", "Gratis events met aanmelding. Klanten melden zich aan op pasr.nl of in Pasr en krijgen een ticket met QR-code; jij scant ze aan de deur.",
      '<button class="zk-btn" type="button" id="tkNew">' + h.ICON.plus + "Nieuw event</button>") + '<div id="tkList"><p class="zd3-muted">Laden…</p></div>';
    $("#tkNew", panel).addEventListener("click", function () { st.sub = "tk-edit"; st.tkEvent = null; h.render(); });
    h.rpc("pasr_business_events", { p_business: b.id }, true).then(function (rows) {
      rows = Array.isArray(rows) ? rows : [];
      var box = $("#tkList", panel); if (!box) return;
      if (!rows.length) {
        box.innerHTML = '<div class="zk-panel zd-first tk-first"><div class="zd-first-card">' + ticketPreview({ name: "Winterborrel", date: addDay(today()), start: "16:00", end: "19:00", doors: "15:45", address: b.city || "Hoofdstraat 1", types: [{ name: "Toegang" }] }, b, esc) +
          "</div><div><h3>Je eerste event</h3><p>Een borrel, proeverij of workshop: kies datum, tijd, adres en het aantal plekken. Klanten melden zich gratis aan met naam, e-mail en geboortedatum; die gegevens zie alleen jij. " +
          "Is het vol, dan komen ze op de wachtlijst en schuiven ze vanzelf door.</p>" + '<button class="zk-btn" id="tkFirst" type="button">' + h.ICON.plus + "Event maken</button></div></div>";
        $("#tkFirst", box).addEventListener("click", function () { st.sub = "tk-edit"; st.tkEvent = null; h.render(); });
        return;
      }
      var now = Date.now();
      box.innerHTML = '<ul class="tk-events">' + rows.map(function (e, i) {
        var past = Date.parse(e.ends_at) < now, s = eventState(e, now);
        var reg = Number(e.registered || 0), cap = Math.max(1, Number(e.capacity || 1)), inn = Number(e.checked_in || 0);
        return '<li class="tk-ev' + (past ? " past" : "") + '"><button type="button" class="tk-evbtn" data-i="' + i + '">' +
          '<span class="tk-date" style="--tc:' + esc(hex(e.color, "#6A5CFF")) + '"><b>' + esc(fmt(e.starts_at, { day: "numeric" })) + "</b><small>" + esc(fmt(e.starts_at, { month: "short" }).replace(".", "")) + "</small></span>" +
          '<span class="tk-evt"><b>' + esc(e.name) + "</b><small>" + esc(hm(e.starts_at) + " · " + (e.address || "geen adres")) + "</small>" +
          '<span class="tk-bar" aria-hidden="true"><i class="in" style="width:' + Math.min(100, inn / cap * 100) + '%"></i><i class="reg" style="width:' + Math.min(100, Math.max(0, reg - inn) / cap * 100) + '%"></i></span></span>' +
          '<span class="tk-evn"><b>' + reg + " / " + cap + "</b><small>" + (e.waitlist ? plural(Number(e.waitlist), "wachtende", "wachtenden") : inn ? inn + " binnen" : "aangemeld") + "</small></span>" +
          '<span class="zk-pill ' + s[1] + '">' + esc(s[0]) + "</span>" + h.ICON.chevron + "</button></li>";
      }).join("") + "</ul>";
      box.querySelectorAll("[data-i]").forEach(function (btn) {
        btn.addEventListener("click", function () { st.sub = "tk-event"; st.tkEvent = rows[Number(btn.dataset.i)]; h.render(); });
      });
    }).catch(function (e) { var box = $("#tkList", panel); if (box) box.innerHTML = '<p class="zk-empty">' + esc(err(e, h)) + "</p>"; });
  }
  function eventState(e, now) {
    now = now || Date.now();
    if (e.status === "cancelled") return ["Afgelast", ""];
    if (e.status === "draft") return ["Concept", "wait"];
    if (Date.parse(e.ends_at) < now) return ["Afgelopen", ""];
    if (Date.parse(e.starts_at) <= now) return ["Bezig", "on"];
    return ["Online", "on"];
  }

  function eventEdit(panel, b, h) {
    var esc = h.esc, st = h.state, e = st.tkEvent;
    var sp = e ? parts(e.starts_at) : null, ep = e ? parts(e.ends_at) : null, dp = e && e.doors_at ? parts(e.doors_at) : null, up = e && e.signup_until ? parts(e.signup_until) : null;
    var s = {
      name: e ? e.name : "", description: e ? e.description || "" : "", date: sp ? sp.date : addDay(today()), start: sp ? sp.time : "19:00", end: ep ? ep.time : "21:00",
      doors: dp ? dp.time : "", address: e ? e.address || "" : "", capacity: e ? e.capacity : 50, max: e ? e.max_per_person || 4 : 4,
      until: up ? up.date + "T" + up.time : "", waitlist: e ? e.waitlist_enabled !== false : true, reminder: e ? e.reminder !== false : true,
      color: e ? e.color : bizColor(b), header: e ? e.header_url || "" : "",
      types: e && Array.isArray(e.ticket_types) && e.ticket_types.length ? e.ticket_types.map(function (t) { return { id: t.id, name: t.name, capacity: t.capacity }; }) : [{ name: "Toegang", capacity: null }]
    };
    var published = e && e.status === "published", approved = b.status === "approved";
    var colors = COLORS.indexOf(hex(s.color, "")) < 0 ? [hex(s.color, "#6A5CFF")].concat(COLORS) : COLORS;
    panel.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="tkBack">' + h.ICON.back + "Tickets</button></p>" +
      '<div class="tk-editor"><form class="zk-panel zk-form tk-form" id="tkForm" novalidate>' +
      '<div class="tk-formhead"><h2 id="zd-title">' + (e ? "Event bewerken" : "Nieuw event") + ' <span class="tk-free">Alleen gratis tickets</span></h2>' +
      '<div class="tk-formbtns"><button class="zk-btn ghost" type="submit" data-status="draft"' + (published ? " hidden" : "") + ">Concept bewaren</button>" +
      '<button class="zk-btn" type="submit" data-status="published"' + (approved ? "" : " disabled") + ">" + h.ICON.check + (published ? "Opslaan" : "Online zetten") + "</button></div></div>" +
      '<label>Naam van het event<input name="name" maxlength="80" required value="' + esc(s.name) + '" placeholder="bijv. Winterborrel"></label>' +
      '<label>Omschrijving<textarea name="description" rows="3" maxlength="2000" placeholder="Wat kunnen je klanten verwachten?">' + esc(s.description) + "</textarea></label>" +
      '<div class="tk-row4"><label>Datum<input name="date" type="date" required value="' + esc(s.date) + '"></label><label>Begint<input name="start" type="time" required value="' + esc(s.start) + '"></label>' +
      '<label>Eindigt<input name="end" type="time" required value="' + esc(s.end) + '"></label><label>Deuren open<input name="doors" type="time" value="' + esc(s.doors) + '"></label></div>' +
      '<label>Adres<input name="address" maxlength="200" autocomplete="street-address" value="' + esc(s.address) + '" placeholder="Straat 1, 1234 AB Plaats"></label>' +
      '<div class="tk-row3"><label>Aantal plekken<input name="capacity" type="number" min="1" max="100000" required value="' + esc(s.capacity) + '"></label>' +
      '<label>Max. per persoon<input name="max" type="number" min="1" max="20" value="' + esc(s.max) + '"></label>' +
      '<label>Aanmelden tot <span class="zd-opt">(leeg = tot de start)</span><input name="until" type="datetime-local" value="' + esc(s.until) + '"></label></div>' +
      '<div class="tk-row2"><label class="tk-switch"><span><b>Wachtlijst</b><small>Bij vol: aanmelden op de wachtlijst, automatisch doorschuiven</small></span><input type="checkbox" name="waitlist"' + (s.waitlist ? " checked" : "") + "></label>" +
      '<label class="tk-switch"><span><b>Herinnering</b><small>Push en mail de dag ervoor om 10:00</small></span><input type="checkbox" name="reminder"' + (s.reminder ? " checked" : "") + "></label></div>" +
      '<fieldset class="tk-types"><legend>Ticketsoorten <span class="zd-opt">(allemaal gratis)</span></legend><div id="tkTypes"></div>' +
      '<button type="button" class="zk-btn ghost sm" id="tkAddType">' + h.ICON.plus + "Soort toevoegen</button></fieldset>" +
      '<div class="tk-ask"><b>Bij aanmelden vragen we</b><span class="tk-chips">' + ["Voornaam", "Achternaam", "E-mailadres", "Geboortedatum"].map(function (x) { return '<span class="tk-chip">' + h.ICON.check + x + "</span>"; }).join("") +
      "</span><small>Verplicht · alleen zichtbaar voor jouw zaak. Op het ticket staat alleen de naam; de QR-code bevat geen persoonsgegevens.</small></div>" +
      '<fieldset class="tk-brand"><legend>Branding</legend><span class="tk-logochip"><span class="zd3-bizlogo sm" style="background:' + esc(bizColor(b)) + '">' + (bizLogo(b) ? '<img alt="" src="' + imgSrc(bizLogo(b)) + '">' : esc(String(b.name).charAt(0))) + "</span>Logo van je zaak · automatisch</span>" +
      '<span class="tk-swatches" role="radiogroup" aria-label="Kleur">' + colors.map(function (c) { return '<button type="button" role="radio" data-c="' + c + '" aria-checked="' + (hex(s.color, "") === c) + '" style="background:' + c + '" aria-label="Kleur ' + c + '"></button>'; }).join("") + "</span>" +
      '<label class="tk-header">Headerfoto <span class="zd-opt">(https-link, optioneel)</span><input name="header" type="url" maxlength="500" placeholder="https://…" value="' + esc(s.header) + '"></label></fieldset>' +
      '<p class="zk-msg" id="tkMsg" role="status" aria-live="polite"></p>' + (approved ? "" : '<p class="zd-help">Online zetten kan na goedkeuring van je zaak; als concept bewaren kan al.</p>') + "</form>" +
      '<aside class="tk-preview"><p class="tk-prevlabel">Live voorbeeld · zo ziet de klant hem</p><div id="tkPrev"></div><p class="zd-help">Ook in Apple Wallet en Google Wallet; tickets van hetzelfde event staan naast elkaar.</p></aside></div>';
    var f = $("#tkForm", panel);
    function drawTypes() {
      $("#tkTypes", panel).innerHTML = s.types.map(function (t, i) {
        return '<div class="tk-type"><input aria-label="Naam van ticketsoort ' + (i + 1) + '" data-tn="' + i + '" maxlength="40" value="' + esc(t.name) + '">' +
          '<input aria-label="Plekken voor ' + esc(t.name || "deze soort") + ' (leeg = geen eigen maximum)" data-tc="' + i + '" type="number" min="1" placeholder="plekken" value="' + esc(t.capacity || "") + '">' +
          (s.types.length > 1 ? '<button type="button" class="zk-btn ghost sm" data-tx="' + i + '" aria-label="Soort ' + esc(t.name) + ' verwijderen">' + TKICON.x + "</button>" : "") + "</div>";
      }).join("");
      $("#tkTypes", panel).querySelectorAll("[data-tn]").forEach(function (x) { x.addEventListener("input", function () { s.types[Number(x.dataset.tn)].name = x.value; draw(); }); });
      $("#tkTypes", panel).querySelectorAll("[data-tc]").forEach(function (x) { x.addEventListener("input", function () { s.types[Number(x.dataset.tc)].capacity = x.value ? Number(x.value) : null; }); });
      $("#tkTypes", panel).querySelectorAll("[data-tx]").forEach(function (x) { x.addEventListener("click", function () { s.types.splice(Number(x.dataset.tx), 1); drawTypes(); draw(); }); });
    }
    function draw() { $("#tkPrev", panel).innerHTML = ticketPreview(s, b, esc); }
    drawTypes(); draw();
    f.addEventListener("input", function (ev) {
      var n = ev.target.name; if (!n) return;
      s[n] = ev.target.type === "checkbox" ? ev.target.checked : ev.target.value; draw();
    });
    $("#tkAddType", panel).addEventListener("click", function () { if (s.types.length < 10) { s.types.push({ name: "", capacity: null }); drawTypes(); var l = panel.querySelectorAll("[data-tn]"); l[l.length - 1].focus(); } });
    panel.querySelectorAll(".tk-swatches button").forEach(function (btn) {
      btn.addEventListener("click", function () { s.color = btn.dataset.c; panel.querySelectorAll(".tk-swatches button").forEach(function (x) { x.setAttribute("aria-checked", String(x === btn)); }); draw(); });
    });
    $("#tkBack", panel).addEventListener("click", function () { st.sub = e ? "tk-event" : null; h.render(); });
    f.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var status = (ev.submitter && ev.submitter.dataset.status) || "draft", msg = $("#tkMsg", panel);
      var startIso = nlIso(s.date, s.start), endIso = nlIso(s.end > s.start ? s.date : addDay(s.date), s.end);
      var doorsIso = s.doors ? nlIso(s.doors <= s.start ? s.date : s.date, s.doors) : null;
      var untilIso = s.until ? nlIso(s.until.slice(0, 10), s.until.slice(11, 16)) : null;
      var bad = !s.name.trim() || s.name.trim().length < 2 ? "name" : !startIso ? "date" : !endIso ? "end" : !(Number(s.capacity) >= 1) ? "capacity" : null;
      if (s.doors && s.doors > s.start) bad = "doors";
      if (s.header && !/^https:\/\//.test(s.header)) bad = "header";
      if (bad) { var x = f.elements[bad]; if (x) x.focus(); h.setMsg(msg, bad === "doors" ? "De deuren gaan open vóór de start." : bad === "header" ? "De headerfoto moet een https-link zijn." : "Vul naam, datum, tijden en het aantal plekken in."); return; }
      var types = s.types.filter(function (t) { return String(t.name || "").trim(); }).map(function (t) { return { id: t.id || undefined, name: String(t.name).trim(), capacity: t.capacity || null }; });
      var body = { name: s.name.trim(), description: s.description.trim(), starts_at: startIso, ends_at: endIso, doors_at: doorsIso, address: s.address.trim(),
        capacity: Number(s.capacity), max_per_person: Math.max(1, Math.min(20, Number(s.max) || 4)), signup_until: untilIso, waitlist: !!s.waitlist, reminder: !!s.reminder,
        color: hex(s.color, "#6A5CFF"), header_url: s.header.trim() || null, status: published ? "published" : status, ticket_types: types };
      if (e) body.id = e.id;
      var btns = f.querySelectorAll("button[type=submit]"); btns.forEach(function (x) { x.disabled = true; });
      h.rpc("pasr_business_event_save", { p_business: b.id, p_event: body }, true).then(function (r) {
        h.toast(body.status === "published" ? (e ? "Event opgeslagen" : "Je event staat online") : "Concept bewaard");
        h.invalidate();
        return h.rpc("pasr_business_events", { p_business: b.id }, true).then(function (rows) {
          st.tkEvent = (rows || []).filter(function (x) { return x.id === r.id; })[0] || null;
          st.sub = st.tkEvent ? "tk-event" : null; h.render();
        });
      }).catch(function (x) { btns.forEach(function (y) { y.disabled = false; }); h.setMsg(msg, err(x, h)); });
    });
    $("[name=name]", f).focus({ preventScroll: true });
  }

  function regRows(rows) {
    // één rij per aanmelding (de RPC geeft één rij per ticket)
    var by = {}, out = [];
    rows.forEach(function (r) {
      var g = by[r.registration_id];
      if (!g) { g = by[r.registration_id] = { id: r.registration_id, first: r.first_name, last: r.last_name, email: r.email, birth: r.birth_date, created: r.created_at, tickets: [] }; out.push(g); }
      g.tickets.push(r);
    });
    out.forEach(function (g) {
      var live = g.tickets.filter(function (t) { return t.status !== "cancelled"; });
      var inn = g.tickets.filter(function (t) { return t.status === "checked_in"; }), wait = g.tickets.filter(function (t) { return t.status === "waitlist"; });
      var types = {}; live.forEach(function (t) { types[t.ticket_type || "Toegang"] = (types[t.ticket_type || "Toegang"] || 0) + 1; });
      g.types = Object.keys(types).map(function (k) { return k + (types[k] > 1 ? " ×" + types[k] : ""); }).join(", ") || (g.tickets[0] && g.tickets[0].ticket_type) || "—";
      g.state = inn.length ? ["Binnen " + hm(inn[0].checked_in_at), "on"] : wait.length ? ["Wachtlijst #" + (wait[0].waitlist_position || "?"), "wait"] : live.length ? ["Aangemeld", "iris"] : ["Afgemeld", ""];
      g.active = live.length > 0;
    });
    return out;
  }
  function csv(rows, name) {
    var head = ["Voornaam", "Achternaam", "E-mailadres", "Geboortedatum", "Ticketsoort", "Status", "Aangemeld op", "Binnen om"];
    var STATUS = { registered: "Aangemeld", checked_in: "Binnen", waitlist: "Wachtlijst", cancelled: "Afgemeld" };
    var q = function (v) { v = String(v == null ? "" : v); if (/^[=+\-@]/.test(v)) v = "'" + v; return '"' + v.replace(/"/g, '""') + '"'; };
    var lines = [head.map(q).join(";")].concat(rows.map(function (r) {
      return [r.first_name, r.last_name, r.email, r.birth_date, r.ticket_type, STATUS[r.status] || r.status, fmt(r.created_at, { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }),
        r.checked_in_at ? hm(r.checked_in_at) : ""].map(q).join(";");
    }));
    var blob = new Blob(["﻿" + lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
    var a = document.createElement("a"); a.href = URL.createObjectURL(blob);
    a.download = "aanmeldingen-" + String(name || "event").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") + ".csv";
    document.body.append(a); a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }

  function eventDetail(panel, b, h) {
    var esc = h.esc, st = h.state, e = st.tkEvent, s = eventState(e);
    var color = hex(e.color, "#6A5CFF");
    panel.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="tkBack">' + h.ICON.back + "Tickets</button></p>" +
      '<section class="zk-panel tk-detail" data-pasr-add="' + (e.status === "published" ? "e:" + esc(e.id) : "") + '" data-pasr-add-name="' + esc(e.name) + '">' +
      '<div class="tk-dhead"><span class="tk-dicon" style="background:' + esc(color) + ";color:" + textOn(color) + '">' + TKICON.ticket + "</span>" +
      '<div><h2 id="zd-title">' + esc(e.name) + ' <span class="zk-pill ' + s[1] + '">' + esc(s[0]) + "</span></h2><p>" + esc(dShort(e.starts_at) + " · " + hm(e.starts_at) + "–" + hm(e.ends_at) + (e.address ? " · " + e.address : "")) + "</p></div></div>" +
      '<div class="zk-actions tk-dactions"><button class="zk-btn ghost sm" type="button" id="tkCsv">' + TKICON.csv + "Exporteer CSV</button>" +
      (e.status !== "cancelled" ? '<button class="zk-btn sm" type="button" id="tkScan">' + h.ICON.scan + "Scannen aan de deur</button>" : "") +
      (e.status !== "cancelled" && Date.parse(e.ends_at) > Date.now() ? '<button class="zk-btn ghost sm" type="button" id="tkEdit">' + h.ICON.edit + "Bewerken</button>" : "") +
      (e.status === "published" ? '<button class="zk-btn ghost sm" type="button" id="tkLink">' + h.ICON.link + "Aanmeldlink</button>" : "") +
      (e.status !== "cancelled" && Date.parse(e.ends_at) > Date.now() ? '<button class="zk-btn ghost sm danger" type="button" id="tkCancel">' + TKICON.x + "Event afgelasten</button>" : "") + "</div>" +
      '<div class="tk-kpis" id="tkKpis">' + kpis(e) + "</div>" +
      '<div class="tk-progress" aria-hidden="true">' + bar(e) + "</div>" +
      '<p class="tk-legend"><span class="in">binnen ' + Number(e.checked_in || 0) + '</span><span class="reg">nog niet binnen ' + Math.max(0, Number(e.registered || 0) - Number(e.checked_in || 0)) + "</span><span>vrij " + Math.max(0, e.capacity - Number(e.registered || 0)) + "</span></p>" +
      '<div class="tk-reghead"><h3>Aanmeldingen</h3><label class="tk-search"><span class="sr-only">Zoek op naam of e-mail</span>' + h.ICON.search + '<input type="search" id="tkQ" placeholder="Zoek op naam of e-mail"></label></div>' +
      '<div id="tkRegs"><p class="zd3-muted">Laden…</p></div>' +
      '<p class="zd-help">Geboortedatum en e-mail zie alleen jij; ze staan niet op het ticket en niet in de QR-code. 30 dagen na het event worden ze gewist.</p></section>';
    var promo = document.createElement("section"); promo.className = "zk-panel tk-promo"; panel.appendChild(promo);
    if (window.PasrPromo) {
      var first = (b.cards || []).filter(function (c) { return c.color; })[0] || {};
      window.PasrPromo.mount(promo, { kind: "event", id: e.id, name: e.name, title: e.name, address: e.address || "", starts_at: e.starts_at, ends_at: e.ends_at,
        status: e.status, business: b.name, color: e.color || first.color || "#6A5CFF", logo: first.logo || "" });
    }
    $("#tkBack", panel).addEventListener("click", function () { st.sub = null; st.tkEvent = null; h.render(); });
    var ed = $("#tkEdit", panel); if (ed) ed.addEventListener("click", function () { st.sub = "tk-edit"; h.render(); });
    var sc = $("#tkScan", panel); if (sc) sc.addEventListener("click", function () { st.scanEvent = e.id; h.go("scannen"); });
    var lk = $("#tkLink", panel); if (lk) lk.addEventListener("click", function () { h.copy("https://pasr.nl/add/e/" + e.id); });
    var cn = $("#tkCancel", panel);
    if (cn) cn.addEventListener("click", function () {
      var md = h.modal("Event afgelasten", "<h2>" + esc(e.name) + " afgelasten?</h2><p>Alle tickets vervallen. Iedereen die zich aanmeldde krijgt een mail" + (e.status === "published" ? " en een pushmelding" : "") + ". Dit kan niet ongedaan worden.</p>" +
        '<label class="zk-form" style="display:grid;gap:6px;font-weight:600">Bericht aan de deelnemers <span class="zd-opt">(optioneel)</span><textarea id="tkCm" rows="3" maxlength="500" placeholder="bijv. Helaas ziek; we plannen een nieuwe datum."></textarea></label>' +
        '<p class="zd-modal-foot"><button class="zk-btn ghost" type="button" id="tkCNo">Terug</button><button class="zk-btn danger-solid" type="button" id="tkCYes">Afgelasten</button></p>', cn);
      $("#tkCNo", md.el).addEventListener("click", md.close);
      $("#tkCYes", md.el).addEventListener("click", function (ev) {
        ev.currentTarget.disabled = true;
        h.rpc("pasr_business_event_cancel", { p_business: b.id, p_event: e.id, p_message: ($("#tkCm", md.el).value || "").trim() || null }, true)
          .then(function () { md.close(); h.toast("Event afgelast; de deelnemers krijgen bericht"); h.invalidate(); e.status = "cancelled"; h.render(); })
          .catch(function (x) { md.close(); h.toast(err(x, h)); });
      });
    });
    var all = [];
    function drawRegs() {
      var q = ($("#tkQ", panel).value || "").trim().toLowerCase(), box = $("#tkRegs", panel);
      var groups = regRows(all).filter(function (g) { return !q || (g.first + " " + g.last + " " + g.email).toLowerCase().indexOf(q) >= 0; });
      if (!all.length) { box.innerHTML = '<p class="zd3-empty">Nog geen aanmeldingen. Deel de aanmeldlink of zet de knop op je website.</p>'; return; }
      if (!groups.length) { box.innerHTML = '<p class="zd3-muted">Niemand gevonden voor “' + esc(q) + "”.</p>"; return; }
      box.innerHTML = h.table(["Naam", "E-mail", "Geboortedatum", "Tickets", "Status", '<span class="sr-only">Acties</span>'], groups.map(function (g, i) {
        return { cells: ["<b>" + esc((g.first || "") + " " + (g.last || "")) + "</b>", esc(g.email || "—"), esc(g.birth ? g.birth.split("-").reverse().join("-") : "—"), esc(g.types),
          '<span class="zk-pill ' + g.state[1] + '">' + esc(g.state[0]) + "</span>",
          g.active && e.status !== "cancelled" ? '<button type="button" class="zk-btn ghost sm" data-rc="' + i + '">Afmelden</button>' : ""] };
      }), "tk-table");
      box.querySelectorAll("[data-rc]").forEach(function (btn) {
        btn.addEventListener("click", function () {
          var g = groups[Number(btn.dataset.rc)];
          if (!confirm((g.first || "") + " " + (g.last || "") + " afmelden? De tickets vervallen en de plek gaat naar de wachtlijst.")) return;
          btn.disabled = true;
          h.rpc("pasr_business_event_registration_cancel", { p_business: b.id, p_registration: g.id }, true).then(function (r) {
            h.toast("Afgemeld" + (r && r.promoted ? "; " + plural(r.promoted, "plek ging", "plekken gingen") + " naar de wachtlijst" : ""));
            h.invalidate(); load();
          }).catch(function (x) { btn.disabled = false; h.toast(err(x, h)); });
        });
      });
    }
    function load() {
      return Promise.all([h.rpc("pasr_business_event_registrations", { p_business: b.id, p_event: e.id }, true), h.rpc("pasr_business_events", { p_business: b.id }, true)]).then(function (r) {
        all = Array.isArray(r[0]) ? r[0] : [];
        var fresh = (r[1] || []).filter(function (x) { return x.id === e.id; })[0];
        if (fresh) { Object.assign(e, fresh); var k = $("#tkKpis", panel); if (k) k.innerHTML = kpis(e); var p = $(".tk-progress", panel); if (p) p.innerHTML = bar(e); }
        drawRegs();
      }).catch(function (x) { var box = $("#tkRegs", panel); if (box) box.innerHTML = '<p class="zk-empty">' + esc(err(x, h)) + "</p>"; });
    }
    $("#tkQ", panel).addEventListener("input", drawRegs);
    $("#tkCsv", panel).addEventListener("click", function () { if (all.length) csv(all, e.name); else h.toast("Nog geen aanmeldingen om te exporteren."); });
    load();
  }
  function kpis(e) {
    var reg = Number(e.registered || 0), cap = Number(e.capacity || 0), inn = Number(e.checked_in || 0), wait = Number(e.waitlist || 0), can = Number(e.cancelled || 0);
    function k(l, v, sub) { return '<div class="tk-kpi"><small>' + l + "</small><b>" + v + "</b><span>" + sub + "</span></div>"; }
    return k("Aangemeld", reg + " / " + cap, plural(Math.max(0, cap - reg), "plek vrij", "plekken vrij")) +
      k("Binnen", inn, inn ? "live bijgewerkt" : "nog niemand gescand") +
      k("Wachtlijst", wait, wait ? "schuiven automatisch door" : e.waitlist_enabled === false ? "staat uit" : "nog leeg") +
      k("Afgemeld", can, can ? "plek ging naar de wachtlijst" : "—");
  }
  function bar(e) {
    var cap = Math.max(1, Number(e.capacity || 1)), inn = Number(e.checked_in || 0), reg = Number(e.registered || 0);
    return '<i class="in" style="width:' + Math.min(100, inn / cap * 100) + '%"></i><i class="reg" style="width:' + Math.min(100, Math.max(0, reg - inn) / cap * 100) + '%"></i>';
  }

  // ================================================================= KLANTENKAARTEN
  var GOALS = [
    ["membership", "idcard", "Lidmaatschap of herkenning", "De klant laat zijn kaart zien; jij ziet wie het is. Geschikt voor vaste klanten, verenigingen en personeel."],
    ["saving", "star", "Sparen voor een beloning", "Elke scan telt als bezoek of punten."],
    ["fixed", "pct", "Vaste korting", "Altijd hetzelfde percentage voor leden."],
    ["periods", "calendar", "Korting in een periode", "Van–tot, eventueel alleen op bepaalde dagen of uren. Plan meerdere periodes vooruit."]
  ];
  /** Korting die nu geldt (zelfde regels als de server, voor het live voorbeeld). */
  function discountNow(s) {
    var p = parts(new Date().toISOString()), d = p.date, t = p.time, dow = ((new Date(d + "T12:00:00Z").getUTCDay() + 6) % 7) + 1, best = null;
    if (s.fixedOn && Number(s.fixed) > 0) best = { percent: Number(s.fixed), label: "Vaste korting", until: null };
    if (s.periodsOn) s.periods.forEach(function (x) {
      if (d < x.starts_on || d > x.ends_on) return;
      if (x.weekdays && x.weekdays.length && x.weekdays.indexOf(dow) < 0) return;
      if (x.from_time && t < x.from_time) return;
      if (x.to_time && t >= x.to_time) return;
      if (!best || Number(x.percent) > best.percent) best = { percent: Number(x.percent), label: x.label || pct(x.percent) + " korting", until: x.to_time ? "tot " + x.to_time : "t/m " + dmy(x.ends_on) };
    });
    return best;
  }
  function barcode(type, number) {
    try {
      if (type === "qr" && window.qrcode) { var q = window.qrcode(0, "M"); q.addData(number); q.make(); return '<span class="mc-qr">' + q.createSvgTag({ cellSize: 3, margin: 0, scalable: true }) + "</span>"; }
      if (window.JsBarcode) {
        var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        window.JsBarcode(svg, number, { format: type === "ean13" ? "EAN13" : "CODE128", displayValue: true, height: 46, margin: 0, fontSize: 13, font: "monospace", width: 1.6, background: "transparent" });
        return '<span class="mc-bars">' + svg.outerHTML + "</span>";
      }
    } catch (e) { /* valt terug op tekst */ }
    return '<span class="mc-bars mc-fake"><i></i><code>' + number + "</code></span>";
  }
  function sampleNumber(s) { return s.type === "ean13" ? "2123456789018" : (s.prefix || "") + "000124"; }
  function cardPreview(s, b, esc) {
    var color = hex(s.color, "#6A5CFF"), t = textOn(color), now = discountNow(s), logo = s.logo || bizLogo(b);
    return '<div class="mc-card" style="--mc:' + color + ";--mt:" + t + '">' +
      '<div class="mc-top"><span class="tk-logo">' + (logo ? '<img alt="" src="' + imgSrc(logo) + '">' : esc(String(b.name || "?").charAt(0))) + '</span><span class="tk-tbiz"><b>' + esc(s.name || "Naam van je kaart") + "</b><small>" + esc(b.name) + "</small></span><em>Klantenkaart</em></div>" +
      (now ? '<div class="mc-chip">' + TKICON.pct + "<b>Nu " + esc(pct(now.percent)) + " korting</b>" + (now.until ? "<small>" + esc(now.until) + "</small>" : "") + "</div>" : "") +
      (s.savingOn ? '<div class="mc-save"><span>' + (s.unit === "points" ? "Punten" : "Spaarstand") + '</span><span class="mc-sbar"><i style="width:60%"></i></span><b>' + Math.round(Number(s.target || 10) * 0.6) + "/" + esc(s.target || 10) + "</b></div>" +
        '<small class="mc-hint">Nog ' + (Number(s.target || 10) - Math.round(Number(s.target || 10) * 0.6)) + " " + (s.unit === "points" ? "punten" : "bezoeken") + " tot " + esc(s.reward || "je beloning") + "</small>" : "") +
      '<div class="mc-code">' + barcode(s.type, sampleNumber(s)) + "</div>" +
      '<div class="mc-foot"><span>Lid: <b>Anna de Vries</b></span><span>sinds ' + esc(fmt(new Date().toISOString(), { month: "short", year: "numeric" })) + "</span></div></div>";
  }

  function cards(panel, b, h) {
    var st = h.state, esc = h.esc;
    if (st.sub === "mc-edit") return cardEdit(panel, b, h);
    panel.innerHTML = h.panelTitle("Klantenkaarten", "Een eigen klantenkaart met barcode: herkenning, sparen, vaste korting of korting in een periode. Klanten worden lid in Pasr; scannen gaat met Pasr Zakelijk of de scanner hier.",
      '<button class="zk-btn" type="button" id="mcNew">' + h.ICON.plus + "Nieuwe klantenkaart</button>") + '<div id="mcList"><p class="zd3-muted">Laden…</p></div>';
    $("#mcNew", panel).addEventListener("click", function () { st.sub = "mc-edit"; st.mcCard = null; h.render(); });
    h.rpc("pasr_business_member_cards", { p_business: b.id }, true).then(function (rows) {
      rows = Array.isArray(rows) ? rows : [];
      var box = $("#mcList", panel); if (!box) return;
      if (!rows.length) {
        box.innerHTML = '<div class="zk-panel zd-first tk-first"><div class="zd-first-card">' + cardPreview({ name: b.name + " Klantenkaart", color: bizColor(b), type: "code128", prefix: "KS-", savingOn: true, target: 10, reward: "een gratis gebakje", periodsOn: false, periods: [], fixedOn: false }, b, esc) +
          "</div><div><h3>Je eigen klantenkaart</h3><p>Kies je logo en kleur, het soort barcode en wat de kaart doet: klanten herkennen, sparen, een vaste korting of korting in een periode. Pasr maakt de kaartnummers zelf.</p>" +
          '<button class="zk-btn" id="mcFirst" type="button">' + h.ICON.plus + "Klantenkaart maken</button></div></div>";
        $("#mcFirst", box).addEventListener("click", function () { st.sub = "mc-edit"; st.mcCard = null; h.render(); });
        return;
      }
      box.innerHTML = '<div class="zk-cards mc-list">' + rows.map(function (c, i) {
        var s = stateOf(c), state = c.status === "published" ? ["Online", " on"] : c.status === "archived" ? ["Gearchiveerd", ""] : ["Concept", " wait"];
        return '<article class="zk-card mc-item" data-pasr-add="' + (c.status === "published" ? "m:" + esc(c.id) : "") + '" data-pasr-add-name="' + esc(c.name) + '">' + cardPreview(s, b, esc) +
          '<div class="zd-cardinfo"><div class="zd-cardtitle"><h3>' + esc(c.name) + '</h3><span class="zk-pill' + state[1] + '">' + state[0] + "</span></div>" +
          '<p class="zd-sub">' + esc(goalText(c.goals)) + "</p>" +
          '<div class="zk-stats"><span class="zk-stat"><b>' + Number(c.members || 0) + '</b><small>leden</small></span><span class="zk-stat"><b>' + Number(c.visits_today || 0) + '</b><small>scans vandaag</small></span>' +
          '<span class="zk-stat"><b>' + (c.discount_now ? esc(pct(c.discount_now.percent)) : "—") + "</b><small>" + (c.discount_now ? "korting nu" : c.next_discount ? "vanaf " + esc(dShort(c.next_discount.starts_at)) : "geen korting nu") + "</small></span></div>" +
          '<div class="zk-actions">' + (c.status !== "archived" ? '<button class="zk-btn sm" type="button" data-e="' + i + '">' + h.ICON.edit + "Bewerken</button>" : "") +
          (c.status === "published" ? '<button class="zk-btn ghost sm" type="button" data-l="' + i + '">' + h.ICON.link + "Link</button>" : "") +
          (c.status !== "archived" ? '<button class="zk-btn ghost sm danger" type="button" data-a="' + i + '">Archiveren</button>' : "") + "</div></div></article>";
      }).join("") + "</div>";
      box.querySelectorAll("[data-e]").forEach(function (x) { x.addEventListener("click", function () { st.sub = "mc-edit"; st.mcCard = rows[Number(x.dataset.e)]; h.render(); }); });
      box.querySelectorAll("[data-l]").forEach(function (x) { x.addEventListener("click", function () { h.copy("https://pasr.nl/add/m/" + rows[Number(x.dataset.l)].id); }); });
      box.querySelectorAll("[data-a]").forEach(function (x) {
        x.addEventListener("click", function () {
          var c = rows[Number(x.dataset.a)];
          if (!confirm(c.name + " archiveren? Scannen werkt dan niet meer en nieuwe klanten kunnen geen lid worden.")) return;
          x.disabled = true;
          var s = stateOf(c);
          h.rpc("pasr_business_member_card_save", { p_business: b.id, p_card: payload(c.id, s, "archived") }, true)
            .then(function () { h.toast("Gearchiveerd"); h.invalidate(); h.render(); }).catch(function (e) { x.disabled = false; h.toast(err(e, h)); });
        });
      });
    }).catch(function (e) { var box = $("#mcList", panel); if (box) box.innerHTML = '<p class="zk-empty">' + esc(err(e, h)) + "</p>"; });
  }
  function goalText(g) {
    g = g || {};
    var out = [];
    if (g.membership) out.push("herkenning");
    if (g.saving && g.saving.enabled) out.push("sparen: " + (g.saving.reward || "beloning") + " na " + g.saving.target);
    if (g.fixed_discount && g.fixed_discount.enabled) out.push(pct(g.fixed_discount.percent) + " vaste korting");
    if (g.periods && g.periods.length) out.push(plural(g.periods.length, "kortingsperiode", "kortingsperiodes"));
    return out.length ? out.join(" · ").replace(/^./, function (c) { return c.toUpperCase(); }) : "Nog geen doel gekozen";
  }
  function stateOf(c) {
    var g = (c && c.goals) || {};
    return { name: c ? c.name : "", color: c ? c.color : null, logo: c ? c.logo : null, type: c ? c.barcode_type : "qr", prefix: c ? c.prefix || "" : "", status: c ? c.status : "draft",
      membership: !!g.membership, savingOn: !!(g.saving && g.saving.enabled), unit: (g.saving && g.saving.unit) || "visits", perScan: 1, target: (g.saving && g.saving.target) || 10, reward: (g.saving && g.saving.reward) || "",
      fixedOn: !!(g.fixed_discount && g.fixed_discount.enabled), fixed: (g.fixed_discount && g.fixed_discount.percent) || 10,
      periodsOn: !!(g.periods && g.periods.length), periods: (g.periods || []).map(function (p) { return { id: p.id, label: p.label || "", percent: Number(p.percent), starts_on: p.starts_on, ends_on: p.ends_on, weekdays: p.weekdays || null, from_time: p.from_time || null, to_time: p.to_time || null }; }) };
  }
  function payload(id, s, status) {
    var body = { name: s.name.trim(), color: hex(s.color, "#6A5CFF"), barcode_type: s.type, prefix: s.type === "ean13" ? "" : s.prefix.toUpperCase(), status: status,
      goals: { membership: !!s.membership,
        saving: s.savingOn ? { enabled: true, unit: s.unit, target: Number(s.target), reward: s.reward.trim() } : { enabled: false },
        fixed_discount: s.fixedOn ? { enabled: true, percent: Number(s.fixed) } : { enabled: false },
        periods: s.periodsOn ? s.periods.map(function (p) { return { id: p.id, label: p.label, percent: Number(p.percent), starts_on: p.starts_on, ends_on: p.ends_on, weekdays: p.weekdays && p.weekdays.length ? p.weekdays : null, from_time: p.from_time || null, to_time: p.to_time || null }; }) : [] } };
    if (s.logo !== undefined) body.logo = s.logo || null;
    if (id) body.id = id;
    return body;
  }
  function periodText(p) {
    var days = p.weekdays && p.weekdays.length ? (p.weekdays.length === 1 ? "elke " + ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"][p.weekdays[0] - 1] : p.weekdays.map(function (d) { return DAYS[d - 1]; }).join(", ")) : "";
    var time = p.from_time || p.to_time ? (p.from_time || "00:00") + "–" + (p.to_time || "24:00") : "hele dag";
    return (days ? days + " " : dmy(p.starts_on) + " – " + dmy(p.ends_on) + " · ") + time + " · " + pct(p.percent) + (p.label ? " · " + p.label : "");
  }
  function months() {
    var p = today().split("-").map(Number), out = [];
    for (var i = 0; i < 3; i++) { var y = p[0] + Math.floor((p[1] - 1 + i) / 12), m = (p[1] - 1 + i) % 12 + 1; out.push({ y: y, m: m }); }
    return out;
  }
  function timeline(s, mo, esc) {
    var last = new Date(Date.UTC(mo.y, mo.m, 0)).getUTCDate(), first = mo.y + "-" + String(mo.m).padStart(2, "0") + "-01", end = mo.y + "-" + String(mo.m).padStart(2, "0") + "-" + last;
    var lanes = s.periods.map(function (p, i) {
      if (p.ends_on < first || p.starts_on > end) return "";
      var a = p.starts_on < first ? 1 : Number(p.starts_on.slice(8)), z = p.ends_on > end ? last : Number(p.ends_on.slice(8));
      if (p.weekdays && p.weekdays.length) {
        var ticks = "";
        for (var d = a; d <= z; d++) {
          var dow = ((new Date(Date.UTC(mo.y, mo.m - 1, d)).getUTCDay() + 6) % 7) + 1;
          if (p.weekdays.indexOf(dow) >= 0) ticks += '<i style="left:' + ((d - 1) / last * 100) + "%;width:" + (100 / last) + '%"></i>';
        }
        return '<div class="mc-lane ticks c' + (i % 4) + '">' + ticks + '<span class="mc-lanelabel">' + esc(periodText(p)) + "</span></div>";
      }
      return '<div class="mc-lane"><span class="mc-span c' + (i % 4) + '" style="left:' + ((a - 1) / last * 100) + "%;width:" + ((z - a + 1) / last * 100) + '%">' + esc(a + "–" + z + " · " + (p.label && p.label.indexOf(pct(p.percent)) === 0 ? p.label : pct(p.percent) + (p.label ? " " + p.label : ""))) + "</span></div>";
    }).join("");
    var scale = [1, 5, 10, 15, 20, 25, last].map(function (d) { return '<span style="left:' + ((d - 1) / last * 100) + '%">' + d + "</span>"; }).join("");
    return '<div class="mc-scale" aria-hidden="true">' + scale + "</div>" + (lanes || '<p class="zd3-muted">Geen kortingsperiodes in deze maand.</p>');
  }

  function cardEdit(panel, b, h) {
    var st = h.state, esc = h.esc, c = st.mcCard, s = stateOf(c);
    if (!c) { s.color = bizColor(b); s.name = ""; s.logo = undefined; }
    var mo = months(), moSel = 0, approved = b.status === "approved", hasMembers = c && Number(c.members || 0) > 0;
    var colors = COLORS.indexOf(hex(s.color, "")) < 0 ? [hex(s.color, "#6A5CFF")].concat(COLORS) : COLORS;
    function tile(type, label, art) {
      return '<label class="mc-bc"><input type="radio" name="type" value="' + type + '"' + (s.type === type ? " checked" : "") + (hasMembers && s.type !== type ? " disabled" : "") + '><span class="mc-bcart">' + art + "</span><b>" + label + "</b></label>";
    }
    var art = {
      qr: '<svg viewBox="0 0 40 40" aria-hidden="true"><path fill="currentColor" d="M2 2h12v12H2zm3 3v6h6V5zM26 2h12v12H26zm3 3v6h6V5zM2 26h12v12H2zm3 3v6h6v-6zM18 2h4v4h-4zm0 8h4v8h-4zm-8 8h4v4h-4zm8 4h8v4h-8zm10 0h4v4h-4zm6 4h4v12h-4zM18 30h4v8h-4zm8 0h4v4h-4zm0 8h8v-4h-4v-4h-4z"/></svg>',
      code128: '<svg viewBox="0 0 60 30" aria-hidden="true"><path fill="currentColor" d="M2 2h2v26H2zm4 0h1v26H6zm3 0h3v26H9zm5 0h1v26h-1zm3 0h2v26h-2zm4 0h3v26h-3zm5 0h1v26h-1zm3 0h2v26h-2zm4 0h1v26h-1zm3 0h3v26h-3zm5 0h2v26h-2zm4 0h1v26h-1zm3 0h3v26h-3z"/></svg>',
      ean13: '<svg viewBox="0 0 60 34" aria-hidden="true"><path fill="currentColor" d="M2 0h1v28H2zm2 0h1v28H4zm3 0h2v24H7zm4 0h1v24h-1zm3 0h3v24h-3zm5 0h1v24h-1zm3 0h1v24h-1zm2 0h1v28h-1zm2 0h1v28h-1zm3 0h2v24h-2zm4 0h1v24h-1zm3 0h3v24h-3zm5 0h1v24h-1zm3 0h2v24h-2zm4 0h1v28h-1zm2 0h1v28h-1z"/><text x="30" y="33" font-size="6" text-anchor="middle" fill="currentColor" font-family="monospace">8712345000124</text></svg>'
    };
    panel.innerHTML = '<p class="zd-back"><button class="zk-btn ghost sm" type="button" id="mcBack">' + h.ICON.back + "Klantenkaarten</button></p>" +
      '<div class="tk-editor"><form class="zk-panel zk-form tk-form" id="mcForm" novalidate>' +
      '<div class="tk-formhead"><h2 id="zd-title">' + (c ? "Klantenkaart bewerken" : "Nieuwe klantenkaart") + "</h2>" +
      '<div class="tk-formbtns"><button class="zk-btn ghost" type="submit" data-status="draft"' + (c && c.status === "published" ? " hidden" : "") + ">Concept bewaren</button>" +
      '<button class="zk-btn" type="submit" data-status="published"' + (approved ? "" : " disabled") + ">" + h.ICON.check + (c && c.status === "published" ? "Opslaan" : "Online zetten") + "</button></div></div>" +
      '<label>Naam van de kaart<input name="name" maxlength="40" required value="' + esc(s.name) + '" placeholder="bijv. ' + esc(b.name) + ' Klantenkaart"></label>' +
      '<fieldset class="mc-logo"><legend>Logo en kleur</legend><span class="row"><label class="zk-btn ghost sm mc-upload">' + h.ICON.upload + '<span>Logo</span><input type="file" accept="image/png,image/jpeg" id="mcLogo" class="sr-only"></label>' +
      '<span class="tk-swatches" role="radiogroup" aria-label="Kleur">' + colors.map(function (x) { return '<button type="button" role="radio" data-c="' + x + '" aria-checked="' + (hex(s.color, "") === x) + '" style="background:' + x + '" aria-label="Kleur ' + x + '"></button>'; }).join("") + "</span></span></fieldset>" +
      '<fieldset class="mc-types"><legend>Soort barcode</legend><div class="mc-bcs">' + tile("qr", "QR-code", art.qr) + tile("code128", "Code 128", art.code128) + tile("ean13", "EAN-13", art.ean13) + "</div>" +
      (hasMembers ? '<small class="zd-help">Het soort barcode ligt vast: er zijn al leden.</small>' : "") + "</fieldset>" +
      '<div class="mc-row"><label>Voorvoegsel kaartnummer<input name="prefix" maxlength="8" pattern="[A-Za-z0-9-]{0,8}" value="' + esc(s.prefix) + '" placeholder="bijv. KS-"' + (s.type === "ean13" ? " disabled" : "") + "></label>" +
      '<label>Nummering<input id="mcNum" disabled value=""></label></div>' +
      '<p class="zd-help">Pasr maakt de nummers zelf. Scannen gaat met Pasr Zakelijk of de scanner op pasr.nl; koppelen met je eigen kassa komt later.</p>' +
      '<fieldset class="mc-goals"><legend>Doel van de kaart · kies er één of meer</legend><div class="mc-goalgrid">' + GOALS.map(function (g) {
        var on = g[0] === "membership" ? s.membership : g[0] === "saving" ? s.savingOn : g[0] === "fixed" ? s.fixedOn : s.periodsOn;
        var extra = g[0] === "saving" ? '<div class="mc-goalx"><label>Per scan<select name="unit"><option value="visits"' + (s.unit === "visits" ? " selected" : "") + ">1 bezoek</option><option value=\"points\"" + (s.unit === "points" ? " selected" : "") + ">punten (bij scannen)</option></select></label>" +
            '<label>Beloning na<input name="target" type="number" min="1" max="1000" value="' + esc(s.target) + '"></label><label class="wide">Beloning<input name="reward" maxlength="80" value="' + esc(s.reward) + '" placeholder="bijv. Gratis gebakje naar keuze"></label></div>'
          : g[0] === "fixed" ? '<div class="mc-goalx"><label>Korting<span class="mc-pct"><input name="fixed" type="number" min="1" max="100" step="0.5" value="' + esc(s.fixed) + '"><span>%</span></span></label></div>' : "";
        return '<label class="mc-goal' + (on ? " on" : "") + '" data-goal="' + g[0] + '"><input type="checkbox" name="goal_' + g[0] + '"' + (on ? " checked" : "") + '><span class="mc-gicon">' + (TKICON[g[1]] || h.ICON[g[1]]) + "</span><b>" + g[2] + "</b><small>" + g[3] + "</small>" + extra + "</label>";
      }).join("") + "</div></fieldset>" +
      '<section class="mc-periods" id="mcPeriods"' + (s.periodsOn ? "" : " hidden") + ' aria-labelledby="mcPerH"><div class="mc-phead"><h3 id="mcPerH">Kortingsperiodes · <span id="mcMoName"></span></h3><div class="zi-seg" role="group" aria-label="Maand">' +
      mo.map(function (m, i) { return '<button type="button" data-m="' + i + '" aria-pressed="' + (i === 0) + '">' + esc(new Intl.DateTimeFormat("nl-NL", { month: "short" }).format(new Date(Date.UTC(m.y, m.m - 1, 15))).replace(".", "")) + "</button>"; }).join("") + "</div></div>" +
      '<div class="mc-timeline" id="mcTimeline"></div><ul class="mc-pchips" id="mcChips"></ul>' +
      '<details class="mc-padd" id="mcAdd"><summary>' + h.ICON.plus + "Periode toevoegen</summary><div class=\"mc-pform\">" +
      '<label>Omschrijving<input id="pLabel" maxlength="40" placeholder="bijv. happy hour"></label><label>Korting<span class="mc-pct"><input id="pPct" type="number" min="1" max="100" step="0.5" value="10"><span>%</span></span></label>' +
      '<label>Van<input id="pFrom" type="date" value="' + today() + '"></label><label>Tot en met<input id="pTo" type="date" value="' + today() + '"></label>' +
      '<fieldset class="mc-days"><legend>Alleen op <span class="zd-opt">(leeg = elke dag)</span></legend>' + DAYS.map(function (d, i) { return '<label><input type="checkbox" value="' + (i + 1) + '"><span>' + d + "</span></label>"; }).join("") + "</fieldset>" +
      '<label>Vanaf <span class="zd-opt">(tijd)</span><input id="pT1" type="time"></label><label>Tot <span class="zd-opt">(tijd)</span><input id="pT2" type="time"></label>' +
      '<button type="button" class="zk-btn sm" id="pSave">Periode toevoegen</button><p class="zk-msg" id="pMsg" role="status"></p></div></details></section>' +
      '<p class="zk-msg" id="mcMsg" role="status" aria-live="polite"></p>' + (approved ? "" : '<p class="zd-help">Online zetten kan na goedkeuring van je zaak; als concept bewaren kan al.</p>') + "</form>" +
      '<aside class="tk-preview"><p class="tk-prevlabel">Live voorbeeld</p><div id="mcPrev"></div><p class="zd-help">De korting die nu geldt en de spaarstand staan op de kaart; ze veranderen vanzelf mee, ook in Wallet.' +
      (c ? " " + plural(Number(c.members || 0), "lid", "leden") + "." : "") + "</p></aside></div>";
    var f = $("#mcForm", panel);
    function draw() {
      $("#mcPrev", panel).innerHTML = cardPreview(s, b, esc);
      var num = $("#mcNum", panel); if (num) num.value = s.type === "ean13" ? "Automatisch · EAN-13 met controlecijfer" : "Automatisch · " + (s.prefix || "").toUpperCase() + "000125, …";
      $("#mcPeriods", panel).hidden = !s.periodsOn;
      if (s.periodsOn) {
        var m = mo[moSel];
        $("#mcMoName", panel).textContent = new Intl.DateTimeFormat("nl-NL", { month: "long" }).format(new Date(Date.UTC(m.y, m.m - 1, 15)));
        $("#mcTimeline", panel).innerHTML = timeline(s, m, esc);
        $("#mcChips", panel).innerHTML = s.periods.map(function (p, i) {
          return '<li><span class="mc-pchip c' + (i % 4) + '">' + (p.from_time ? h.ICON.clock : h.ICON.calendar) + esc(periodText(p)) + '<button type="button" data-px="' + i + '" aria-label="Periode verwijderen">' + TKICON.x + "</button></span></li>";
        }).join("");
        $("#mcChips", panel).querySelectorAll("[data-px]").forEach(function (x) { x.addEventListener("click", function () { s.periods.splice(Number(x.dataset.px), 1); draw(); }); });
      }
    }
    draw();
    f.addEventListener("input", function (ev) {
      var t = ev.target, n = t.name;
      if (!n) return;
      if (n === "type") { s.type = t.value; $("[name=prefix]", f).disabled = s.type === "ean13"; }
      else if (n.indexOf("goal_") === 0) {
        var g = n.slice(5); if (g === "membership") s.membership = t.checked; else if (g === "saving") s.savingOn = t.checked; else if (g === "fixed") s.fixedOn = t.checked; else s.periodsOn = t.checked;
        t.closest(".mc-goal").classList.toggle("on", t.checked);
      } else if (n === "prefix") { t.value = t.value.toUpperCase().replace(/[^A-Z0-9-]/g, "").slice(0, 8); s.prefix = t.value; }
      else s[n] = t.value;
      draw();
    });
    panel.querySelectorAll(".tk-swatches button").forEach(function (btn) {
      btn.addEventListener("click", function () { s.color = btn.dataset.c; panel.querySelectorAll(".tk-swatches button").forEach(function (x) { x.setAttribute("aria-checked", String(x === btn)); }); draw(); });
    });
    panel.querySelectorAll("[data-m]").forEach(function (btn) {
      btn.addEventListener("click", function () { moSel = Number(btn.dataset.m); panel.querySelectorAll("[data-m]").forEach(function (x) { x.setAttribute("aria-pressed", String(x === btn)); }); draw(); });
    });
    $("#mcLogo", panel).addEventListener("change", function (ev) {
      var file = ev.target.files && ev.target.files[0]; if (!file) return;
      var img = new Image(), url = URL.createObjectURL(file);
      img.onload = function () {
        var size = 256, k = Math.min(size / img.width, size / img.height, 1), cv = document.createElement("canvas");
        cv.width = Math.max(1, Math.round(img.width * k)); cv.height = Math.max(1, Math.round(img.height * k));
        cv.getContext("2d").drawImage(img, 0, 0, cv.width, cv.height);
        s.logo = cv.toDataURL("image/png").split(",")[1]; if (s.logo.length > 200000) s.logo = cv.toDataURL("image/jpeg", 0.85).split(",")[1];
        URL.revokeObjectURL(url); draw();
      };
      img.src = url;
    });
    $("#pSave", panel).addEventListener("click", function () {
      var p = { label: $("#pLabel", panel).value.trim(), percent: Number($("#pPct", panel).value), starts_on: $("#pFrom", panel).value, ends_on: $("#pTo", panel).value,
        weekdays: Array.prototype.map.call(panel.querySelectorAll(".mc-days input:checked"), function (x) { return Number(x.value); }),
        from_time: $("#pT1", panel).value || null, to_time: $("#pT2", panel).value || null };
      var msg = $("#pMsg", panel);
      if (!(p.percent > 0 && p.percent <= 100)) return h.setMsg(msg, "Kies een korting tussen 1 en 100%.");
      if (!p.starts_on || !p.ends_on || p.ends_on < p.starts_on) return h.setMsg(msg, "De einddatum ligt na de begindatum.");
      if (p.from_time && p.to_time && p.to_time <= p.from_time) return h.setMsg(msg, "De eindtijd ligt na de begintijd.");
      if (s.periods.length >= 20) return h.setMsg(msg, "Hoogstens 20 periodes.");
      if (!p.weekdays.length) p.weekdays = null;
      s.periods.push(p); h.setMsg(msg, ""); $("#pLabel", panel).value = ""; $("#mcAdd", panel).open = false;
      var m = p.starts_on.split("-").map(Number); mo.forEach(function (x, i) { if (x.y === m[0] && x.m === m[1]) { moSel = i; panel.querySelectorAll("[data-m]").forEach(function (y, j) { y.setAttribute("aria-pressed", String(j === i)); }); } });
      draw();
    });
    $("#mcBack", panel).addEventListener("click", function () { st.sub = null; st.mcCard = null; h.render(); });
    f.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var status = (c && c.status === "published") ? "published" : ((ev.submitter && ev.submitter.dataset.status) || "draft"), msg = $("#mcMsg", panel);
      if (!s.name.trim()) { $("[name=name]", f).focus(); return h.setMsg(msg, "Geef de kaart een naam."); }
      if (s.savingOn && (!s.reward.trim() || !(Number(s.target) >= 1))) { $("[name=reward]", f).focus(); return h.setMsg(msg, "Vul bij sparen de beloning en het aantal in."); }
      if (s.periodsOn && !s.periods.length) return h.setMsg(msg, "Voeg een kortingsperiode toe, of zet Korting in een periode uit.");
      if (status === "published" && !(s.membership || s.savingOn || s.fixedOn || s.periodsOn)) return h.setMsg(msg, "Kies minstens één doel voor de kaart.");
      var btns = f.querySelectorAll("button[type=submit]"); btns.forEach(function (x) { x.disabled = true; });
      h.rpc("pasr_business_member_card_save", { p_business: b.id, p_card: payload(c && c.id, s, status) }, true).then(function () {
        h.toast(status === "published" ? "Je klantenkaart staat online" : "Concept bewaard"); h.invalidate(); st.sub = null; st.mcCard = null; h.render();
      }).catch(function (x) { btns.forEach(function (y) { y.disabled = false; }); h.setMsg(msg, err(x, h)); });
    });
    $("[name=name]", f).focus({ preventScroll: true });
  }

  // ================================================================= Vandaag, zoeken, scanner
  /** Te doen voor Vandaag en de bel: events die bijna vol zijn of een wachtlijst hebben, concepten, aflopende kortingsperiodes. */
  function todo(b, x, h) {
    var out = [], now = Date.now(), week = now + 7 * 864e5;
    (x.events || []).forEach(function (e) {
      if (e.status === "published" && Date.parse(e.ends_at) > now) {
        var left = Number(e.capacity) - Number(e.registered || 0);
        if (Number(e.waitlist || 0) > 0 || left <= Math.max(3, Number(e.capacity) * 0.1)) {
          out.push({ icon: "ticket", tone: "iris", html: "<b>" + h.esc(e.name) + "</b> is " + (left <= 0 ? "vol" : "bijna vol: " + plural(left, "plek", "plekken") + " over"),
            sub: Number(e.waitlist || 0) ? plural(Number(e.waitlist), "persoon staat", "mensen staan") + " op de wachtlijst · plekken bijzetten?" : "Aanmelden loopt goed", label: "Plekken bijzetten", tab: "tickets", tkEvent: e, edit: true });
        }
      }
      if (e.status === "draft" && Date.parse(e.starts_at) > now) out.push({ icon: "ticket", tone: "iris", html: "Event <b>" + h.esc(e.name) + "</b> staat nog in concept", sub: "Zet het online zodat klanten zich kunnen aanmelden", label: "Bekijken", tab: "tickets", tkEvent: e, edit: true });
    });
    (x.memberCards || []).forEach(function (c) {
      if (c.status === "draft") out.push({ icon: "mcard", tone: "iris", html: "<b>" + h.esc(c.name) + "</b> staat nog in concept", sub: "Zet hem online zodat klanten hem kunnen toevoegen", label: "Online zetten", tab: "klantenkaarten", mcCard: c });
      ((c.goals && c.goals.periods) || []).forEach(function (p) {
        var end = Date.parse(p.ends_on + "T23:59:00");
        if (c.status === "published" && end > now && end <= week && p.starts_on <= today()) {
          out.push({ icon: "pct", tone: "mint", html: "Kortingsperiode <b>" + h.esc(p.label || pct(p.percent) + " korting") + "</b> loopt af op " + h.esc(dmy(p.ends_on)), sub: "Verlengen of een nieuwe periode plannen", label: "Plannen", tab: "klantenkaarten", mcCard: c });
        }
      });
    });
    return out;
  }
  function upcoming(x, h) {
    var now = Date.now(), list = (x.events || []).filter(function (e) { return e.status !== "cancelled" && Date.parse(e.ends_at) > now; }).slice(0, 4);
    if (!list.length) return '<p class="zd3-empty">Nog geen events gepland. Maak een gratis event met aanmelding.</p>';
    return '<ul class="tk-upc">' + list.map(function (e, i) {
      var s = eventState(e, now);
      return '<li><button type="button" data-upc="' + i + '"><span class="tk-upd"><b>' + h.esc(fmt(e.starts_at, { day: "numeric" })) + "</b><small>" + h.esc(fmt(e.starts_at, { month: "short" }).replace(".", "").toUpperCase()) + '</small></span><span class="zd3-rt"><b>' + h.esc(e.name) + "</b><small>" +
        h.esc(hm(e.starts_at) + " · " + (e.status === "draft" ? "concept" : Number(e.registered || 0) + "/" + e.capacity + " aangemeld")) + '</small></span><span class="zk-pill ' + s[1] + '">' + s[0] + "</span></button></li>";
    }).join("") + "</ul>";
  }
  function kpiTiles(x, h) {
    var now = Date.now(), next = (x.events || []).filter(function (e) { return e.status === "published" && Date.parse(e.ends_at) > now; })[0];
    var members = (x.memberCards || []).reduce(function (a, c) { return a + (c.status === "archived" ? 0 : Number(c.members || 0)); }, 0);
    var disc = (x.memberCards || []).filter(function (c) { return c.status === "published" && c.discount_now; }).sort(function (a, c) { return Number(c.discount_now.percent) - Number(a.discount_now.percent); })[0];
    var scans = (x.memberCards || []).reduce(function (a, c) { return a + Number(c.visits_today || 0); }, 0);
    if (!next && !(x.memberCards || []).length) return "";
    function tile(icon, label, val, sub, extra) { return '<div class="zd3-kpi tk-k"><small>' + (TKICON[icon] || h.ICON[icon]) + h.esc(label) + "</small><b>" + val + "</b>" + (extra || "") + '<span class="zd3-trend">' + sub + "</span></div>"; }
    var dper = disc && disc.discount_now;
    return tile("ticket", next ? "Aanmeldingen " + next.name : "Aanmeldingen", next ? Number(next.registered || 0) + " / " + next.capacity : "—",
        next ? h.esc(dShort(next.starts_at)) + (Number(next.waitlist || 0) ? " · " + next.waitlist + " op de wachtlijst" : "") : "geen event gepland",
        next ? '<span class="tk-minibar"><i style="width:' + Math.min(100, Number(next.registered || 0) / Math.max(1, next.capacity) * 100) + '%"></i></span>' : "") +
      tile("mcard", "Klantenkaart-leden", members, plural((x.memberCards || []).filter(function (c) { return c.status === "published"; }).length, "kaart online", "kaarten online")) +
      tile("pct", "Kortingsperiode", dper ? h.esc(pct(dper.percent)) : "—", dper ? (dper.until_date ? "loopt t/m " + h.esc(dmy(dper.until_date)) : dper.until ? "loopt tot " + h.esc(fmt(dper.until, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })) : "vaste korting") : "nu geen korting") +
      tile("scan", "Klantenkaart-scans vandaag", scans, "bezoeken geregistreerd");
  }

  // ---- scanner: ticket aan de deur of klantenkaart aan de kassa (zelfde RPC's als Pasr Zakelijk)
  var TICKET = /^[A-Z2-7]{20,40}$/;
  function isTicket(code) { return TICKET.test(code) && !/^P[ZC]/.test(code); }
  function scanTicket(root, h, zaak, code, eventId, again) {
    return h.rpc("pasr_business_ticket_scan", { p_business: zaak, p_code: code, p_event: eventId || null }, true).then(function (r) {
      if (r.result === "invalid" && !again) return null;   // misschien een klantenkaart
      var ok = r.result === "valid";
      var why = { used: "Al gebruikt om " + hm(r.checked_in_at), other_event: "Ticket voor een ander event" + (r.event_name ? ": " + r.event_name : ""), cancelled: "Afgemeld of afgelast", invalid: r.reason === "waitlist" ? "Staat nog op de wachtlijst" : "Onbekend ticket" }[r.result];
      var c = r.counts || {};
      root.innerHTML = '<div class="tk-scanres ' + (ok ? "ok" : "bad") + '" tabindex="-1" id="tkRes"><span class="tk-scanic">' + (ok ? h.ICON.check : TKICON.x) + "</span><h3>" + (ok ? "Geldig" : "Niet geldig") + "</h3>" +
        (why ? "<p><b>" + h.esc(why) + "</b></p>" : "") +
        (r.first_name ? "<p>" + h.esc((r.first_name || "") + " " + (r.last_name || "")) + (r.ticket_type ? " · " + h.esc(r.ticket_type) : "") + "</p>" : "") +
        (r.event_name ? '<p class="tk-scansub">' + h.esc(r.event_name) + (ok ? " · ingecheckt om " + h.esc(hm(r.checked_in_at)) : "") + "</p>" : "") +
        (c.capacity ? '<p class="tk-scancount">' + Number(c.checked_in || 0) + " / " + Number(c.registered || 0) + " binnen · " + c.capacity + " plekken</p>" : "") + "</div>";
      var el = $("#tkRes", root); if (el) el.focus({ preventScroll: true });
      if (navigator.vibrate) navigator.vibrate(ok ? 40 : [60, 60, 60]);
      return r;
    });
  }
  function scanCard(root, h, zaak, code) {
    return h.rpc("pasr_business_member_card_scan", { p_business: zaak, p_code: code }, true).then(function (r) {
      if (r.result !== "valid") return r;
      function draw(m) {
        var d = m.discount_now, n = m.next_discount, s = m.saving;
        root.innerHTML = '<div class="tk-scanres mc ' + (d ? "ok" : "plain") + '" tabindex="-1" id="tkRes"><span class="tk-scanic">' + (d ? TKICON.pct : TKICON.mcard) + "</span>" +
          "<h3>" + (d ? h.esc(pct(d.percent)) + " korting" : "Geen korting vandaag") + "</h3>" +
          "<p><b>" + h.esc(m.member_name || "Lid") + "</b> · " + h.esc(m.card_name) + " · " + h.esc(m.number) + "</p>" +
          (d ? '<p class="tk-scansub">' + h.esc(d.label || "") + (d.until ? " · geldt tot " + h.esc(fmt(d.until, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })) : "") + "</p>"
             : n ? '<p class="tk-scansub">Volgende: ' + h.esc(dShort(n.starts_at) + " " + hm(n.starts_at)) + " · " + h.esc(n.label || pct(n.percent)) + "</p>" : "") +
          (s ? '<div class="mc-save scan"><span>' + (s.unit === "points" ? "Punten" : "Spaarstand") + '</span><span class="mc-sbar"><i style="width:' + Math.min(100, s.count / Math.max(1, s.target) * 100) + '%"></i></span><b>' + s.count + "/" + s.target + "</b></div>" : "") +
          '<div class="zk-actions">' + (s && s.unit === "points" ? '<label class="tk-points">Punten<input id="mcPts" type="number" min="1" max="1000" value="1"></label>' : "") +
          '<button class="zk-btn mint" type="button" id="mcVisit">' + h.ICON.check + "Bezoek registreren</button>" +
          (s ? '<button class="zk-btn coral" type="button" id="mcRedeem"' + (s.can_redeem ? "" : " disabled") + ">" + h.ICON.gift + "Beloning inwisselen</button>" : "") + "</div>" +
          '<p class="zk-msg" id="mcScanMsg" role="status"></p></div>';
        var v = $("#mcVisit", root);
        v.addEventListener("click", function () {
          v.disabled = true;
          var pts = $("#mcPts", root);
          h.rpc("pasr_business_member_card_visit", { p_business: zaak, p_code: m.number, p_points: pts ? Math.max(1, Number(pts.value) || 1) : 1 }, true).then(function (x) {
            m.saving = x.saving; draw(m); h.setMsg($("#mcScanMsg", root), "Bezoek geregistreerd", true);
          }).catch(function (e) { v.disabled = false; h.setMsg($("#mcScanMsg", root), err(e, h)); });
        });
        var rd = $("#mcRedeem", root);
        if (rd) rd.addEventListener("click", function () {
          if (!confirm("Beloning “" + (s.reward || "") + "” inwisselen?")) return;
          rd.disabled = true;
          h.rpc("pasr_business_member_card_redeem", { p_business: zaak, p_code: m.number }, true).then(function (x) {
            m.saving = x.saving; draw(m); h.setMsg($("#mcScanMsg", root), "Beloning ingewisseld", true);
          }).catch(function (e) { rd.disabled = false; h.setMsg($("#mcScanMsg", root), err(e, h)); });
        });
      }
      draw(r);
      var el = $("#tkRes", root); if (el) el.focus({ preventScroll: true });
      if (navigator.vibrate) navigator.vibrate(40);
      return r;
    });
  }
  /** Gescande of getypte code die geen stempelkaart (PZ) of kortingsbon (PC) is: eerst ticket, dan klantenkaart.
   *  Geeft true als hij is afgehandeld. */
  function scan(root, h, zaak, code, eventId) {
    code = String(code || "").replace(/\s+/g, "").toUpperCase();
    if (!zaak || !code) return Promise.resolve(false);
    var first = isTicket(code) ? scanTicket(root, h, zaak, code, eventId, false) : Promise.resolve(null);
    return first.then(function (r) {
      if (r) return true;
      return scanCard(root, h, zaak, code).then(function (m) {
        if (m && m.result === "valid") return true;
        if (isTicket(code)) return scanTicket(root, h, zaak, code, eventId, true).then(function () { return true; });
        root.innerHTML = '<div class="tk-scanres bad" tabindex="-1" id="tkRes"><span class="tk-scanic">' + TKICON.x + "</span><h3>Niet gevonden</h3><p>" +
          (m && m.result === "other_business" ? "Deze klantenkaart hoort bij een andere zaak." : "Geen ticket, klantenkaart of stempelkaart van je zaak.") + "</p></div>";
        return true;
      });
    });
  }
  function eventPicker(root, h, zaak, onPick, preset) {
    return h.rpc("pasr_business_events", { p_business: zaak }, true).then(function (rows) {
      var now = Date.now(), list = (rows || []).filter(function (e) { return e.status === "published" && Date.parse(e.ends_at) > now - 6 * 3600e3 && Date.parse(e.starts_at) < now + 7 * 864e5; });
      if (!list.length) return;
      root.hidden = false;
      root.innerHTML = '<label>Tickets scannen voor <select id="tkPick"><option value="">Elk event van je zaak</option>' + list.map(function (e) {
        return '<option value="' + h.esc(e.id) + '"' + (e.id === preset ? " selected" : "") + ">" + h.esc(e.name + " · " + dShort(e.starts_at) + " " + hm(e.starts_at)) + " (" + Number(e.checked_in || 0) + "/" + Number(e.registered || 0) + " binnen)</option>";
      }).join("") + "</select></label>";
      var sel = $("#tkPick", root); onPick(sel.value || null);
      sel.addEventListener("change", function () { onPick(sel.value || null); });
    }).catch(function () { /* scanner werkt ook zonder keuze */ });
  }

  function $(s, r) { return (r || document).querySelector(s); }
  window.PasrTK = { tickets: tickets, cards: cards, todo: todo, upcoming: upcoming, kpiTiles: kpiTiles, scan: scan, isTicket: isTicket, eventPicker: eventPicker,
    eventState: eventState, goalText: goalText, pct: pct, dShort: dShort, hm: hm, icon: TKICON };
})();
