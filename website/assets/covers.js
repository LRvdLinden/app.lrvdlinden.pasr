// Cadeaubon-gidsen: kaartontwerpen die na het maken van de site in het beheer zijn gezet, live ophalen
// (pasr_store_covers, hoogstens 40 per keer). Zonder verbinding blijft de kaart met logo en kleur staan.
(function () {
  'use strict';
  var me = document.currentScript;
  var url = me && me.getAttribute('data-url'), key = me && me.getAttribute('data-key');
  if (!url || !key || !window.fetch) return;
  function run() {
    var cards = document.querySelectorAll('.kc-card[data-cover]');
    var ids = [];
    Array.prototype.forEach.call(cards, function (c) {
      var id = (c.getAttribute('data-cover') || '').replace(/[^a-z0-9-]/g, '');
      if (id && ids.indexOf(id) === -1) ids.push(id);
    });
    for (var i = 0; i < ids.length; i += 40) {
      fetch(url.replace(/\/$/, '') + '/rest/v1/rpc/pasr_store_covers', {
        method: 'POST', credentials: 'omit',
        headers: { 'apikey': key, 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ p_ids: ids.slice(i, i + 40) })
      }).then(function (r) { return r.ok ? r.json() : null; }).then(function (covers) {
        if (!covers || typeof covers !== 'object') return;
        Object.keys(covers).forEach(function (id) {
          var b64 = covers[id];
          if (typeof b64 !== 'string' || !/^(\/9j\/|iVBORw0KGgo)[A-Za-z0-9+/=]+$/.test(b64)) return;
          Array.prototype.forEach.call(document.querySelectorAll('.kc-card[data-cover="' + id.replace(/[^a-z0-9-]/g, '') + '"]'), function (card) {
            if (card.querySelector('.kc-cover')) return;
            var img = document.createElement('img');
            img.className = 'kc-cover'; img.alt = ''; img.decoding = 'async';
            img.src = (b64.charAt(0) === '/' ? 'data:image/jpeg;base64,' : 'data:image/png;base64,') + b64;
            card.insertBefore(img, card.firstChild);
            card.classList.add('has-cover');
          });
        });
      }, function () { /* offline: niets */ });
    }
  }
  if ('requestIdleCallback' in window) requestIdleCallback(run, { timeout: 2000 }); else setTimeout(run, 300);
})();
