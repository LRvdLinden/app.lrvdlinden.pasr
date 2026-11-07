// The phone in the hero: tap a card and it comes forward and turns over to its barcode,
// like in the app. Tap it again to put it back.
(function () {
  const stack = document.getElementById('stack');
  if (!stack) return;
  const hint = document.getElementById('hint');
  const passes = Array.from(stack.querySelectorAll('.pass'));
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const tops = passes.map(p => p.style.top);
  let active = null;

  function close() {
    if (!active) return;
    const index = passes.indexOf(active);
    active.style.transform = '';
    active.style.top = tops[index];
    active.classList.remove('active');
    active.setAttribute('aria-pressed', 'false');
    stack.classList.remove('open');
    active = null;
    if (hint) hint.textContent = 'Tik op een kaart';
  }

  function open(pass) {
    close();
    active = pass;
    stack.classList.add('open');
    pass.classList.add('active');
    pass.setAttribute('aria-pressed', 'true');
    pass.style.top = '90px';
    pass.style.transform = 'scale(1.04)';
    setTimeout(() => {
      if (active === pass) pass.style.transform = 'scale(1.04) rotateY(180deg)';
    }, reduce ? 0 : 260);
    if (hint) hint.textContent = 'Tik nog eens om terug te leggen';
  }

  passes.forEach(pass => {
    pass.setAttribute('aria-pressed', 'false');
    pass.addEventListener('click', () => (active === pass ? close() : open(pass)));
  });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
})();

// Animations: cards that slide in while scrolling, a counting "300+", a phone that floats and tilts
// with the mouse, and one card that shows its barcode by itself after the page has loaded.
(function () {
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Slide in while scrolling
  const groups = ['.section-head', '.features .feature', '.steps li', '.compare > div', '#faq details', '.cta', '.page > *'];
  const items = [];
  groups.forEach(sel => document.querySelectorAll(sel).forEach((el, i) => {
    el.classList.add('reveal');
    el.style.setProperty('--r', String(i % 6));
    items.push(el);
  }));
  if (reduce || !('IntersectionObserver' in window)) {
    items.forEach(el => el.classList.add('in'));
  } else {
    const io = new IntersectionObserver(entries => entries.forEach(e => {
      if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
    }), { threshold: 0, rootMargin: '0px 0px -40px 0px' });
    items.forEach(el => io.observe(el));
  }

  // 0 → 300 when the store band comes into view
  const count = document.querySelector('.stores .count');
  if (count && !reduce && 'IntersectionObserver' in window) {
    const to = +count.dataset.to;
    count.textContent = '0';
    const io = new IntersectionObserver(entries => {
      if (!entries[0].isIntersecting) return;
      io.disconnect();
      const start = performance.now();
      const step = now => {
        const t = Math.min(1, (now - start) / 1400);
        count.textContent = String(Math.round(to * (1 - Math.pow(1 - t, 3))));
        if (t < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    }, { threshold: 0.6 });
    io.observe(count);
  }

  const stage = document.querySelector('.stage');
  const phone = stage && stage.querySelector('.phone');
  const stack = document.getElementById('stack');
  if (!stage || !phone || reduce) return;

  // After the entrance, drop its animations (they would hold the cards' transforms) and start floating
  setTimeout(() => { stage.classList.remove('enter-stage'); stage.classList.add('floating'); }, 2300);

  // Tilt with the mouse (desktop)
  if (window.matchMedia('(pointer: fine)').matches) {
    stage.addEventListener('mousemove', e => {
      const r = stage.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      phone.style.transform = `perspective(1200px) rotateY(${x * 10}deg) rotateX(${-y * 8}deg)`;
    });
    stage.addEventListener('mouseleave', () => { phone.style.transform = ''; });
  }

  // Show once what a tap does: the front card comes forward and turns over, then goes back
  if (stack) {
    let touched = false;
    stack.addEventListener('click', () => { touched = true; }, { capture: true });
    const passes = stack.querySelectorAll('.pass');
    const last = passes[passes.length - 1];
    setTimeout(() => {
      if (touched || !last) return;
      last.click();
      touched = false;
      setTimeout(() => { if (!touched && last.classList.contains('active')) last.click(); }, 2600);
    }, 2600);
  }
})();

// Delen: start de animaties als de sectie in beeld komt; de tijdelijke kaart telt 24 uur af in 6 seconden,
// verloopt (code vervaagt, stempel "Verlopen"), en begint daarna opnieuw.
(function () {
  const section = document.getElementById('delen');
  if (!section) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const phone = section.querySelector('.tp-phone');
  const meter = section.querySelector('.tp-meter i');
  const time = section.querySelector('.tp-time');
  const label = section.querySelector('.tp-label');
  const DAY = 24 * 3600, RUN = 6000, HOLD = 2600;
  const fmt = s => [Math.floor(s / 3600), Math.floor(s / 60) % 60, Math.floor(s) % 60].map(n => String(n).padStart(2, '0')).join(':');
  let started = false;

  function countdown() {
    phone.classList.remove('expired');
    label.textContent = 'Nog geldig';
    const t0 = performance.now();
    const step = now => {
      const p = Math.min(1, (now - t0) / RUN);
      const eased = p < 0.8 ? p / 0.8 * 0.6 : 0.6 + (p - 0.8) / 0.2 * 0.4;   // het laatste stuk gaat sneller
      meter.style.transform = `scaleX(${1 - eased})`;
      time.textContent = fmt(DAY * (1 - eased));
      if (p < 1) return requestAnimationFrame(step);
      phone.classList.add('expired');
      label.textContent = 'Verlopen';
      time.textContent = '00:00:00';
      setTimeout(countdown, HOLD);
    };
    requestAnimationFrame(step);
  }

  function play() {
    if (started) return;
    started = true;
    section.classList.add('play');
    if (!reduce && phone) setTimeout(countdown, 1600);
  }

  if (reduce || !('IntersectionObserver' in window)) return play();
  const io = new IntersectionObserver(entries => {
    if (entries.some(e => e.isIntersecting)) { io.disconnect(); play(); }
  }, { threshold: 0.25 });
  io.observe(section.querySelector('.share-grid'));
})();

// Functies naast elkaar: rijen schuiven in, vinkjes ploppen als de tabel in beeld komt
(function () {
  const t = document.querySelector('.ft');
  if (!t) return;
  t.querySelectorAll('tbody tr').forEach(tr => {
    const y = tr.querySelector('.ft-y');
    if (y) y.style.setProperty('--r', tr.style.getPropertyValue('--r'));
  });
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)) return t.classList.add('in');
  const io = new IntersectionObserver(e => { if (e[0].isIntersecting) { t.classList.add('in'); io.disconnect(); } }, { threshold: 0.2 });
  io.observe(t);
})();

// Overstappen: kaarten komen voorbij in de schermopname, worden gescand en landen in Pasr; daarna opnieuw
(function () {
  const demo = document.querySelector('.im-demo');
  if (!demo) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const src = Array.from(demo.querySelectorAll('.im-src'));
  const rows = Array.from(demo.querySelectorAll('.im-row'));
  const scan = demo.querySelector('.im-scan');
  const count = demo.querySelector('.im-count b');
  if (reduce || !('IntersectionObserver' in window)) { count.textContent = rows.length; return; }
  let k = 0, timer = null;
  function reset() {
    src.forEach(s => s.classList.remove('on', 'off'));
    rows.forEach(r => r.classList.remove('in'));
    count.textContent = '0';
    k = 0;
  }
  function step() {
    if (k > 0) { src[k - 1].classList.remove('on'); src[k - 1].classList.add('off'); }
    if (k >= src.length) { timer = setTimeout(() => { reset(); timer = setTimeout(step, 500); }, 2600); return; }
    src[k].classList.add('on');
    const i = k;
    setTimeout(() => {
      scan.classList.remove('hit'); void scan.offsetWidth; scan.classList.add('hit');
      setTimeout(() => { rows[i].classList.add('in'); count.textContent = String(i + 1); }, 350);
    }, 450);
    k++;
    timer = setTimeout(step, 1400);
  }
  const io = new IntersectionObserver(e => {
    if (e[0].isIntersecting && !timer) step();
  }, { threshold: 0.3 });
  io.observe(demo);
})();

// Deelbare #-links: een linkje naast elke kop (tik = adres gekopieerd), en een gedeelde vraag gaat vanzelf open
(function () {
  const targets = document.querySelectorAll('section[id] h2, article[id] h3, .ft-wrap[id] h3, details[id] summary, main h2[id]');
  targets.forEach(h => {
    const holder = h.closest('[id]');
    const id = holder && holder.id;
    if (!id || h.querySelector('.anchor')) return;
    const a = document.createElement('a');
    a.className = 'anchor';
    a.href = '#' + id;
    a.setAttribute('aria-label', 'Link naar dit deel kopiëren');
    a.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
    a.addEventListener('click', e => {
      e.preventDefault();
      e.stopPropagation();
      const url = location.origin + location.pathname + '#' + id;
      history.replaceState(null, '', '#' + id);
      const done = () => { a.classList.add('copied'); setTimeout(() => a.classList.remove('copied'), 1600); };
      if (navigator.share && matchMedia('(pointer: coarse)').matches) {
        navigator.share({ url, title: document.title }).catch(() => {});
      } else if (navigator.clipboard) {
        navigator.clipboard.writeText(url).then(done, done);
      } else { done(); }
    });
    h.appendChild(a);
  });
  function openFromHash() {
    const id = decodeURIComponent(location.hash.slice(1));
    const el = id && document.getElementById(id);
    if (!el) return;
    if (el.tagName === 'DETAILS') el.open = true;
    el.classList.add('in');   // niet onzichtbaar blijven door de inschuif-animatie
    el.querySelectorAll('.reveal').forEach(r => r.classList.add('in'));
  }
  openFromHash();
  window.addEventListener('hashchange', openFromHash);
})();
