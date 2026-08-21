---
title: Glossary
description: Terms used by Macotron. Plugins, workdir, host API, catalog, and more.
doc_version: "1.1.0"
last_updated: 2026-08-21
---

# Glossary

Words the site and host API use.

## Plugin

A `.js` file in the workdir `plugins/` folder. Macotron loads it and runs it.

## Workdir

The folder you pick on first launch. Holds `plugins/`, `settings.json`, and an app-owned `AGENTS.md`.

## Host API

The `macotron.*` object injected into every plugin. Native Swift modules, not npm packages.

## Catalog

The 73 built-in plugins shipped in the app. First launch copies the ones you pick into the workdir.

## Featured

Catalog plugins marked `highlighted` in `catalog.json`. They sort first in Settings and on this site.

## Hot reload

Save a plugin file and the host reloads that script. Off by default for unapproved hashes.

## Helper

A background service the user installs from Settings for privileged work such as a fan-speed floor.

## Stock Mac

Built-in plugins use only `macotron.*` and Apple-shipped tools. No Homebrew, npm, or extra binaries.

## Panel

A small WKWebView window opened with `macotron.panel.open`.

## Launcher

The Cmd-Space style palette. Plugins add rows with `macotron.launcher.set` and `macotron.command`.

## QuickJS

The embedded JavaScript engine. Plugins are not Node and have no npm.

## Sitemap

- [Home](/index.md)
- [Glossary](/glossary.md)
- [AGENTS.md](/AGENTS.md)
- [Sitemap](/sitemap.md)
