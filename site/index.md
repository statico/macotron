---
title: Macotron does everything.
description: Customization and automation with a quick launch bar, global hotkeys, menu bar items, and APIs for everything you can think of. Open-source and free.
doc_version: "1.1.0"
last_updated: 2026-08-21
---

# Macotron does everything.

Tile windows, bind hotkeys, drive the menu bar, read sensors, capture the screen, talk to models. From small JavaScript files that reload when you save them.

Free and open source. Built with Swift and QuickJS.

- [Download for macOS](https://github.com/statico/macotron/releases/latest), or `brew install statico/tap/macotron`
- [Source on GitHub](https://github.com/statico/macotron)
- [Glossary](./glossary.md)
- [AGENTS.md](./AGENTS.md)

## What it is

Macotron is a native macOS host for JavaScript plugins. First launch asks for a directory. Scripts go in `plugins/`. Macotron writes an `AGENTS.md` next to them so a coding agent already knows the API.

The catalog ships 73 built-in plugins. Everything hangs off `macotron.*`. Apple-shipped tools only. No Homebrew, npm, or extra binaries.

## Example

```javascript
// ~/Macotron/plugins/tile.js
macotron.keyboard.on("Tile Left", "ctrl+opt+left", () => {
  const win = macotron.window.focused();
  macotron.window.moveToFraction(win.id, {
    x: 0, y: 0, w: 0.5, h: 1,
  });
});
```

Save the file. The hotkey is live.

## Capabilities

The homepage lists host capabilities under Launcher, Windows, Interface, Screen and clipboard, Display, System, Power, Network, Input, Apps, Audio and media, Home and people, Devices, Files and shell, AI, Accessibility, Runtime, and the built-in plugin catalog.

## Plugins

Featured catalog plugins: Calculator, Clipboard History, File Search, Lock Screen, Meetings, Notes, Snippets, Weather, Window Grid, Windows.

Browse every built-in plugin under `workdir/plugins/` on this site, or `Examples/plugins/` in the repo.

## Host API

Namespaces include `macotron.window`, `keyboard`, `event`, `display`, `system`, `power`, `audio`, `network`, `bonjour`, `udp`, `appletv`, `app`, `spaces`, `screen`, `ocr`, `qr`, `clipboard`, `snippets`, `fs`, `shell`, `http`, `ai`, `panel`, `menubar`, `notify`, `media`, `calendar`, `reminders`, `notes`, `contacts`, `homekit`, `dock`, `ax`, `camera`, `share`, `hid`, `spotlight`, `launcher`, `usb`, `shortcuts`, `url`, `keychain`, `idle`, `every` / `at`, and `settings` / `checks`.

## Sitemap

- [Home](/)
- [Glossary](/glossary.md)
- [AGENTS.md](/AGENTS.md)
- [llms.txt](/llms.txt)
- [Sitemap](/sitemap.md)
