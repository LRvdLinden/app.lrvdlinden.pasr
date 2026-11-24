/* Shared animated website experience, without altering the existing production animations. */
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
      // De officiële Pasr-stempel wordt via het bestaande SVG getoond.
      el.textContent = "";
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

  // Three separate demonstrations of genuine business product categories.
  // All interactions are local and never create/redeem real merchant discounts.
  document.querySelectorAll("[data-pv-demo]").forEach(button => {
    button.addEventListener("click", () => {
      const selected = button.dataset.pvDemo;
      document.querySelectorAll("[data-pv-demo]").forEach(tab => {
        tab.setAttribute("aria-pressed", String(tab.dataset.pvDemo === selected));
      });
      document.querySelectorAll("[data-pv-panel]").forEach(panel => {
        panel.hidden = panel.dataset.pvPanel !== selected;
      });
    });
  });
  const couponButton = document.getElementById("pv-change-coupon");
  const couponValue = document.getElementById("pv-coupon-value");
  if (couponButton && couponValue) {
    couponButton.addEventListener("click", () => {
      const isPercentage = couponValue.textContent.includes("%");
      couponValue.textContent = isPercentage ? "€ 5 korting" : "10% korting";
      couponButton.textContent = isPercentage ? "Bekijk een 10%-coupon" : "Bekijk een € 5-coupon";
    });
  }

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
