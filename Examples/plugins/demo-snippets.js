macotron.snippets.set("omw", "On my way!");
macotron.snippets.set(";date", new Date().toLocaleDateString());
macotron.snippets.setExpansionEnabled(true);
macotron.command("Insert OMW", "Copy the OMW snippet", () => macotron.snippets.insert("omw"));
macotron.command("List snippets", "Log registered snippets", () => {
  console.log(macotron.snippets.list());
});
