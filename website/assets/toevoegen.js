/* "Voeg toe aan Pasr": terugvalpagina voor https://pasr.nl/add/<soort>/<id> (en /toevoegen/#<soort>/<id>).
   Opent de app niet vanzelf (geen Pasr geïnstalleerd, of de link werd in een app-browser geopend), dan toont deze pagina
   het item, de downloadknoppen en "Al geïnstalleerd? Open in Pasr". Gemaakt door tools/make_add.py. */
(function () {
  "use strict";
  var KINDS = { k: "Stempelkaart", c: "Kortingsbon", a: "Actiecode", t: "Ticket", g: "Cadeaukaart", s: "Klantenkaart" };
  var ID = /^[A-Za-z0-9][A-Za-z0-9-]{0,63}$/;
  var STORE = "pasr.add.pending";
  var $ = function (id) { return document.getElementById(id); };

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function hex(c, fb) { return /^#[0-9A-Fa-f]{6}$/.test(c || "") ? c : fb; }
  function light(c) { var r = parseInt(c.substr(1, 2), 16), g = parseInt(c.substr(3, 2), 16), b = parseInt(c.substr(5, 2), 16); return 0.2126 * r + 0.7152 * g + 0.0722 * b > 160; }
  function logoSrc(v) {
    if (!v || typeof v !== "string") return null;
    if (/^https:\/\//.test(v) || /^\/assets\//.test(v)) return v;
    if (/^(\/9j\/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$/.test(v) && v.length < 400000) return "data:image/" + (v.indexOf("/9j/") === 0 ? "jpeg" : "png") + ";base64," + v;
    return null;
  }
  function money(type, value) {
    var n = Number(value || 0);
    return type === "percent" ? n.toLocaleString("nl-NL") + "% korting" : new Intl.NumberFormat("nl-NL", { style: "currency", currency: "EUR" }).format(n) + " korting";
  }
  function store(get, value) {
    try {
      if (get) return JSON.parse(localStorage.getItem(STORE) || "null");
      localStorage.setItem(STORE, JSON.stringify(value));
    } catch (e) { return null; }
    return null;
  }

  // ---- welk item? /add/<soort>/<id>, /toevoegen/#<soort>/<id>, ?soort=&id=, of eerder onthouden
  function parse() {
    var m = location.pathname.match(/^\/add\/([kcatgs])\/([^/?#]+)\/?$/);
    if (!m) m = decodeURIComponent(location.hash.replace(/^#\/?/, "")).match(/^([kcatgs])\/([^/?#]+)$/);
    if (!m) {
      var q = new URLSearchParams(location.search);
      if (q.get("soort") && q.get("id")) m = [null, q.get("soort"), q.get("id")];
    }
    if (m && KINDS[m[1]] && ID.test(m[2])) return { k: m[1], id: /^[kca]$/.test(m[1]) ? m[2].toLowerCase() : m[2], fresh: true };
    var saved = store(true);
    if (saved && KINDS[saved.k] && ID.test(saved.id || "") && Date.now() - (saved.at || 0) < 30 * 864e5) return { k: saved.k, id: saved.id, fresh: false };
    return null;
  }

  function rpc(name, body) {
    var cfg = window.PASR_ACCOUNT || {};
    if (!cfg.url || !cfg.key) return Promise.reject(new Error("offline"));
    return fetch(cfg.url.replace(/\/$/, "") + "/rest/v1/rpc/" + name, {
      method: "POST", headers: { apikey: cfg.key, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(body || {})
    }).then(function (r) { if (!r.ok) throw new Error("http " + r.status); return r.json(); });
  }

  // ---- weergave van het item (zelfde opbouw als de kaarten in de app: kleur en logo van de zaak)
  function head(color, logo, title) {
    var img = logoSrc(logo);
    return '<div class="ta-head">' + (img ? '<img class="ta-logo" alt="" src="' + esc(img) + '">' : '<span class="ta-initial">' + esc(String(title || "?").trim().charAt(0).toUpperCase()) + "</span>") +
      '<span class="ta-brand">' + esc(title) + "</span></div>";
  }
  function stampCard(c) {
    var color = hex(c.color, "#6A5CFF"), total = Math.max(2, Math.min(30, Number(c.stamps_total) || 10)), dots = "";
    for (var i = 0; i < total; i++) dots += "<i></i>";
    return '<div class="ta-card" style="--c:' + color + (light(color) ? ";--t:#17162A" : "") + '">' + head(color, c.logo, c.business) +
      '<div class="ta-name">' + esc(c.name) + '</div><div class="ta-stamps' + (total > 12 ? " many" : "") + '">' + dots + "</div>" +
      (c.reward ? '<div class="ta-foot">Beloning: ' + esc(c.reward) + "</div>" : "") + "</div>";
  }
  function offerCard(o, label) {
    var color = hex(o.color, "#6A5CFF");
    return '<div class="ta-card ta-offer" style="--c:' + color + (light(color) ? ";--t:#17162A" : "") + '">' + head(color, o.logo, o.business) +
      '<div class="ta-big">' + esc(money(o.discount_type, o.discount_value)) + '</div><div class="ta-name">' + esc(o.title) + "</div>" +
      '<div class="ta-foot">' + esc(label) + (o.ends_at ? " · geldig t/m " + esc(new Date(o.ends_at).toLocaleDateString("nl-NL")) : "") + "</div></div>";
  }
  function storeCard(s, kind) {
    var color = hex(s.c, "#2B2F3A");
    return '<div class="ta-card' + (kind === "t" ? " ta-ticket" : "") + '" style="--c:' + color + (light(color) ? ";--t:#17162A" : "") + '">' +
      (s.l ? '<div class="ta-head ta-head-logo"><img class="ta-wordmark" alt="' + esc(s.n) + '" src="' + esc(s.l) + '"></div>' : head(color, null, s.n)) +
      '<div class="ta-name">' + esc(s.n) + '</div><div class="ta-foot">' + esc(KINDS[kind]) + "</div></div>";
  }

  function show(item, html, title, lead, extra) {
    $("ta-item").innerHTML = html;
    $("ta-title").textContent = title;
    $("ta-lead").innerHTML = lead + (extra || "");
    $("ta-open-wrap").hidden = false;
    document.title = title + " | Pasr";
  }
  function fail(item, msg) {
    $("ta-item").innerHTML = '<div class="ta-card ta-empty"><span>' + esc(KINDS[item.k]) + "</span></div>";
    $("ta-title").textContent = msg;
    $("ta-lead").textContent = "Vraag de zaak om een nieuwe link, of bekijk wat er in Pasr te vinden is.";
    $("ta-error").hidden = false;
    $("ta-error").innerHTML = '<a href="/kaarten/">Alle kaarten</a> · <a href="/stempelkaarten/">Stempelkaarten</a> · <a href="/kortingsbonnen/">Kortingsbonnen</a>';
    $("ta-open-wrap").hidden = true;
  }

  function load(item) {
    var name = KINDS[item.k].toLowerCase();
    if (item.k === "k") {
      return rpc("pasr_business_card", { p_card: item.id }).then(function (c) {
        if (!c || !c.id) return fail(item, "Deze stempelkaart is niet (meer) online");
        show(item, stampCard(c), "Voeg " + (c.name || "deze stempelkaart") + " toe aan Pasr",
          esc(c.business) + (c.city ? " in " + esc(c.city) : "") + ": spaar " + esc(c.stamps_total) + " stempels" + (c.reward ? " voor " + esc(c.reward) : "") + ". De zaak ziet alleen je spaarstand, geen naam of e-mail.",
          ' <a href="/zakelijk/kaart/' + esc(item.id) + '/">Liever in de browser sparen?</a>');
      });
    }
    if (item.k === "c" || item.k === "a") {
      var fn = item.k === "c" ? "pasr_business_coupon_list" : "pasr_business_promo_public";
      return rpc(fn, {}).then(function (rows) {
        var o = (Array.isArray(rows) ? rows : []).filter(function (r) { return String(r.id).toLowerCase() === item.id; })[0];
        if (!o) return fail(item, "Deze " + name + " is verlopen of niet gevonden");
        if (o.ends_at && new Date(o.ends_at) < new Date()) return fail(item, "Deze " + name + " is verlopen");
        show(item, offerCard(o, KINDS[item.k]), "Voeg deze " + name + " toe aan Pasr",
          esc(o.business) + ": " + esc(o.title) + ". In Pasr krijg je een persoonlijke code die je aan de kassa laat scannen; daarvoor heb je een gratis Pasr-account nodig.");
      });
    }
    return fetch("/toevoegen/winkels.json", { cache: "force-cache" }).then(function (r) { return r.json(); }).then(function (all) {
      var s = all && (all[item.id] || all[Object.keys(all).filter(function (k) { return k.toLowerCase() === item.id.toLowerCase(); })[0]]);
      if (!s) return fail(item, "Deze kaart staat niet (meer) in Pasr");
      var kind = item.k;
      show(item, storeCard(s, kind), "Voeg " + s.n + " toe aan Pasr",
        kind === "t" ? "Pasr zet je ticket in de stijl van het evenement klaar. Daarna scan je de code van je eigen, gekochte ticket."
          : kind === "g" ? "Pasr zet de cadeaukaart klaar met logo en kleur. Daarna scan of typ je het nummer en de pincode van je eigen kaart."
          : "Pasr zet de kaart klaar met logo en kleur. Daarna scan of typ je het nummer van je eigen kaart.",
        s.u ? ' <a href="' + esc(s.u) + '">Meer over ' + esc(s.n) + "</a>" : "");
    });
  }

  var item = parse();
  if (!item) {
    $("ta-title").textContent = "Geen kaart of bon in deze link";
    $("ta-lead").textContent = "Deze link is onvolledig. Open de link uit de mail, de website of de QR-code van de zaak opnieuw.";
    $("ta-item").innerHTML = '<div class="ta-card ta-empty"><span>pasr</span></div>';
    return;
  }
  var link = "https://pasr.nl/add/" + item.k + "/" + item.id;
  $("ta-kind").textContent = KINDS[item.k] + " · Voeg toe aan Pasr";
  $("ta-link").textContent = link;
  $("ta-open").href = "pasr://add/" + item.k + "/" + encodeURIComponent(item.id);
  if (!item.fresh) $("ta-kind").textContent = KINDS[item.k] + " · eerder bekeken";
  store(false, { k: item.k, id: item.id, at: Date.now() });
  if (store(true)) $("ta-saved").hidden = false;
  $("ta-copybtn").addEventListener("click", function () {
    var b = this;
    (navigator.clipboard ? navigator.clipboard.writeText(link) : Promise.reject()).then(function () { b.textContent = "Gekopieerd"; },
      function () { var r = document.createRange(); r.selectNodeContents($("ta-link")); var s = getSelection(); s.removeAllRanges(); s.addRange(r); });
  });
  $("ta-open").addEventListener("click", function () {
    // Opent Pasr niet (niet geïnstalleerd), dan blijft deze pagina staan: wijs dan op de downloadknoppen.
    setTimeout(function () {
      if (document.visibilityState === "visible") {
        $("ta-error").hidden = false;
        $("ta-error").textContent = "Opent Pasr niet? Installeer de app hieronder en open deze link daarna opnieuw.";
      }
    }, 1800);
  });
  load(item).catch(function () {
    $("ta-title").textContent = "Voeg dit item toe aan Pasr";
    $("ta-lead").textContent = "We konden het item nu niet ophalen. Open het in Pasr, of probeer het zo nog eens.";
    $("ta-item").innerHTML = '<div class="ta-card ta-empty"><span>' + esc(KINDS[item.k]) + "</span></div>";
    $("ta-open-wrap").hidden = false;
  });
})();
