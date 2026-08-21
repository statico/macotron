macotron.plugin({
  title: "Web Search",
  description: "Search the web or look up a word from the launcher.",
});

function searchURL(engine, q) {
  const e = encodeURIComponent(q);
  return {
    google: "https://www.google.com/search?q=",
    wikipedia: "https://en.wikipedia.org/wiki/Special:Search?search=",
    maps: "https://maps.apple.com/?q=",
    youtube: "https://www.youtube.com/results?search_query=",
    github: "https://github.com/search?q=",
  }[engine] + e;
}

const qArg = { arguments: [{ name: "q", type: "text", placeholder: "Query", required: true }] };

function search(engine, args) {
  const q = String(args.q || "").trim();
  if (!q) return macotron.notify.toast("Enter a query");
  macotron.url.open(searchURL(engine, q));
}

for (const [name, engine] of [
  ["Search Google", "google"],
  ["Search Wikipedia", "wikipedia"],
  ["Search Maps", "maps"],
  ["Search YouTube", "youtube"],
  ["Search GitHub", "github"],
]) {
  macotron.command(name, name, (args) => search(engine, args), qArg);
}

macotron.command("Define", "Look up a word in Dictionary", (args) => {
  const q = String(args.q || "").trim();
  if (!q) return macotron.notify.toast("Enter a query");
  macotron.shell.run("/usr/bin/open", ["dict://" + encodeURIComponent(q)]);
}, qArg);
