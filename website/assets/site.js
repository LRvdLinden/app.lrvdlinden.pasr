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
