macotron.plugin({
  title: "Text Snippets",
  description: "Expand short abbreviations into longer text from the launcher.",
});

macotron.snippets.set("omw", "On my way!");
macotron.snippets.setExpansionEnabled(true);

macotron.launcher.set("snippets", [
  {
    id: "omw",
    title: "omw",
    subtitle: "On my way!",
    onClick: () => macotron.snippets.insert("omw"),
  },
  {
    id: "date",
    title: "Insert Date",
    onClick: () => {
      const today = new Date().toLocaleDateString();
      macotron.clipboard.set(today);
      macotron.notify.toast("Copied", today);
    },
  },
]);

macotron.command("Insert OMW", "Copy the OMW snippet", () => macotron.snippets.insert("omw"));
