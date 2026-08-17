# AI Integration

Macotron does not ship an in-app coding agent. External tools such as Cursor and Claude Code edit plugins in the workdir. The host only runs plugins and exposes AI APIs to those plugins.

## Who Writes Plugins

| Role | Responsibility |
|---|---|
| Cursor / Claude Code / other agents | Create and edit `.js` files under `plugins/` |
| Macotron host | Load, watch, and run plugins. Own `AGENTS.md` and `CLAUDE.md` |
| Plugin code | Call `macotron.ai` when a plugin needs model output |

The app writes agent instruction files. Those files must not be edited by hand. The app overwrites them.

```
<!-- DO NOT EDIT — Macotron overwrites this file. -->
```

## Plugin AI API

Plugins call `macotron.ai` for cloud or on-device models:

```javascript
macotron.ai.claude({ model?, apiKey? })   // Anthropic API
macotron.ai.openai({ model?, apiKey? })   // OpenAI API
macotron.ai.gemini({ model?, apiKey? })   // Google Gemini API
macotron.ai.local()                       // Apple Foundation Models (on-device)

// All return an object with:
//   .chat(prompt, { image?, system? }) → Promise<string>
//   .stream(prompt, { image?, system? }) → calls onChunk callback
```

Store API keys in the Keychain through `macotron.keychain`, not in plugin source or git.

## Foundation Models

When Apple Foundation Models are available, plugins can call `macotron.ai.local()`. Full polish of on-device models is out of scope for host-shell v1. The host exposes the API when the system supports it.

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
