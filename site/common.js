// Shared by every page: the color scheme toggle.

function applyTheme(mode) {
  if (mode === "light" || mode === "dark") document.documentElement.dataset.theme = mode;
  else delete document.documentElement.dataset.theme;
  localStorage.setItem("theme", mode);
  document.querySelectorAll("[data-theme-set]").forEach((btn) => {
    btn.setAttribute("aria-pressed", btn.dataset.themeSet === mode ? "true" : "false");
  });
}

applyTheme(localStorage.getItem("theme") || "system");
document.querySelector(".theme")?.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-theme-set]");
  if (btn) applyTheme(btn.dataset.themeSet);
});

