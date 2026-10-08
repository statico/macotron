// Runs in <head> before the stylesheet paints, so neither the color scheme nor
// a preview look flashes in late.
(function () {
  var root = document.documentElement;
  var m = localStorage.getItem("theme") || "system";
  if (m === "light" || m === "dark") root.dataset.theme = m;

  // ?look=name previews site/looks/name.css and remembers it; ?look=default
  // goes back to plain site.css.
  var asked = new URLSearchParams(location.search).get("look");
  if (asked) localStorage.setItem("look", asked);
  var look = localStorage.getItem("look");
  if (look === "default") { localStorage.removeItem("look"); look = null; }
  if (look && /^[a-z-]+$/.test(look)) {
    root.dataset.look = look;
    document.write('<link rel="stylesheet" href="/looks/' + look + '.css">');
  }
})();
