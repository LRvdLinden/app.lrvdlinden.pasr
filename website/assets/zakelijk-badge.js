/* Pasr Zakelijk-dashboard: "Knop voor je website" bij elke online stempelkaart, kortingsbon en actiecode.
   Losse laag (zoals zakelijk-dashboard-v2.js): verandert geen gegevens en geen RPC's. Zoekt in het dashboard
   - online stempelkaarten: article.zk-card[data-id] met de pil "Online"  → https://pasr.nl/add/k/<id>
   - elementen met data-pasr-add="<soort>:<id>" (kortingsbonnen c, actiecodes a; loyalty2.js en promo-codes-business.js)
   en zet daar een knop bij. De dialoog geeft voorbeeld, HTML-snippet, link, PNG voor drukwerk en een QR-code.
   De knop is altijd Nederlands: "Voeg toe aan Pasr" (badges in /badge/nl/, tools/make_badges.py). */
(function () {
  "use strict";
  var THEMES = [["zwart", "Zwart"], ["wit", "Wit"], ["nachtblauw", "Nachtblauw"]];
  var SIZES = [["groot", "Groot", 52], ["compact", "Compact", 38]];
  var KIND = { k: "stempelkaart", c: "kortingsbon", a: "actiecode", t: "ticket", g: "cadeaukaart", s: "kaart" };
  var state = { theme: "zwart", size: "groot" };
  try { var saved = JSON.parse(localStorage.getItem("pasr.badge.choice") || "null"); if (saved && saved.theme) state = saved; } catch (e) { /* geen opslag */ }

  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function addUrl(kind, id) { return "https://pasr.nl/add/" + kind + "/" + (/^[kca]$/.test(kind) ? String(id).toLowerCase() : id); }
  function file() { return state.theme + (state.size === "compact" ? "-compact" : ""); }
  function height() { return state.size === "compact" ? 38 : 52; }
  function snippet(kind, id) {
    return '<a href="' + addUrl(kind, id) + '">\n  <img src="https://pasr.nl/badge/nl/' + file() + '.svg"\n       alt="Voeg toe aan Pasr" height="' + height() + '">\n</a>';
  }
  function slug(s) { return String(s || "pasr").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "pasr"; }
  function copy(text, btn) {
    var done = function () { var t = btn.textContent; btn.textContent = "Gekopieerd"; setTimeout(function () { btn.textContent = t; }, 1600); };
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () { fallback(); });
    else fallback();
    function fallback() { var ta = el("textarea"); ta.value = text; document.body.append(ta); ta.select(); try { document.execCommand("copy"); done(); } catch (e) { /* niets */ } ta.remove(); }
  }
  function qrCanvas(text, px) {
    if (typeof window.qrcode !== "function") return null;
    var q = window.qrcode(0, "M"); q.addData(text); q.make();
    var n = q.getModuleCount(), margin = 4, cell = Math.max(1, Math.floor(px / (n + margin * 2)));
    var c = document.createElement("canvas"); c.width = c.height = (n + margin * 2) * cell;
    var x = c.getContext("2d"); x.fillStyle = "#FFFFFF"; x.fillRect(0, 0, c.width, c.height); x.fillStyle = "#000000";
    for (var r = 0; r < n; r++) for (var k = 0; k < n; k++) if (q.isDark(r, k)) x.fillRect((k + margin) * cell, (r + margin) * cell, cell, cell);
    return c;
  }

  function style() {
    if (document.getElementById("pz-badge-css")) return;
    var s = el("style"); s.id = "pz-badge-css";
    s.textContent =
      ".pz-badge-btn{white-space:nowrap}" +
      ".pz-badge-dlg{border:0;padding:0;border-radius:24px;width:min(760px,calc(100vw - 24px));max-height:calc(100vh - 24px);background:var(--paper-2,#fff);color:var(--ink,#17162A);box-shadow:0 40px 90px -30px rgba(0,0,0,.55)}" +
      ".pz-badge-dlg::backdrop{background:rgba(14,13,24,.55)}" +
      ".pz-badge-in{padding:24px clamp(16px,4vw,30px) 26px;display:flex;flex-direction:column;gap:18px}" +
      ".pz-badge-top{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}.pz-badge-top h2{margin:0;font-size:24px}.pz-badge-top p{margin:4px 0 0;color:var(--ink-2,#4B4966)}" +
      ".pz-badge-x{border:0;background:var(--soft,#ECEAFB);color:inherit;width:38px;height:38px;border-radius:50%;font-size:20px;cursor:pointer;flex:none}" +
      ".pz-badge-opts{display:flex;flex-wrap:wrap;gap:12px 22px}.pz-badge-opts fieldset{border:0;margin:0;padding:0;display:flex;flex-direction:column;gap:6px}.pz-badge-opts legend{font-weight:700;font-size:13px;color:var(--ink-2,#4B4966);padding:0;margin-bottom:6px}" +
      ".pz-seg{display:inline-flex;background:var(--soft,#ECEAFB);border-radius:12px;padding:3px;gap:2px}.pz-seg button{border:0;background:transparent;color:inherit;font:inherit;font-weight:600;padding:8px 14px;border-radius:9px;cursor:pointer}.pz-seg button[aria-pressed=true]{background:var(--paper-2,#fff);box-shadow:0 1px 4px rgba(0,0,0,.15)}" +
      ".pz-badge-prev{display:grid;grid-template-columns:1fr 1fr;border-radius:16px;overflow:hidden;border:1px solid var(--line,#DCD9F2)}.pz-badge-prev div{display:flex;align-items:center;justify-content:center;min-height:110px;padding:14px}.pz-badge-prev .l{background:#fff}.pz-badge-prev .d{background:#17162A}.pz-badge-prev img{display:block;max-width:100%}" +
      ".pz-badge-code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;line-height:1.55;background:#17162A;color:#E9E7FF;border-radius:14px;padding:14px 16px;white-space:pre-wrap;word-break:break-all;margin:0}" +
      ".pz-badge-row{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.pz-badge-link{font-family:ui-monospace,Menlo,monospace;font-size:13px;overflow-wrap:anywhere;color:var(--ink-2,#4B4966)}" +
      ".pz-badge-qr{display:flex;gap:16px;align-items:center;flex-wrap:wrap}.pz-badge-qr canvas{width:132px;height:132px;border-radius:12px;border:1px solid var(--line,#DCD9F2);image-rendering:pixelated}.pz-badge-qr p{margin:0 0 8px;color:var(--ink-2,#4B4966);max-width:40ch}" +
      ".pz-badge-h{font-weight:800;font-size:15px;margin:0}" +
      "@media (max-width:560px){.pz-badge-prev{grid-template-columns:1fr}}";
    document.head.append(s);
  }

  function seg(list, key, onChange) {
    var wrap = el("div", "pz-seg"); wrap.setAttribute("role", "group");
    list.forEach(function (o) {
      var b = el("button", "", o[1]); b.type = "button"; b.dataset.v = o[0];
      b.setAttribute("aria-pressed", String(state[key] === o[0]));
      b.addEventListener("click", function () {
        state[key] = o[0];
        try { localStorage.setItem("pasr.badge.choice", JSON.stringify(state)); } catch (e) { /* geen opslag */ }
        wrap.querySelectorAll("button").forEach(function (x) { x.setAttribute("aria-pressed", String(x.dataset.v === o[0])); });
        onChange();
      });
      wrap.append(b);
    });
    return wrap;
  }

  function open(kind, id, name) {
    style();
    var dlg = el("dialog", "pz-badge-dlg"); dlg.setAttribute("aria-labelledby", "pz-badge-title");
    var box = el("div", "pz-badge-in"); dlg.append(box);
    var top = el("div", "pz-badge-top"), t = el("div"), h = el("h2", "", "Knop voor je website"); h.id = "pz-badge-title";
    t.append(h, el("p", "", "Klanten zetten je " + KIND[kind] + (name ? " “" + name + "”" : "") + " met één tik in Pasr. Zonder Pasr opent pasr.nl met de downloadknoppen."));
    var x = el("button", "pz-badge-x", "×"); x.type = "button"; x.setAttribute("aria-label", "Sluiten"); x.addEventListener("click", function () { dlg.close(); });
    top.append(t, x);
    var opts = el("div", "pz-badge-opts");
    var f1 = el("fieldset"), f2 = el("fieldset");
    f1.append(el("legend", "", "Kleur"), seg(THEMES, "theme", render));
    f2.append(el("legend", "", "Formaat"), seg(SIZES, "size", render));
    opts.append(f1, f2);
    var prev = el("div", "pz-badge-prev"), pl = el("div", "l"), pd = el("div", "d"); prev.append(pl, pd);
    prev.setAttribute("aria-label", "Voorbeeld op een lichte en een donkere achtergrond");
    var code = el("pre", "pz-badge-code");
    var actions = el("div", "pz-badge-row");
    var bCopy = el("button", "zk-btn sm", "Kopieer HTML-code"); bCopy.type = "button";
    var bLink = el("button", "zk-btn ghost sm", "Kopieer link"); bLink.type = "button";
    var aPng = el("a", "zk-btn ghost sm", "PNG voor drukwerk"); var aSvg = el("a", "zk-btn ghost sm", "SVG");
    actions.append(bCopy, bLink, aPng, aSvg);
    var link = el("div", "pz-badge-link", addUrl(kind, id));
    var qr = el("div", "pz-badge-qr"), qrText = el("div"), aQr = el("a", "zk-btn ghost sm", "QR-code downloaden (PNG)");
    qrText.append(el("p", "pz-badge-h", "QR-code voor toonbank en kassabon"), el("p", "", "Scannen met de camera opent dezelfde link: met Pasr meteen Toevoegen aan Pasr?, anders pasr.nl."), aQr);
    var canvas = qrCanvas(addUrl(kind, id), 900);
    if (canvas) { qr.append(canvas, qrText); aQr.href = canvas.toDataURL("image/png"); aQr.download = "pasr-qr-" + slug(name) + ".png"; }
    box.append(top, opts, prev, el("p", "pz-badge-h", "Zet deze code op je website"), code, actions, link, qr);
    bCopy.addEventListener("click", function () { copy(snippet(kind, id), bCopy); });
    bLink.addEventListener("click", function () { copy(addUrl(kind, id), bLink); });

    function img(theme) {
      var i = el("img"); i.alt = "Voeg toe aan Pasr"; i.height = height();
      i.src = "/badge/nl/" + theme + (state.size === "compact" ? "-compact" : "") + ".svg"; return i;
    }
    function render() {
      pl.replaceChildren(img(state.theme)); pd.replaceChildren(img(state.theme));
      code.textContent = snippet(kind, id);
      aPng.href = "/badge/nl/" + file() + "@3x.png"; aPng.download = "voeg-toe-aan-pasr-" + file() + ".png";
      aSvg.href = "/badge/nl/" + file() + ".svg"; aSvg.download = "voeg-toe-aan-pasr-" + file() + ".svg";
    }
    render();
    dlg.addEventListener("close", function () { dlg.remove(); });
    document.body.append(dlg);
    if (dlg.showModal) dlg.showModal(); else dlg.setAttribute("open", "");
    return dlg;
  }
  window.PasrAddBadge = { open: open, url: addUrl, snippet: snippet };

  // ---- knoppen in het dashboard
  function button(kind, id, name) {
    var b = el("button", "zk-btn ghost sm pz-badge-btn", "Knop voor je website"); b.type = "button";
    b.dataset.pzBadge = kind + ":" + id;
    b.addEventListener("click", function () { open(kind, id, name); });
    return b;
  }
  function install() {
    var app = document.getElementById("zk-app"); if (!app) return;
    app.querySelectorAll("article.zk-card[data-id]").forEach(function (card) {
      if (card.querySelector(".pz-badge-btn") || !card.querySelector(".zk-pill.on")) return;
      var row = card.querySelector(".zk-actions"); if (!row) return;
      var h = card.querySelector("h3");
      row.append(button("k", card.dataset.id, h ? h.textContent : ""));
    });
    app.querySelectorAll("[data-pasr-add]").forEach(function (item) {
      if (item.querySelector(".pz-badge-btn")) return;
      var m = String(item.dataset.pasrAdd).match(/^([kcatgs]):([A-Za-z0-9-]{1,64})$/); if (!m) return;
      var row = item.querySelector(".zk-actions") || item;
      row.append(button(m[1], m[2], item.dataset.pasrAddName || ""));
    });
  }
  if (document.body.dataset.page !== "zk-dashboard") return;
  var app = document.getElementById("zk-app"); if (!app) return;
  var scheduled = false;
  new MutationObserver(function () { if (!scheduled) { scheduled = true; requestAnimationFrame(function () { scheduled = false; install(); }); } })
    .observe(app, { childList: true, subtree: true });
  install();
})();
