# AI Integration

Macotron does not ship an in-app coding agent. External tools such as Claude Code, Codex, Cursor, and pi.dev edit plugins in the workdir. The host only runs plugins and exposes AI APIs to those plugins.

## Who Writes Plugins

| Role | Responsibility |
|---|---|
| Claude Code, Codex, Cursor, pi.dev | Create and edit `.js` files under `plugins/` |
| Macotron host | Load, watch, and run plugins. Own `AGENTS.md` and `CLAUDE.md` |
| Plugin code | Call `macotron.ai` when a plugin needs model output |

The app writes agent instruction files. Those files must not be edited by hand. The app overwrites them.

```
<!-- DO NOT EDIT — Macotron overwrites this file. -->
```

## Plugin AI API

Plugins call `macotron.ai` for cloud or on-device models:

```javascript
macotron.ai.claude({ model?, apiKey? })
macotron.ai.anthropic({ model?, apiKey? })  // same as claude
macotron.ai.openai({ model?, apiKey? })
macotron.ai.gemini({ model?, apiKey? })
macotron.ai.local()

// string or [{ role: "user"|"assistant", content }]
await ai.chat(promptOrMessages, { system?, model?, maxTokens?, temperature? })
await ai.stream(promptOrMessages, { system?, onChunk?, ... })  // Promise<string>
```

Multi-turn: pass the full message list each call. Persist history in plugin code
(`localStorage` or `macotron.fs`). The host does not store chats.

Store API keys in the Keychain through `macotron.keychain`, not in plugin source or git.

## Foundation Models

When Apple Foundation Models are available, plugins can call `macotron.ai.local()`. That is the on-device small model (Apple Intelligence). It needs macOS 26, Apple Silicon, and Apple Intelligence turned on.

## What the Host Does Not Do

The host does not run:

- In-app agent sessions
- Chat sessions as a coding agent
- Tool-call file management for snippets
- Module auto-fix loops
- Agent progress UI

External agents own planning, writing, testing, and repair. Macotron hot-reloads after disk changes.

## Prompt Injection Mitigation

When plugin code sends user-controlled data (screen content, clipboard, file contents) to a model, wrap that data with clear delimiters. Tell the model to ignore embedded instructions inside that data.
