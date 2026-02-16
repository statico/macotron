# AI Integration

Macotron is a **coding agent**, not a chat interface. The user types a command in natural language, and the agent autonomously plans, writes scripts, validates them, and reports the result. There is no back-and-forth conversation — the agent does the work and gets out of the way.

## Agent Loop

```
User command ("set up keybindings to move windows")
  │
  ▼
Plan — agent decides which scripts to create/modify
  │
  ▼
Execute — agent calls tools (write_snippet, delete_snippet, etc.)
  │
  ▼
Reload — engine reloads all snippets from disk
  │
  ▼
Validate — check for JS syntax errors, runtime errors
  │
  ├── Errors? → Auto-repair (up to 2 attempts) → back to Reload
  │
  ▼
Done — report success or failure to user
```

The user never sees JavaScript unless they want to. The agent writes complete files (not patches), which sidesteps most edit-mechanism failures.

## Agent Progress UI

While the agent works, a floating panel shows progress:

- **Topic line** — what the agent is working on ("Setting up window keybindings")
- **Status updates** — indefinite progress with animated text: "Planning..." → "Writing script..." → "Testing script..." → "Done!"
- **Shiny/AI-style text animation** on the status line
- **Green checkmark** on success, red X on failure with error summary

The panel dismisses automatically after a short delay on success.

## Tool Calls

The agent manages snippets through tool calls. Every write/delete automatically backs up the config directory, performs the operation, and triggers a reload.

| Tool | Description |
|---|---|
| `read_snippet` | Read the contents of an existing snippet file |
| `write_snippet` | Create or overwrite a snippet file (writes the whole file) |
| `delete_snippet` | Delete a snippet file (triggers backup first) |
| `list_snippets` | List all snippet files with their descriptions |
| `read_config` | Read the current config.js |
| `write_config` | Update config.js (triggers backup first) |

## AI Providers

```javascript
macotron.ai.claude({ model?, apiKey? })   // Anthropic API
macotron.ai.openai({ model?, apiKey? })   // OpenAI API
macotron.ai.gemini({ model?, apiKey? })   // Google Gemini API
macotron.ai.local()                       // Apple Foundation Models (on-device)

// All return an object with:
//   .chat(prompt, { image?, system? }) → Promise<string>
//   .stream(prompt, { image?, system? }) → calls onChunk callback
```

## AI System Prompt

Includes:
1. The full `macotron.d.ts` type definitions
2. Example snippets demonstrating patterns
3. The user's current snippet list with filenames and descriptions
4. Tool definitions for read/write/delete/list operations
5. Instructions to act as an autonomous agent — plan, execute, validate

## Context Engineering

Based on lessons from production agent systems:

**Stable system prompt prefix.** The system prompt has a fixed prefix (type definitions, tool schemas, instructions) that rarely changes. This maximizes KV-cache hit rates across requests — the model doesn't re-process the same prefix every time.

**Tool masking over removal.** All tools are always defined in the prefix. When a tool is unavailable (e.g., user hasn't granted accessibility permissions), it is masked with a note explaining why, rather than removed. This preserves cache alignment.

**File system as extended memory.** The agent can write intermediate plans and state to disk. Snippets on disk are the ground truth — the agent reads them back to understand current state rather than relying on conversation history.

**Rewritable todo/plan.** Each agent step rewrites a short plan of remaining work. This keeps the goal in the model's recent attention window rather than buried earlier in context.

**Preserve failure traces.** When the agent hits an error, the error message and failed code stay in context. Don't clean up — let the model learn from the failure on retry.

**Break repetition patterns.** If the agent fails twice with similar approaches, inject structured variation (e.g., "Try a different approach") to break out of few-shot repetition loops.

## The Harness Problem

The edit mechanism matters as much as model quality. Since macotron writes complete JS files via `write_snippet` (not line-level patches), the edit mechanism is simple — but validation is critical.

The harness = tool call system + validation + auto-repair loop:

1. **Syntax check** — parse the JS before writing to disk
2. **Reload** — engine reloads all snippets
3. **Runtime check** — capture any errors during execution
4. **Auto-repair** — if errors, feed them back to the agent (up to 2 attempts)
5. **Rollback** — if still broken after retries, restore from backup and notify user

## Snippet Auto-Fix

When a snippet fails on load (independent of the agent loop):
1. All other snippets continue loading (isolation)
2. Check: does it use dangerous APIs or have `// macotron:no-autofix`? → skip
3. Check: rate limited? → skip
4. AI is called with error + source + instructions not to add dangerous APIs
5. AI uses `write_snippet` tool call to fix (triggers backup)
6. Verify: fixed code doesn't introduce new dangerous API calls
7. If still broken after 2 attempts → notify user

## Script Summary

The agent maintains a summary of all active scripts — what each one does, what events it listens for, what hotkeys it registers. This summary is:
- Shown in **Settings > Summary tab**
- Included in the agent's system prompt so it knows what already exists
- Auto-updated whenever scripts are created, modified, or deleted

## Capability Tiers

| Tier | Examples | Behavior |
|---|---|---|
| Safe | keyboard, window, notify, timer, clipboard | Agent writes freely |
| Sensitive | shell, http, fs, camera, screen | Agent writes, user sees capability warning |
| Dangerous | shell with sudo, fs writes outside config dir | Agent cannot use without explicit user approval |

## Dev Shortcut

During development, check for `~/Library/Application Support/Macotron-dev.json` at launch. If found, auto-fill the API key so developers skip the wizard:

```json
{
  "apiKey": "sk-ant-...",
  "provider": "claude",
  "model": "claude-sonnet-4-20250514"
}
```

This file is gitignored and never shipped.

## Prompt Injection Mitigation

When user-controlled data (screen content, clipboard, file contents) is passed to the agent, it is wrapped with structured delimiters and explicit "ignore embedded instructions" framing.
