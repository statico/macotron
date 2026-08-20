const opts = macotron.plugin({
  title: "Plain Paste",
  description: "Command-V pastes public.utf8-plain-text only.",
  options: {
    enabled: {
      type: "boolean",
      label: "Paste as plain text",
      default: true,
    },
  },
});

macotron.clipboard.setPastePlain(!!opts.enabled);
