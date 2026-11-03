// Cookiemelding (AVG/ePrivacy), zoals op weekdot.com en bingr.online. Noodzakelijke opslag (alleen deze keuze) staat
// altijd aan. De lettertypen van Google Fonts (een derde partij) laden pas na "Accepteren". De keuze blijft 12 maanden.
(function () {
  "use strict";
  var KEY = "pasr_consent", MAX = 365 * 24 * 3600, MAX_MS = MAX * 1000;
  var FONTS = "https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Figtree:wght@400;500;600&display=swap";
  var T = {
    title: "Cookies op pasr.nl",
    text: "We gebruiken geen tracking en geen advertenties. Alleen als je akkoord gaat, laden we de lettertypen van Google Fonts; anders gebruikt je browser zijn eigen letter. Je keuze bewaren we 12 maanden.",
    more: "Meer in de privacyverklaring",
    accept: "Accepteren",
    necessary: "Alleen noodzakelijk",
    settings: "Cookie-instellingen",
  };
  function valid(v) { return v && (v.choice === "all" || v.choice === "necessary") && !(Date.now() - Date.parse(v.at) > MAX_MS); }
  function read() {
    try { var v = JSON.parse(localStorage.getItem(KEY)); if (valid(v)) return v; } catch (e) {}
    var m = document.cookie.match(/(?:^|; )pasr_consent=([^;]+)/);
    if (m) { try { var c = JSON.parse(decodeURIComponent(m[1])); if (valid(c)) return c; } catch (e) {} }
    return null;
  }
  function save(choice) {
    var v = { choice: choice, at: new Date().toISOString(), v: 1 };
    try { localStorage.setItem(KEY, JSON.stringify(v)); } catch (e) {}
    try {
      document.cookie = KEY + "=" + encodeURIComponent(JSON.stringify(v)) + "; Max-Age=" + MAX + "; Path=/; SameSite=Lax" +
        (location.protocol === "https:" ? "; Secure" : "");
    } catch (e) {}
    return v;
  }
  function fonts() {
    if (document.getElementById("pasr-fonts")) return;
    var l = document.createElement("link"); l.id = "pasr-fonts"; l.rel = "stylesheet"; l.href = FONTS;
    document.head.appendChild(l);
  }
  var COOKIE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.3A9 9 0 1 1 11.7 3a3 3 0 0 0 3.8 3.8 3 3 0 0 0 3.7 3.7 3 3 0 0 0 1.8 1.8z"/><circle cx="8.5" cy="10.5" r="1" fill="currentColor"/><circle cx="12" cy="15.5" r="1" fill="currentColor"/><circle cx="16" cy="14" r="1" fill="currentColor"/><circle cx="8" cy="15" r=".6" fill="currentColor"/></svg>';

  function banner() {
    if (document.getElementById("pasr-consent")) return;
    var prev = document.activeElement;
    var d = document.createElement("div");
    d.id = "pasr-consent"; d.setAttribute("role", "dialog"); d.setAttribute("aria-modal", "false");
    d.setAttribute("aria-labelledby", "pasr-consent-t"); d.setAttribute("aria-describedby", "pasr-consent-p"); d.tabIndex = -1;
    d.innerHTML = '<div class="t" id="pasr-consent-t">' + T.title + "</div>" +
      '<p id="pasr-consent-p">' + T.text + ' <a href="/privacy/#cookies">' + T.more + "</a></p>" +
      '<div class="b"><button type="button" class="y">' + T.accept + '</button><button type="button" class="n">' + T.necessary + "</button></div>";
    function close(choice) {
      save(choice); if (choice === "all") fonts();
      var hadFocus = d.contains(document.activeElement);
      d.remove(); showBubble(true);
      if (hadFocus) {
        var back = prev && prev !== document.body && document.contains(prev) ? prev : document.getElementById("pasr-cookie-btn");
        if (back && back.focus) try { back.focus({ preventScroll: true }); } catch (e) { back.focus(); }
      }
    }
    d.querySelector(".y").onclick = function () { close("all"); };
    d.querySelector(".n").onclick = function () { close("necessary"); };
    (document.body || document.documentElement).appendChild(d);
    try { d.focus({ preventScroll: true }); } catch (e) { d.focus(); }
  }
  // rond koekje linksonder (als er een keuze is): tik = melding opnieuw
  function bubble() {
    if (document.getElementById("pasr-cookie-btn")) return;
    var b = document.createElement("button"); b.id = "pasr-cookie-btn"; b.type = "button";
    b.title = T.settings; b.setAttribute("aria-label", T.settings); b.innerHTML = COOKIE;
    b.onclick = function () { open(); };
    (document.body || document.documentElement).appendChild(b);
  }
  function showBubble(on) { var b = document.getElementById("pasr-cookie-btn"); if (on) bubble(); else if (b) b.remove(); }
  function open() { var x = document.getElementById("pasr-consent"); if (x) x.remove(); showBubble(false); banner(); }

  window.PasrConsent = { open: open, get: read };
  var c = read();
  if (c && c.choice === "all") fonts();
  function start() {
    if (c) bubble(); else banner();
    // voettekst "Cookie-instellingen" (zonder JavaScript: /privacy/#cookies)
    Array.prototype.forEach.call(document.querySelectorAll("[data-consent-open]"), function (a) {
      a.addEventListener("click", function (e) { e.preventDefault(); open(); });
    });
  }
  var started = false;
  function go() { if (!started) { started = true; start(); } }
  if (document.readyState !== "loading") go(); else document.addEventListener("DOMContentLoaded", go);
})();
