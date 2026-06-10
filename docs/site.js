const root = document.documentElement;
const themeButton = document.querySelector(".theme-toggle");
const tabs = Array.from(document.querySelectorAll("[role='tab']"));
const panels = Array.from(document.querySelectorAll("[role='tabpanel']"));
const mobileCta = document.querySelector(".mobile-cta");
const hero = document.querySelector(".hero");
const finalCta = document.querySelector(".final-cta");

function setTheme(theme, persist = true) {
  root.dataset.theme = theme;
  if (persist) {
    try {
      localStorage.setItem("memento-theme", theme);
    } catch (error) {
      // Theme still changes for the current page when storage is unavailable.
    }
  }

  if (!themeButton) {
    return;
  }

  const nextTheme = theme === "dark" ? "light" : "dark";
  themeButton.setAttribute("aria-label", `Switch to ${nextTheme} mode`);
  themeButton.setAttribute("aria-pressed", String(theme === "dark"));
}

if (themeButton) {
  setTheme(root.dataset.theme || "light", false);
  themeButton.addEventListener("click", () => {
    setTheme(root.dataset.theme === "dark" ? "light" : "dark");
  });
}

function activateTab(nextTab) {
  tabs.forEach((tab) => {
    const isActive = tab === nextTab;
    tab.classList.toggle("is-active", isActive);
    tab.setAttribute("aria-selected", String(isActive));
    tab.tabIndex = isActive ? 0 : -1;
  });

  panels.forEach((panel) => {
    const isActive = panel.dataset.panel === nextTab.dataset.tab;
    panel.classList.toggle("is-active", isActive);
    panel.hidden = !isActive;
  });
}

tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => activateTab(tab));
  tab.addEventListener("keydown", (event) => {
    const lastIndex = tabs.length - 1;
    let nextIndex = index;

    if (event.key === "ArrowRight" || event.key === "ArrowDown") {
      nextIndex = index === lastIndex ? 0 : index + 1;
    } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
      nextIndex = index === 0 ? lastIndex : index - 1;
    } else if (event.key === "Home") {
      nextIndex = 0;
    } else if (event.key === "End") {
      nextIndex = lastIndex;
    } else {
      return;
    }

    event.preventDefault();
    tabs[nextIndex].focus();
    activateTab(tabs[nextIndex]);
  });
});

document.querySelectorAll(".visual-frame img").forEach((image) => {
  image.addEventListener("error", () => {
    const frame = image.closest(".visual-frame");
    const fallback = frame?.querySelector(".visual-fallback");
    image.hidden = true;
    if (fallback) {
      fallback.hidden = false;
    }
  });
});

requestAnimationFrame(() => {
  document.querySelectorAll("[data-reveal]").forEach((element) => {
    element.classList.add("is-visible");
  });
});

if (mobileCta && hero && finalCta && "IntersectionObserver" in window) {
  let heroVisible = true;
  let finalVisible = false;

  function syncMobileCta() {
    const shouldShow = !heroVisible && !finalVisible;
    mobileCta.classList.toggle("is-visible", shouldShow);
    mobileCta.setAttribute("aria-hidden", String(!shouldShow));
    mobileCta.toggleAttribute("inert", !shouldShow);
  }

  const ctaObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.target === hero) {
          heroVisible = entry.isIntersecting;
        }
        if (entry.target === finalCta) {
          finalVisible = entry.isIntersecting;
        }
      });
      syncMobileCta();
    },
    { threshold: 0.08 }
  );

  ctaObserver.observe(hero);
  ctaObserver.observe(finalCta);
}
