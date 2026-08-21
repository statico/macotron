macotron.plugin({
  title: "Snippets",
  description: "Expand short abbreviations into longer text from the launcher.",
});

macotron.snippets.set("omw", "On my way!");
macotron.snippets.set(";date", new Date().toLocaleDateString());
macotron.snippets.setExpansionEnabled(true);
macotron.command("Insert OMW", "Copy the OMW snippet", () => macotron.snippets.insert("omw"));
macotron.command("List Snippets", "List registered snippets", () => {
  console.log(macotron.snippets.list());
});
