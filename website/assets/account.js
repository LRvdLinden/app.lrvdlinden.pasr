// Pasr account on the website: confirm the e-mail address, choose a new password, create an account.
// Plain fetch to the account server (no SDK). The confirm links only work after a tap, so link scanners
// in mail programs can't use them up.
(function () {
  const cfg = window.PASR_ACCOUNT || {};
  const ready = !!(cfg.url && cfg.key);
  const $ = (s) => document.querySelector(s);
  const ICON = {
    mail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="m4 7 8 6 8-6"/></svg>',
    ok: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5 10 17 19 7"/></svg>',
    err: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 7v6M12 17h.01"/><circle cx="12" cy="12" r="10"/></svg>',
    key: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l3 3"/></svg>',
    user: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/></svg>',
  };

  async function call(path, body, token) {
    const headers = { "Content-Type": "application/json", apikey: cfg.key };
    if (token) headers.Authorization = "Bearer " + token;
    const res = await fetch(cfg.url + "/" + path, { method: path.startsWith("auth/v1/user") ? "PUT" : "POST", headers, body: JSON.stringify(body) });
    let data = {};
    try { data = await res.json(); } catch (_) {}
    if (!res.ok) { const e = new Error(data.msg || data.message || "error"); e.status = res.status; e.code = data.error_code || data.code || ""; throw e; }
    return data;
  }

  function nice(e) {
    if (e.code === "weak_password") return "Kies een wachtwoord van minstens 8 tekens.";
    if (e.status === 429) return "Even wachten: er zijn te veel pogingen gedaan. Probeer het over een paar minuten opnieuw.";
    if (e.code === "otp_expired" || e.status === 403) return "Deze link is verlopen of al gebruikt. Vraag in de app een nieuwe aan.";
    if (e.code === "user_already_exists" || e.code === "email_exists") return "Er is al een account met dit e-mailadres.";
    if (/permanent email/i.test(e.message)) return "Gebruik een vast e-mailadres; tijdelijke adressen werken niet.";
    if (e.code === "same_password") return "Kies een ander wachtwoord dan je huidige.";
    return "Er ging iets mis. Probeer het opnieuw.";
  }

  function card(kind, icon, title, text, inner) {
    const box = $("#auth");
    box.className = "auth" + (kind ? " " + kind : "");
    box.innerHTML = '<div class="badge">' + ICON[icon] + "</div><h1>" + title + "</h1><p>" + text + "</p>" + (inner || "");
  }

  function setMsg(text, good) { const m = $("#msg"); if (m) { m.textContent = text; m.className = "msg " + (good ? "good" : "bad"); } }

  // ---- pasr.nl/bevestigen/?token_hash=…&type=signup|recovery|email_change|magiclink ----
  function confirmPage() {
    const q = new URLSearchParams(location.search);
    const hash = q.get("token_hash"), type = q.get("type");
    if (!hash || !type) {
      return card("err", "err", "Deze link is niet compleet", "Open de link uit de mail opnieuw, of vraag in de Pasr-app een nieuwe mail aan.");
    }
    if (!ready) return card("err", "err", "Even niet beschikbaar", "Accounts zijn nog niet actief. Probeer het later opnieuw.");
    const isRecovery = type === "recovery";
    card("", isRecovery ? "key" : "mail",
      isRecovery ? "Nieuw wachtwoord kiezen" : type === "email_change" ? "Nieuw e-mailadres bevestigen" : "Bevestig je e-mailadres",
      isRecovery ? "Tik op de knop om verder te gaan en kies daarna een nieuw wachtwoord." : "Nog één tik en je Pasr-account is klaar.",
      '<form id="go"><button type="submit">' + (isRecovery ? "Verder" : "Bevestigen") + '</button><p class="msg" id="msg" role="status"></p></form>');
    $("#go").addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        const s = await call("auth/v1/verify", { type, token_hash: hash });
        history.replaceState(null, "", location.pathname);
        if (isRecovery) return newPassword(s.access_token);
        card("ok", "ok", "Gelukt!", type === "email_change" ? "Je nieuwe e-mailadres is bevestigd." : "Je e-mailadres is bevestigd. Ga terug naar Pasr en log in met je e-mailadres en wachtwoord.",
          '<p class="small">Je kunt dit venster sluiten.</p>');
      } catch (e) { btn.disabled = false; setMsg(nice(e)); }
    });
  }

  function newPassword(token) {
    card("", "key", "Kies een nieuw wachtwoord", "Minstens 8 tekens. Daarna log je in de app in met je nieuwe wachtwoord.",
      '<form id="pw"><label>Nieuw wachtwoord<input type="password" id="p1" autocomplete="new-password" minlength="8" required></label>' +
      '<label>Herhaal wachtwoord<input type="password" id="p2" autocomplete="new-password" minlength="8" required></label>' +
      '<button type="submit">Wachtwoord opslaan</button><p class="msg" id="msg" role="status"></p></form>');
    $("#pw").addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const a = $("#p1").value, b = $("#p2").value;
      if (a.length < 8) return setMsg("Kies een wachtwoord van minstens 8 tekens.");
      if (a !== b) return setMsg("De wachtwoorden zijn niet gelijk.");
      const btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        await call("auth/v1/user", { password: a }, token);
        card("ok", "ok", "Wachtwoord gewijzigd", "Log in de Pasr-app in met je nieuwe wachtwoord.", '<p class="small">Je kunt dit venster sluiten.</p>');
      } catch (e) { btn.disabled = false; setMsg(nice(e)); }
    });
  }

  // ---- pasr.nl/account/: account maken (met honeypot en tijdmeting) of wachtwoord vergeten ----
  function accountPage() {
    if (!ready) return card("err", "err", "Binnenkort", "Pasr-accounts komen binnenkort. Tot die tijd staan je kaarten in je eigen iCloud.");
    const mode = location.hash === "#vergeten" ? "forgot" : "signup";
    if (mode === "forgot") {
      card("", "key", "Wachtwoord vergeten", "Vul je e-mailadres in. Je krijgt een mail om een nieuw wachtwoord te kiezen.",
        '<form id="f"><label>E-mailadres<input type="email" id="email" autocomplete="email" required></label>' +
        '<button type="submit">Stuur mail</button><p class="msg" id="msg" role="status"></p></form>' +
        '<p class="switch"><a href="#">Nog geen account? Maak er een</a></p>');
      $("#f").addEventListener("submit", async (ev) => {
        ev.preventDefault();
        const btn = ev.target.querySelector("button"); btn.disabled = true;
        try {
          await call("auth/v1/recover?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email: $("#email").value.trim().toLowerCase() });
          setMsg("Als er een account met dit adres is, staat er nu een mail in je inbox.", true);
        } catch (e) { setMsg(nice(e)); } finally { btn.disabled = false; }
      });
      return;
    }
    const shown = performance.now();
    card("", "user", "Maak je Pasr-account", "Gratis. Al je klantenkaarten versleuteld in één account, op al je apparaten.",
      '<form id="f" novalidate><label>Voornaam<input id="name" autocomplete="given-name" maxlength="40" required></label>' +
      '<label>E-mailadres<input type="email" id="email" autocomplete="email" required></label>' +
      '<label>Wachtwoord<input type="password" id="pw" autocomplete="new-password" minlength="8" required></label>' +
      '<div class="hp-field" aria-hidden="true"><label>Laat dit veld leeg<input type="text" id="website" name="website" tabindex="-1" autocomplete="off"></label></div>' +
      '<button type="submit">Account maken</button><p class="msg" id="msg" role="status"></p>' +
      '<p class="small">Je krijgt een mail om je e-mailadres te bevestigen. Lees ook onze <a href="/privacy/">privacyverklaring</a>.</p></form>' +
      '<p class="switch"><a href="#vergeten">Wachtwoord vergeten?</a></p>');
    $("#f").addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const name = $("#name").value.replace(/[<>]/g, "").replace(/\s+/g, " ").trim().slice(0, 40);
      const email = $("#email").value.trim().toLowerCase(), pw = $("#pw").value, hp = $("#website").value;
      if (!name) return setMsg("Vul je voornaam in.");
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return setMsg("Dit e-mailadres klopt niet.");
      if (pw.length < 8) return setMsg("Kies een wachtwoord van minstens 8 tekens.");
      const data = { first_name: name, fill_ms: Math.round(performance.now() - shown), app: "web" };
      // regio van de browserinstelling (bv. nl-NL → NL), alleen voor de landentelling; geen locatie
      try { const r = new Intl.Locale(navigator.language || "").maximize().region; if (/^[A-Z]{2}$/.test(r || "")) data.country = r; } catch {}
      if (hp) data.hp = hp;
      const btn = ev.target.querySelector("button"); btn.disabled = true;
      try {
        await call("auth/v1/signup?redirect_to=" + encodeURIComponent("https://pasr.nl/bevestigen/"), { email, password: pw, data });
        card("ok", "mail", "Check je mail", "We hebben een mail gestuurd naar " + email.replace(/[<>&]/g, "") + ". Tik op de knop in die mail om je account te bevestigen en log daarna in de Pasr-app in.");
      } catch (e) { $("#website").value = ""; btn.disabled = false; setMsg(nice(e)); }
    });
  }

  window.addEventListener("hashchange", () => { if (document.body.dataset.page === "account") accountPage(); });
  document.body.dataset.page === "confirm" ? confirmPage() : accountPage();
})();
