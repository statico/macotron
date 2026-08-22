# Macotron website

This directory is the public site for Macotron, a native macOS host for JavaScript plugins. Live URL: https://macotron.statico.io/

## What this is

A static homepage. No build step. Vercel serves the `site/` folder as the domain root.

- `index.html` / `index.md` — product page
- `site.js` / `site.css` — capabilities, API cards, plugin finder
- `workdir/plugins/*.js` — copies of the 73 built-in plugins
- `glossary.html` — terms used on the page and in the host API

The app itself lives in the repo root (`Sources/`, `Examples/plugins/`). Do not treat this folder as the plugin workdir. The workdir `AGENTS.md` that Macotron writes for coding agents is `workdir/AGENTS.md` here, and a generated file on the user's Mac.

## Installation

1. `brew install statico/tap/macotron`, or download from https://github.com/statico/macotron/releases/latest
2. Or build with `make bundle` from the repo root
3. First launch picks a workdir. Plugins go in `plugins/*.js`

## Usage

Edit `site/index.html`, `site/site.js`, and `site/site.css`. Keep the capability cards and `FILES` list in `site.js` in sync with `Examples/plugins/` and `Resources/Catalog/catalog.json`.

Serve locally:

```
python3 -m http.server 19876 --directory site
```

## Conventions

- Built-in macOS only. Host APIs and built-in plugins use `macotron.*` and Apple-shipped tools.
- Plugin filenames match the catalog. Featured plugins are listed first in the finder.
- Do not put secrets in this folder.

## a14y configuration

- Target URL: http://127.0.0.1:19876/
- Scorecard: 0.2.0
- Mode: site
- Last runs:
  - 2026-08-21 — 92 (scorecard 0.2.0)
  - 2026-08-21 — 91 (scorecard 0.2.0)
  - 2026-08-21 — 64 (scorecard 0.2.0)
  - 2026-08-21 — 40 (scorecard 0.2.0)
