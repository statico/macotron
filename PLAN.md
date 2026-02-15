# Macotron

Architecture documentation has been split into `docs/`:

- [01-overview.md](docs/01-overview.md) — What Macotron is, tech stack, process architecture
- [02-project-structure.md](docs/02-project-structure.md) — Repo layout, source targets, user config, backup/rollback
- [03-engine.md](docs/03-engine.md) — QuickJS engine, NativeModule protocol, EventBus, execution model
- [04-modules.md](docs/04-modules.md) — Native module list and JS APIs
- [05-ai-integration.md](docs/05-ai-integration.md) — AI providers, tool-call file management, auto-fix
- [06-security.md](docs/06-security.md) — Permissions, capability tiers, shell approval, mitigations
- [07-build-system.md](docs/07-build-system.md) — Package.swift, Makefile, debug server
- [08-examples.md](docs/08-examples.md) — Example snippets (window tiling, URL routing, etc.)
- [09-phases.md](docs/09-phases.md) — Implementation phases

## Key changes from original plan

- **No TypeScript support** — JS only (may add later)
- **No IndexedDB** — localStorage only for simplicity
- **AI uses tool calls** for reading/writing snippets (not direct fs access)
- **Module versioning** — each module declares a version number
- **Config backup/rollback** — full compressed backup before every AI-initiated change
