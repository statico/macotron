// Shared by every page: the color scheme toggle and the look picker.
const LOOKS = ["default", "polar", "smui", "blueprint", "glass", "phosphor"];

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

// Shown only while previewing looks, so visitors never see it.
if (new URLSearchParams(location.search).has("look") || localStorage.getItem("look")) {
  const current = document.documentElement.dataset.look || "default";
  const picker = document.createElement("label");
  picker.className = "look-picker";
  picker.innerHTML = "Look <select>" +
    LOOKS.map((l) => `<option${l === current ? " selected" : ""}>${l}</option>`).join("") + "</select>";
  picker.querySelector("select").addEventListener("change", (e) => {
    const url = new URL(location.href);
    url.searchParams.set("look", e.target.value);
    location.href = url.href;
  });
  document.body.append(picker);
}
