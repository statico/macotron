const opts = macotron.plugin({
  title: "Plain Paste",
  description: "Paste as plain text when you press Command-V.",
  options: {
    enabled: {
      type: "boolean",
      label: "Paste as plain text",
      default: true,
    },
  },
});

macotron.clipboard.setPastePlain(!!opts.enabled);
