// /kaarten/: zoeken (ook op aliassen), soort kaart, categorie; daarna de live catalogus erbij (terugval: de gegenereerde lijst).
(function () {
  'use strict';
  var cfgEl = document.getElementById('kaarten-config');
  var cfg = {};
  try { cfg = JSON.parse(cfgEl ? cfgEl.textContent : '{}'); } catch (e) { cfg = {}; }

  var q = document.getElementById('kf-q');
  var cat = document.getElementById('kf-cat');
  var catWrap = cat && cat.parentNode;
  var status = document.getElementById('kf-status');
  var other = document.getElementById('kf-other');
  var empty = document.getElementById('kg-empty');
  var blocks = {};
  Array.prototype.forEach.call(document.querySelectorAll('.kg-block'), function (b) { blocks[b.getAttribute('data-kind')] = b; });
  if (!q || !blocks.loyalty || !blocks.voucher) return;

  var LABEL = { loyalty: ['klantenkaart', 'klantenkaarten'], voucher: ['cadeaukaart of voucher', 'cadeaukaarten en vouchers'] };
  var kind = 'loyalty';
  var allOptions = Array.prototype.map.call(cat.options, function (o) { return o.value; }).filter(Boolean);
  var cats = cfg.cats || {};

  function fold(s) {
    s = String(s || '').toLowerCase();
    if (s.normalize) s = s.normalize('NFKD').replace(/[̀-ͯ]/g, '');
    return s;
  }
  function compact(s) { return s.replace(/[^a-z0-9]+/g, ''); }

  function tiles(k) { return blocks[k].querySelectorAll('.kc'); }
  function live(li) { return !li.hasAttribute('data-gone'); }

  function matches(li, needle, needle2) {
    if (!needle) return true;
    var hay = li.getAttribute('data-q') || '';
    return hay.indexOf(needle) !== -1 || (needle2.length > 1 && compact(hay).indexOf(needle2) !== -1);
  }

  // Alleen de categorieën die bij de gekozen soort horen; bij één categorie geen keuze tonen.
  function syncCategories() {
    var list = (cats[kind] || allOptions).slice();
    var keep = cat.value;
    while (cat.options.length > 1) cat.remove(1);
    list.forEach(function (c) { var o = document.createElement('option'); o.value = c; o.textContent = c; cat.appendChild(o); });
    cat.value = list.indexOf(keep) !== -1 ? keep : '';
    catWrap.hidden = list.length < 2;
  }

  function count(k) {
    var n = 0;
    Array.prototype.forEach.call(tiles(k), function (li) { if (live(li)) n++; });
    return n;
  }

  function apply() {
    var needle = fold(q.value).trim();
    var needle2 = compact(needle);
    var c = cat.value;
    var shown = 0, otherHits = 0;
    ['loyalty', 'voucher'].forEach(function (k) {
      var on = k === kind;
      blocks[k].classList.toggle('off', !on);
      Array.prototype.forEach.call(tiles(k), function (li) {
        var ok = live(li) && matches(li, needle, needle2);
        if (on) {
          ok = ok && (!c || li.getAttribute('data-c') === c);
          li.hidden = !ok;
          if (ok) shown++;
        } else if (ok && needle) {
          otherHits++;
        }
      });
    });
    var total = count(kind);
    var words = LABEL[kind];
    if (needle || c) {
      status.textContent = shown === 1 ? '1 ' + words[0] + ' gevonden' : shown + ' ' + words[1] + ' gevonden';
    } else {
      status.textContent = total + ' ' + words[1] + ', van A tot Z';
    }
    empty.hidden = shown !== 0;
    if (otherHits) {
      var ok = kind === 'loyalty';
      other.innerHTML = '';
      other.appendChild(document.createTextNode((ok ? 'Er is ook een cadeaukaart' : 'Er is ook een klantenkaart') + ' voor deze zoekterm. '));
      var b = document.createElement('b');
      b.textContent = ok ? 'Toon cadeaukaarten' : 'Toon klantenkaarten';
      other.appendChild(b);
      other.hidden = false;
    } else {
      other.hidden = true;
    }
  }

  function setKind(k) {
    kind = k;
    var r = document.getElementById(k === 'voucher' ? 'kf-voucher' : 'kf-loyalty');
    if (r && !r.checked) r.checked = true;
    syncCategories();
    apply();
  }

  // ?soort=cadeaukaarten en ?q= in het adres, zodat je een gefilterde lijst kunt delen
  try {
    var params = new URLSearchParams(location.search);
    if (/^cadeau|^voucher/.test(params.get('soort') || '')) kind = 'voucher';
    if (params.get('q')) q.value = params.get('q');
  } catch (e) { /* oude browser: niets */ }
  try { if (location.hash === '#cadeaukaarten') kind = 'voucher'; } catch (e) { /* niets */ }

  var timer;
  q.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(apply, 60); });
  q.addEventListener('keydown', function (e) { if (e.key === 'Escape') { q.value = ''; apply(); } });
  cat.addEventListener('change', apply);
  Array.prototype.forEach.call(document.querySelectorAll('.kf-kind input'), function (r) {
    r.addEventListener('change', function () { if (r.checked) setKind(r.value); });
  });
  other.addEventListener('click', function () { setKind(kind === 'loyalty' ? 'voucher' : 'loyalty'); q.focus(); });
  setKind(kind);

  // ---- Live catalogus: winkels die in het beheer zijn bijgekomen ------------------------------------------------
  function setCounts() {
    ['loyalty', 'voucher'].forEach(function (k) {
      var n = String(count(k));
      Array.prototype.forEach.call(document.querySelectorAll('[data-count="' + k + '"]'), function (el) { el.textContent = n; });
      var t = blocks[k].querySelector('.kg-title span');
      if (t) t.textContent = '(' + n + ')';
    });
  }

  function isLight(hex) {
    var m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
    if (!m) return false;
    var v = parseInt(m[1], 16);
    return 0.2126 * (v >> 16 & 255) + 0.7152 * (v >> 8 & 255) + 0.0722 * (v & 255) > 160;
  }

  var GIFT = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10h16v10H4zM3 7h18v3H3zM12 7v13M12 7c-1.5-3-5-3-5-1s3 1 5 1c2 0 5 1 5-1s-3.5-2-5 1" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  function saldoLink(name, url) {
    var a = document.createElement('a');
    a.className = 'kc-saldo';
    a.href = url; a.target = '_blank'; a.rel = 'noopener nofollow';
    a.setAttribute('aria-label', 'Saldo-check van ' + name + ' (opent de site van de uitgever)');
    a.innerHTML = GIFT;
    a.appendChild(document.createTextNode('Saldo-check'));
    return a;
  }

  function safeUrl(u) { return typeof u === 'string' && /^https:\/\/[^\s"'<>]+$/.test(u) ? u : null; }

  function makeTile(s, balance) {
    var li = document.createElement('li');
    li.className = 'kc new';
    li.setAttribute('data-id', s.id);
    li.setAttribute('data-src', 'catalogus');
    li.setAttribute('data-c', s.category || 'Overig');
    li.setAttribute('data-q', [s.name].concat(s.aliases || [], s.domain || '').map(fold).join(' '));
    var hex = /^#[0-9a-f]{6}$/i.test(s.card_hex || '') ? s.card_hex : '#2B2F3A';
    var card = document.createElement('div');
    card.className = 'kc-card' + (isLight(hex) ? ' ink-dark' : '');
    card.style.background = hex;
    if (s.logo && /^[A-Za-z0-9+/=\s]+$/.test(s.logo)) {
      var box = document.createElement('span');
      box.className = 'kc-logo';
      var img = document.createElement('img');
      img.alt = ''; img.decoding = 'async';
      img.src = 'data:image/png;base64,' + s.logo.replace(/\s+/g, '');
      box.appendChild(img); card.appendChild(box);
    } else {
      var w = document.createElement('span');
      w.className = 'kc-word'; w.setAttribute('aria-hidden', 'true'); w.textContent = s.name;
      card.appendChild(w);
    }
    if (s.kind === 'voucher' && balance) card.appendChild(saldoLink(s.name, balance));
    var name = document.createElement('span');
    name.className = 'kc-name'; name.textContent = s.name;
    li.appendChild(card); li.appendChild(name);
    return li;
  }

  function insertSorted(list, li) {
    var key = fold(li.querySelector('.kc-name').textContent);
    var items = list.querySelectorAll('.kc');
    for (var i = 0; i < items.length; i++) {
      var other = fold(items[i].querySelector('.kc-name').textContent);
      if ((other.localeCompare ? other.localeCompare(key, 'nl') : (other > key ? 1 : -1)) > 0) { list.insertBefore(li, items[i]); return; }
    }
    list.appendChild(li);
  }

  function merge(json) {
    if (!json || !Array.isArray(json.stores)) return;
    var pages = json.balance_pages && typeof json.balance_pages === 'object' ? json.balance_pages : {};
    var seen = {};
    json.stores.forEach(function (s) {
      if (!s || typeof s.id !== 'string' || s.removed || !s.name) return;
      seen[s.id] = true;
      if (!s.domain) return;   // geen winkel ("eigen kaart")
      var k = s.kind === 'voucher' ? 'voucher' : 'loyalty';
      var existing = document.querySelectorAll('.kc[data-id="' + s.id.replace(/[^a-z0-9-]/g, '') + '"]');
      if (existing.length) { Array.prototype.forEach.call(existing, function (li) { li.removeAttribute('data-gone'); }); return; }
      var c = s.category || 'Overig';
      if (!cats[k]) cats[k] = [];
      if (cats[k].indexOf(c) === -1) { cats[k].push(c); cats[k].sort(function (a, b) { return a.localeCompare(b, 'nl'); }); }
      insertSorted(blocks[k].querySelector('.kg'), makeTile(s, safeUrl(pages[s.id])));
    });
    // Catalogus-winkels uit de repo die live (nog) niet gepubliceerd zijn: niet tonen.
    Array.prototype.forEach.call(document.querySelectorAll('.kc[data-src="catalogus"]'), function (li) {
      if (!seen[li.getAttribute('data-id')]) li.setAttribute('data-gone', '');
    });
    // Saldo-pagina's die in het beheer zijn bijgekomen
    Array.prototype.forEach.call(blocks.voucher.querySelectorAll('.kc'), function (li) {
      var url = safeUrl(pages[li.getAttribute('data-id')]);
      var card = li.querySelector('.kc-card');
      if (url && card && !card.querySelector('.kc-saldo')) card.appendChild(saldoLink(li.querySelector('.kc-name').textContent, url));
    });
    setCounts();
    syncCategories();
    apply();
  }

  function rpc(name, body) {
    var ctrl = window.AbortController ? new AbortController() : null;
    var t = ctrl ? setTimeout(function () { ctrl.abort(); }, 8000) : 0;
    return fetch(cfg.url.replace(/\/$/, '') + '/rest/v1/rpc/' + name, {
      method: 'POST',
      headers: { 'apikey': cfg.key, 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify(body || {}),
      credentials: 'omit',
      signal: ctrl ? ctrl.signal : undefined
    }).then(function (r) { clearTimeout(t); return r.ok ? r.json() : null; },
            function () { clearTimeout(t); return null; });
  }

  // Logo's los ophalen (pasr_store_logos, hoogstens 40 per keer) voor nieuwe winkels en winkels die sinds het maken
  // van deze pagina zijn gewijzigd. Zo blijft de lijst zelf klein (pasr_store_index levert geen logo's).
  function loadLogos(ids) {
    for (var i = 0; i < ids.length; i += 40) {
      rpc('pasr_store_logos', { p_ids: ids.slice(i, i + 40) }).then(function (logos) {
        if (!logos || typeof logos !== 'object') return;
        Object.keys(logos).forEach(function (id) {
          var b64 = logos[id];
          if (typeof b64 !== 'string' || !/^[A-Za-z0-9+/=\s]+$/.test(b64)) return;
          Array.prototype.forEach.call(document.querySelectorAll('.kc[data-id="' + id.replace(/[^a-z0-9-]/g, '') + '"] .kc-card'), function (card) {
            var word = card.querySelector('.kc-word'), box = card.querySelector('.kc-logo'), img = box && box.querySelector('img');
            if (!img) {
              box = document.createElement('span'); box.className = 'kc-logo';
              img = document.createElement('img'); img.alt = ''; img.decoding = 'async';
              box.appendChild(img);
              card.insertBefore(box, card.firstChild);
            }
            img.removeAttribute('width'); img.removeAttribute('height');
            img.src = 'data:image/png;base64,' + b64.replace(/\s+/g, '');
            if (word) word.remove();
          });
        });
      });
    }
  }

  function fetchCatalog() {
    if (!cfg.url || !cfg.key || !window.fetch || !window.JSON) return;
    rpc('pasr_store_index').then(function (json) {
      if (!json || !Array.isArray(json.stores)) return;   // offline of geblokkeerd: de gegenereerde lijst blijft staan
      var built = Date.parse(cfg.built || '') || 0, need = [];
      json.stores.forEach(function (s) {
        if (!s || typeof s.id !== 'string' || s.removed || !s.has_logo) return;
        var known = document.querySelector('.kc[data-id="' + s.id.replace(/[^a-z0-9-]/g, '') + '"]');
        if (!known || (built && Date.parse(s.updated_at || '') > built)) need.push(s.id);
      });
      merge(json);
      if (need.length) loadLogos(need);
    });
  }
  if ('requestIdleCallback' in window) requestIdleCallback(fetchCatalog, { timeout: 2000 }); else setTimeout(fetchCatalog, 300);
})();
