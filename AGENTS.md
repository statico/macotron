# Macotron - AI-powered macOS automation tool

- Read docs/ for the master plan 
- Use best practices as of February 2026 for macOS 26 Tahoe
- Read the Apple HIG to understand UI guidelines
- Make sure `make` builds clean
- Commit after every feature
- Keep the code clean
- Use Raycast as inspiration
- Take screenshots using the HTTP server and evaluate with /frontend-design
- Use subagents to parallelize work
- Built-in macOS only: host APIs and demo plugins must work on a stock Mac with Macotron installed. No Homebrew, npm, or other third-party binaries. Use `macotron.*` and Apple-shipped tools (`/usr/bin/open`, `/usr/bin/defaults`, `/bin/mv`).
