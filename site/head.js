// Runs in <head> before first paint, so the color scheme never flashes in late.
(function () {
  var m = localStorage.getItem("theme") || "system";
  if (m === "light" || m === "dark") document.documentElement.dataset.theme = m;
})();
