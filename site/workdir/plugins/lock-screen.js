macotron.plugin({
  title: "Lock Screen Command",
  description: "Lock this Mac from the launcher.",
});

macotron.command("Lock Screen", "Lock this Mac", () => {
  macotron.power.lock();
});
