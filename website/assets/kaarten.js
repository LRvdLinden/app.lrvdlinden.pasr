// /kaarten/: zoeken (ook op aliassen), soort kaart (klantenkaarten, cadeaukaarten en vouchers, stempelkaarten), categorie.
// Daarna de live gegevens uit de database erbij, zodat de pagina altijd overeenkomt met het beheer (terugval: de
// gegenereerde lijst): winkels erbij of weg, naam, kleur en logo bijgewerkt, kaartontwerpen, saldo-pagina's, en de
// stempelkaarten van zaken (pasr_business_directory). De demo-zaak voor App Review komt er nooit op.
(function () {
  'use strict';
  var cfgEl = document.getElementById('kaarten-config');
  var cfg = {};
  try { cfg = JSON.parse(cfgEl ? cfgEl.textContent : '{}'); } catch (e) { cfg = {}; }

  var KINDS = ['loyalty', 'voucher', 'stamp'];
  var q = document.getElementById('kf-q');
  var cat = document.getElementById('kf-cat');
  var catWrap = cat && cat.parentNode;
  var status = document.getElementById('kf-status');
  var other = document.getElementById('kf-other');
  var empty = document.getElementById('kg-empty');
  var stampEmpty = document.getElementById('ks-empty');
  var blocks = {};
  Array.prototype.forEach.call(document.querySelectorAll('.kg-block'), function (b) { blocks[b.getAttribute('data-kind')] = b; });
  if (!q || !blocks.loyalty || !blocks.voucher) return;
  if (!blocks.stamp) KINDS = ['loyalty', 'voucher'];

  var LABEL = {
    loyalty: ['klantenkaart', 'klantenkaarten', 'Er is ook een klantenkaart', 'Toon klantenkaarten'],
    voucher: ['cadeaukaart of voucher', 'cadeaukaarten en vouchers', 'Er is ook een cadeaukaart', 'Toon cadeaukaarten'],
    stamp: ['stempelkaart', 'stempelkaarten', 'Er is ook een stempelkaart', 'Toon stempelkaarten']
  };
  var kind = 'loyalty';
  var couponBlock = blocks.coupon;
  if (couponBlock && window.PasrLoyalty2) window.PasrLoyalty2.publicPage(document.getElementById('pz2Public'));

  var allOptions = Array.prototype.map.call(cat.options, function (o) { return o.value; }).filter(Boolean);
  var cats = cfg.cats || {};
  cats.stamp = [];

  function fold(s) {
    s = String(s || '').toLowerCase();
    if (s.normalize) s = s.normalize('NFKD').replace(/[̀-ͯ]/g, '');
    return s;
  }
  function compact(s) { return s.replace(/[^a-z0-9]+/g, ''); }
  function cssId(id) { return String(id || '').toLowerCase().replace(/[^a-z0-9-]/g, ''); }
  function each(list, fn) { Array.prototype.forEach.call(list, fn); }

  function tiles(k) { return blocks[k].querySelectorAll('.kc'); }
  function live(li) { return !li.hasAttribute('data-gone'); }

  function matches(li, needle, needle2) {
    if (!needle) return true;
    var hay = li.getAttribute('data-q') || '';
    return hay.indexOf(needle) !== -1 || (needle2.length > 1 && compact(hay).indexOf(needle2) !== -1);
  }

  // Alleen de categorieën die bij de gekozen soort horen; bij één categorie (of stempelkaarten) geen keuze tonen.
  function syncCategories() {
    var list = kind === 'coupon' ? [] : (cats[kind] || allOptions).slice();
    var keep = cat.value;
    while (cat.options.length > 1) cat.remove(1);
    list.forEach(function (c) { var o = document.createElement('option'); o.value = c; o.textContent = c; cat.appendChild(o); });
    cat.value = list.indexOf(keep) !== -1 ? keep : '';
    catWrap.hidden = list.length < 2;
  }

  function count(k) {
    var n = 0;
    each(tiles(k), function (li) { if (live(li)) n++; });
    return n;
  }

  function apply() {
    var needle = fold(q.value).trim();
    var needle2 = compact(needle);
    var c = kind === 'stamp' || kind === 'coupon' ? '' : cat.value;
    var shown = 0, hits = {};
    KINDS.forEach(function (k) {
      var on = k === kind;
      blocks[k].classList.toggle('off', !on);
      each(tiles(k), function (li) {
        var ok = live(li) && matches(li, needle, needle2);
        if (on) {
          ok = ok && (!c || li.getAttribute('data-c') === c);
          li.hidden = !ok;
          if (ok) shown++;
        } else if (ok && needle) {
          hits[k] = (hits[k] || 0) + 1;
        }
      });
    });
    if (couponBlock) {
      couponBlock.classList.toggle('off', kind !== 'coupon');
      if (kind === 'coupon') {
        var embeddedSearch = document.getElementById('pz2Search');
        if (embeddedSearch && embeddedSearch.value !== q.value) {
          embeddedSearch.value = q.value;
          embeddedSearch.dispatchEvent(new Event('input', { bubbles:true }));
        }
        status.textContent = 'Tijdelijke kortingsbonnen van Pasr-ondernemers';
        other.hidden = true;
        empty.hidden = true;
        if (stampEmpty) stampEmpty.hidden = true;
        return;
      }
    }
    var total = count(kind);
    var words = LABEL[kind];
    if (needle || c) {
      status.textContent = shown === 1 ? '1 ' + words[0] + ' gevonden' : shown + ' ' + words[1] + ' gevonden';
    } else if (kind === 'stamp') {
      status.textContent = total === 0 ? '' : (total === 1 ? '1 stempelkaart' : total + ' stempelkaarten') + ', van A tot Z';
    } else {
      status.textContent = total + ' ' + words[1] + ', van A tot Z';
    }
    // Lege staat: bij stempelkaarten zonder enige kaart de eigen melding, anders "geen kaart gevonden".
    var noStamps = kind === 'stamp' && total === 0;
    if (stampEmpty) stampEmpty.hidden = !noStamps;
    empty.hidden = shown !== 0 || noStamps;
    var otherKind = null;
    KINDS.forEach(function (k) { if (!otherKind && k !== kind && hits[k]) otherKind = k; });
    if (otherKind) {
      other.innerHTML = '';
      other.setAttribute('data-kind', otherKind);
      other.appendChild(document.createTextNode(LABEL[otherKind][2] + ' voor deze zoekterm. '));
      var b = document.createElement('b');
      b.textContent = LABEL[otherKind][3];
      other.appendChild(b);
      other.hidden = false;
    } else {
      other.hidden = true;
    }
  }

  function setKind(k) {
    if (!blocks[k]) k = 'loyalty';
    kind = k;
    var r = document.getElementById('kf-' + k);
    if (r && !r.checked) r.checked = true;
    syncCategories();
    apply();
  }

  // ?soort=cadeaukaarten|stempelkaarten en ?q= in het adres, zodat je een gefilterde lijst kunt delen
  try {
    var params = new URLSearchParams(location.search);
    var soort = params.get('soort') || '';
    if (/^cadeau|^voucher/.test(soort)) kind = 'voucher';
    if (/^stempel/.test(soort)) kind = 'stamp';
    if (/^korting|^coupon|^bonnen/.test(soort)) kind = 'coupon';
    if (params.get('q')) q.value = params.get('q');
  } catch (e) { /* oude browser: niets */ }
  try {
    if (location.hash === '#cadeaukaarten') kind = 'voucher';
    if (location.hash === '#stempelkaarten') kind = 'stamp';
    if (location.hash === '#kortingsbonnen') kind = 'coupon';
  } catch (e) { /* niets */ }

  var timer;
  q.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(apply, 60); });
  q.addEventListener('keydown', function (e) { if (e.key === 'Escape') { q.value = ''; apply(); } });
  cat.addEventListener('change', apply);
  each(document.querySelectorAll('.kf-kind input'), function (r) {
    r.addEventListener('change', function () { if (r.checked) setKind(r.value); });
  });
  other.addEventListener('click', function () { setKind(other.getAttribute('data-kind') || 'loyalty'); q.focus(); });
  setKind(kind);

  // ---- Live gegevens uit de database ------------------------------------------------------------------------------
  function setCounts() {
    KINDS.forEach(function (k) {
      var n = String(count(k));
      each(document.querySelectorAll('[data-count="' + k + '"]'), function (el) { el.textContent = n; });
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
  function hexOr(h, d) { return /^#[0-9a-f]{6}$/i.test(h || '') ? h : d; }
  function b64ok(s) { return typeof s === 'string' && /^[A-Za-z0-9+/=\s]+$/.test(s); }
  function imgOk(s) { return typeof s === 'string' && /^(\/9j\/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$/.test(s); }
  function dataUrl(b64) { return (b64.charAt(0) === '/' ? 'data:image/jpeg;base64,' : 'data:image/png;base64,') + b64.replace(/\s+/g, ''); }

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

  function setWord(card, name) {
    var w = card.querySelector('.kc-word');
    if (!w) {
      if (card.querySelector('.kc-logo img')) return;
      w = document.createElement('span');
      w.className = 'kc-word'; w.setAttribute('aria-hidden', 'true');
      card.appendChild(w);
    }
    w.textContent = name;
  }

  function makeTile(s, balance) {
    var li = document.createElement('li');
    li.className = 'kc new';
    li.setAttribute('data-id', cssId(s.id));
    li.setAttribute('data-c', s.category || 'Overig');
    li.setAttribute('data-q', [s.name].concat(s.aliases || [], s.domain || '').map(fold).join(' '));
    var hex = hexOr(s.card_hex, '#2B2F3A');
    var card = document.createElement('div');
    card.className = 'kc-card' + (isLight(hex) ? ' ink-dark' : '');
    card.style.background = hex;
    setWord(card, s.name);
    if (s.kind === 'voucher' && balance) card.appendChild(saldoLink(s.name, balance));
    var name = document.createElement('span');
    name.className = 'kc-name'; name.textContent = s.name;
    li.appendChild(card); li.appendChild(name);
    return li;
  }

  function nameOf(li) { var n = li.querySelector('.kc-name'); return n ? n.textContent.replace(/ · gids$/, '') : ''; }

  function insertSorted(list, li) {
    var key = fold(nameOf(li));
    var items = list.querySelectorAll('.kc');
    for (var i = 0; i < items.length; i++) {
      if (items[i] === li) continue;
      var o = fold(nameOf(items[i]));
      if ((o.localeCompare ? o.localeCompare(key, 'nl') : (o > key ? 1 : -1)) > 0) { list.insertBefore(li, items[i]); return; }
    }
    list.appendChild(li);
  }

  // Naam, kleur, soort en categorie bijwerken als die in het beheer anders zijn dan op de gegenereerde pagina.
  function update(li, s, k) {
    var card = li.querySelector('.kc-card');
    var hex = hexOr(s.card_hex, null);
    if (card && hex && !card.classList.contains('has-cover')) {
      card.style.background = hex;
      card.classList.toggle('ink-dark', isLight(hex));
    }
    var nameEl = li.querySelector('.kc-name');
    if (nameEl && nameOf(li) !== s.name) {
      var gids = nameEl.querySelector('.kc-gids');
      nameEl.textContent = s.name;
      if (gids) nameEl.appendChild(gids);
      var w = card && card.querySelector('.kc-word');
      if (w) w.textContent = s.name;
    }
    li.setAttribute('data-q', [s.name].concat(s.aliases || [], s.domain || '').map(fold).join(' '));
    if (s.category) li.setAttribute('data-c', s.category);
    var list = blocks[k].querySelector('.kg');
    if (li.parentNode !== list) insertSorted(list, li);
  }

  function merge(json) {
    var pages = json.balance_pages && typeof json.balance_pages === 'object' ? json.balance_pages : {};
    var seen = {};
    json.stores.forEach(function (s) {
      if (!s || typeof s.id !== 'string' || s.removed || !s.name) return;
      var k = s.kind === 'voucher' ? 'voucher' : 'loyalty';
      if (!s.domain && k !== 'voucher') return;   // geen winkel ("Kapper (eigen kaart)")
      var id = cssId(s.id);
      seen[id] = true;
      var c = s.category || 'Overig';
      if (!cats[k]) cats[k] = [];
      if (cats[k].indexOf(c) === -1) { cats[k].push(c); cats[k].sort(function (a, b) { return a.localeCompare(b, 'nl'); }); }
      var existing = document.querySelectorAll('.kc[data-id="' + id + '"]:not(.ks)');
      if (existing.length) {
        each(existing, function (li) { li.removeAttribute('data-gone'); update(li, s, k); });
        return;
      }
      insertSorted(blocks[k].querySelector('.kg'), makeTile(s, safeUrl(pages[s.id])));
    });
    // Alles wat niet (meer) gepubliceerd is in de database: niet tonen.
    each(document.querySelectorAll('.kc:not(.ks)'), function (li) {
      if (!seen[li.getAttribute('data-id')]) li.setAttribute('data-gone', ''); else li.removeAttribute('data-gone');
    });
    // Saldo-pagina's zoals in het beheer: erbij, aangepast of weg
    each(blocks.voucher.querySelectorAll('.kc'), function (li) {
      var id = li.getAttribute('data-id'), url = null;
      Object.keys(pages).forEach(function (k) { if (cssId(k) === id) url = safeUrl(pages[k]); });
      var card = li.querySelector('.kc-card');
      if (!card) return;
      var a = card.querySelector('.kc-saldo');
      if (url && !a) card.appendChild(saldoLink(nameOf(li), url));
      else if (url && a) a.href = url;
      else if (!url && a) a.remove();
    });
    each(blocks.loyalty.querySelectorAll('.kc-saldo'), function (a) { a.remove(); });
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

  // Logo's los ophalen (pasr_store_logos, hoogstens 40 per keer): voor elke winkel waar de pagina geen logo heeft en
  // voor elke winkel die na het maken van deze pagina in het beheer is gewijzigd (mogelijk een ander logo).
  function loadLogos(ids) {
    for (var i = 0; i < ids.length; i += 40) {
      rpc('pasr_store_logos', { p_ids: ids.slice(i, i + 40) }).then(function (logos) {
        if (!logos || typeof logos !== 'object') return;
        Object.keys(logos).forEach(function (id) {
          var b64 = logos[id];
          if (!b64ok(b64)) return;
          each(document.querySelectorAll('.kc[data-id="' + cssId(id) + '"]:not(.ks) .kc-card'), function (card) {
            var word = card.querySelector('.kc-word'), box = card.querySelector('.kc-logo'), img = box && box.querySelector('img');
            if (!img) {
              box = document.createElement('span'); box.className = 'kc-logo';
              img = document.createElement('img'); img.alt = ''; img.decoding = 'async';
              box.appendChild(img);
              card.insertBefore(box, card.querySelector('.kc-saldo'));
            }
            // logo's van de server hebben de stijl (vlak, plaat) al ingebakken
            box.className = 'kc-logo'; box.removeAttribute('style');
            img.removeAttribute('width'); img.removeAttribute('height');
            img.src = 'data:image/png;base64,' + b64.replace(/\s+/g, '');
            if (word) word.remove();
          });
        });
      });
    }
  }

  // Kaartontwerpen van cadeaukaarten (pasr_store_covers, hoogstens 40 per keer): voor ontwerpen die (nog) niet als
  // bestand op de site staan, of als de kaart na het maken van de site in het beheer is gewijzigd.
  function setCover(card, src) {
    var img = card.querySelector('.kc-cover');
    if (!img) {
      img = document.createElement('img');
      img.className = 'kc-cover'; img.alt = ''; img.decoding = 'async';
      card.insertBefore(img, card.firstChild);
    }
    img.removeAttribute('width'); img.removeAttribute('height');
    img.src = src;
    card.classList.add('has-cover');
  }
  function loadCovers(ids) {
    for (var i = 0; i < ids.length; i += 40) {
      rpc('pasr_store_covers', { p_ids: ids.slice(i, i + 40) }).then(function (covers) {
        if (!covers || typeof covers !== 'object') return;
        Object.keys(covers).forEach(function (id) {
          var b64 = covers[id];
          if (!imgOk(b64)) return;
          each(blocks.voucher.querySelectorAll('.kc[data-id="' + cssId(id) + '"] .kc-card'), function (card) { setCover(card, dataUrl(b64)); });
        });
      });
    }
  }

  function fetchCatalog() {
    rpc('pasr_store_index').then(function (json) {
      if (!json || !Array.isArray(json.stores)) return;   // offline of geblokkeerd: de gegenereerde lijst blijft staan
      var built = Date.parse(cfg.built || '') || 0, logos = [], covers = [], staticCovers = [];
      var files = {};
      Object.keys(cfg.covers || {}).forEach(function (k) { files[cssId(k)] = cfg.covers[k]; });
      json.stores.forEach(function (s) {
        if (!s || typeof s.id !== 'string' || s.removed) return;
        var id = cssId(s.id);
        var known = document.querySelector('.kc[data-id="' + id + '"]:not(.ks)');
        var changed = !known || !built || Date.parse(s.updated_at || '') > built;
        var hasLogo = known && known.querySelector('.kc-logo img');
        // Zonder live gegevens bij het maken (terugval op de repo) kan elk logo verouderd zijn: dan alle logo's live.
        if (s.has_logo && (changed || !hasLogo || !cfg.live)) logos.push(s.id);
        if (s.kind === 'voucher') {
          var file = files[id];
          // Staat het ontwerp als bestand op de site, dan dat (klein en gecachet); anders, of als de winkel na het maken
          // van de site is gewijzigd (mogelijk een nieuw ontwerp), live ophalen.
          if (s.has_cover && file && !changed) { if (!(known && known.querySelector('.kc-cover'))) staticCovers.push([id, file]); }
          else if (s.has_cover) covers.push(s.id);
          // ontwerp in het beheer weggehaald: weer logo en kleur
          if (!s.has_cover) {
            each(document.querySelectorAll('.kc[data-id="' + id + '"] .kc-card'), function (card) {
              var img = card.querySelector('.kc-cover'); if (img) img.remove();
              card.classList.remove('has-cover');
            });
          }
        }
      });
      merge(json);
      if (logos.length) loadLogos(logos);
      if (covers.length) loadCovers(covers);
      staticCovers.forEach(function (pair) {
        if (!/^[a-z0-9-]+\.(jpg|png)$/.test(pair[1])) return;
        each(blocks.voucher.querySelectorAll('.kc[data-id="' + pair[0] + '"] .kc-card'), function (card) {
          if (!card.querySelector('.kc-cover')) setCover(card, '/assets/covers/' + pair[1]);
        });
      });
    });
  }

  // ---- Stempelkaarten (pasr_business_directory: gepubliceerd, zaak goedgekeurd en vindbaar) ------------------------
  // Nooit tonen: de demo-zaak voor App Review en zaken die niet vindbaar willen zijn.
  function hiddenBusiness(b) {
    if (!b || b.listed === false) return true;
    return /apple\s*review/i.test([b.business_name, b.card_name, b.name].join(' '));
  }

  function stampTile(b) {
    var total = Math.max(2, Math.min(30, parseInt(b.stamps_total, 10) || 10));
    var bg = hexOr(b.color, '#6A5CFF');
    var ink = hexOr(b.text_color, isLight(bg) ? '#17162A' : '#FFFFFF');
    var li = document.createElement('li');
    li.className = 'kc ks';
    li.setAttribute('data-id', cssId(b.card_id));
    li.setAttribute('data-q', [b.business_name, b.card_name, b.city, b.reward].filter(Boolean).map(fold).join(' '));
    var card = document.createElement('div');
    card.className = 'kc-card ks-card';
    card.style.background = bg; card.style.color = ink;
    var top = document.createElement('span'); top.className = 'ks-top';
    if (imgOk(b.logo)) {
      var img = document.createElement('img');
      img.className = 'ks-logo'; img.alt = ''; img.decoding = 'async'; img.src = dataUrl(b.logo);
      top.appendChild(img);
    }
    var biz = document.createElement('span'); biz.className = 'ks-biz'; biz.textContent = b.business_name;
    top.appendChild(biz);
    var dots = document.createElement('span'); dots.className = 'ks-dots'; dots.setAttribute('aria-hidden', 'true');
    dots.style.setProperty('--n', String(Math.min(total, 10)));
    for (var i = 0; i < total; i++) dots.appendChild(document.createElement('i'));
    var reward = document.createElement('span'); reward.className = 'ks-reward'; reward.textContent = b.reward || '';
    card.appendChild(top); card.appendChild(dots); card.appendChild(reward);
    var name = document.createElement('span'); name.className = 'kc-name'; name.textContent = b.business_name;
    var sub = document.createElement('span'); sub.className = 'ks-sub';
    sub.textContent = [b.city, total + ' stempels'].filter(Boolean).join(' · ');
    li.appendChild(card); li.appendChild(name); li.appendChild(sub);
    return li;
  }

  function fetchStamps() {
    if (!blocks.stamp) return;
    rpc('pasr_business_directory', { p_limit: 200 }).then(function (list) {
      if (!Array.isArray(list)) return;   // offline: de gegenereerde lijst blijft staan
      var ul = blocks.stamp.querySelector('.kg');
      var items = list.filter(function (b) { return !hiddenBusiness(b) && b.card_id && b.business_name; });
      items.sort(function (a, b) {
        var x = fold(a.business_name + ' ' + (a.card_name || '')), y = fold(b.business_name + ' ' + (b.card_name || ''));
        return x.localeCompare ? x.localeCompare(y, 'nl') : (x > y ? 1 : -1);
      });
      while (ul.firstChild) ul.removeChild(ul.firstChild);
      items.forEach(function (b) { ul.appendChild(stampTile(b)); });
      setCounts();
      apply();
    });
  }

  function start() {
    if (!cfg.url || !cfg.key || !window.fetch || !window.JSON) return;
    fetchCatalog();
    fetchStamps();
  }
  // Voor de zekerheid ook in de gegenereerde lijst: nooit de demo-zaak voor App Review.
  if (blocks.stamp) {
    each(blocks.stamp.querySelectorAll('.kc'), function (li) {
      if (/apple\s*review/i.test(li.textContent || '')) li.remove();
    });
    setCounts();
    apply();
  }
  if ('requestIdleCallback' in window) requestIdleCallback(start, { timeout: 2000 }); else setTimeout(start, 300);
})();
