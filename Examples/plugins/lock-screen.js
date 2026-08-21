macotron.plugin({
  title: "Lock Screen",
  description: "Lock this Mac from the launcher.",
});

macotron.command("Lock Screen", "Lock this Mac", () => {
  macotron.power.lock();
});
