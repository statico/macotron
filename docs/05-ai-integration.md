# AI Integration

The AI is the **primary configuration interface.** Most users never see JavaScript — they describe what they want, the AI writes it, and it just works.

## AI File Management via Tool Calls

The AI manages snippets through **tool calls**, not direct file system access. This provides an audit trail, enables the backup/rollback system, and ensures proper validation before any file is written.

### Available Tools

The AI is given these tools when processing user requests:

| Tool | Description |
|---|---|
| `read_snippet` | Read the contents of an existing snippet file |
| `write_snippet` | Create or overwrite a snippet file (triggers backup first) |
| `delete_snippet` | Delete a snippet file (triggers backup first) |
| `list_snippets` | List all snippet files with their descriptions |
| `read_config` | Read the current config.js |
| `write_config` | Update config.js (triggers backup first) |

Every write/delete tool call automatically:
1. Compresses and backs up the entire `~/.macotron/` directory
2. Performs the file operation
3. Triggers a reload of all snippets

### The Invisible-JS Flow

```
User: "tile my windows with keyboard shortcuts"
  │
  ▼
AI understands intent, knows the macotron API (via system prompt)
  │
  ▼
AI generates JS, explains what it'll do in plain English
  │
  ▼
Capability review: static analysis extracts which APIs the code uses
  │
  ▼
User sees:  "I'll add keyboard shortcuts for window tiling:
             • Ctrl+Opt+← → Left half
             • Ctrl+Opt+→ → Right half
             • Ctrl+Opt+↵ → Maximize"
            [Enable]  [Show code]  [Cancel]
  │
  ▼
User clicks [Enable]
  │
  ▼
AI calls write_snippet tool → backs up config → writes file
  │
  ▼
Auto-reload → shortcuts are live immediately
```

For snippets using **dangerous APIs**, the UI shows capabilities:

```
User sees:  "I'll watch for camera activation and send an HTTP request:
             ⚠ This snippet will use: http (network requests)"
            [Approve & Enable]  [Show code]  [Cancel]
```

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
5. Instructions to explain behavior in plain English, never leading with code

## Snippet Auto-Fix

When a snippet fails on load:
1. All other snippets continue loading (isolation)
2. Check: does it use dangerous APIs or have `// macotron:no-autofix`? → skip
3. Check: rate limited? → skip
4. AI is called with error + source + instructions not to add dangerous APIs
5. AI uses `write_snippet` tool call to fix (triggers backup)
6. Verify: fixed code doesn't introduce new dangerous API calls
7. If still broken after 2 attempts → notify user

## Prompt Injection Mitigation

When user-controlled data (screen content, clipboard, file contents) is passed to AI, it is wrapped with structured delimiters and explicit "ignore embedded instructions" framing.
