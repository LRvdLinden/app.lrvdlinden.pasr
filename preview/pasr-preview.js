/* Only loaded by Pasr /test/ previews. Existing production animations continue unchanged. */
(() => {
  "use strict";
  const state = { stampCount: 6 };
  const stamp = document.getElementById("pv-stamps");
  const button = document.getElementById("pv-add-stamp");
  const reset = document.getElementById("pv-reset");
  const status = document.getElementById("pv-stamp-status");
  const draw = (animated) => {
    if (!stamp) return;
    stamp.querySelectorAll(".pv-stamp-dot").forEach((el, i) => {
      el.classList.toggle("on", i < state.stampCount);
      el.textContent = i < state.stampCount ? "✓" : "✧";
      el.classList.remove("pop");
      if (animated && i === state.stampCount - 1 &&
          !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
        void el.offsetWidth;
        el.classList.add("pop");
      }
    });
    if (status) status.textContent = state.stampCount >= 10
      ? "Kaart vol! Tijd voor je beloning." : `${state.stampCount} van 10 stempels · ${10 - state.stampCount} te gaan`;
    if (button) button.textContent = state.stampCount >= 10 ? "Opnieuw beginnen" : "Probeer +1 stempel";
  };
  if (button) {
    button.addEventListener("click", () => {
      state.stampCount = state.stampCount >= 10 ? 0 : state.stampCount + 1;
      draw(true);
    });
    draw(false);
  }
  if (reset) reset.addEventListener("click", () => { state.stampCount = 0; draw(false); });

  // Search input in concept hero leads to EXISTING catalog and gift-guide filters.
  // Never change or replace the existing catalog's search implementation.
  const qs = new URLSearchParams(location.search);
  const initial = qs.get("q");
  if (initial) {
    const field = document.querySelector("#kf-q, #gd-q");
    if (field) {
      field.value = initial.slice(0, 120);
      field.dispatchEvent(new Event("input", { bubbles: true }));
      const target = document.querySelector("#lijst, #gidsen");
      if (target) requestAnimationFrame(() => target.scrollIntoView({ block: "start" }));
    }
  }
  document.querySelectorAll("form[data-preview-search]").forEach(form => {
    form.addEventListener("submit", e => {
      const input = form.querySelector("input[name=q]");
      if (!input || !input.value.trim()) { e.preventDefault(); input?.focus(); return; }
      // Existing native GET navigation to /test/kaarten/?q=.. or /test/cadeaubon/?q=..
    });
  });

  // Concept-only marker; all published card, coupon and business interactions remain original.
  document.documentElement.dataset.pasrConcept = "true";
})();
