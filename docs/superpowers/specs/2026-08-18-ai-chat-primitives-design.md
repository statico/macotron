# AI Chat Primitives Design

**Date:** 2026-08-18  
**Status:** Proposed  
**Scope:** Host API + example plugin only. Not an in-app coding agent.

## Problem

Plugins can open a WKWebView panel and call `macotron.ai.*.chat()`, but a Raycast-like chat needs:

1. **Streaming** — token chunks into the UI while the model runs
2. **Multi-turn** — real message history sent to the provider (not one concatenated string)
3. **Saved chats** — persist conversations across reloads

Today: `.stream` ignores JS `onChunk` (chunks only log); providers take a single `prompt` string; docs/`macotron.d.ts` claim Promises but `AIModule` blocks on a semaphore.

## Non-goals

- In-app agent / tool-calling loop / auto-fix
- Panel chrome (title bar / borderless HUD). Current utility `NSPanel` is fine for v1
- Vision / `image` option (documented but unwired — separate work)
- Gemini provider (still a placeholder)
- New storage module

## Design

### 1. Multi-turn on `macotron.ai`

```js
const ai = macotron.ai.claude();

// Still valid
await ai.chat("Hello");

// Multi-turn
await ai.chat([
  { role: "user", content: "Hi" },
  { role: "assistant", content: "Hello!" },
  { role: "user", content: "What next?" },
], { system: "Be brief." });

await ai.stream(messages, {
  system: "Be brief.",
  onChunk: (chunk) => { /* string delta */ },
});
```

- First arg: `string | Array<{ role: "user"|"assistant", content: string }>`
- `system` stays in options (Anthropic-style), not mixed into the messages array for Claude
- OpenAI maps `system` into its messages array as today
- Invalid roles / empty content → JS TypeError before network

Swift: introduce `AIChatMessage` and change `AIProvider` to take `[AIChatMessage]`. String prompts normalize to one user message at the JS bridge.

### 2. Streaming that reaches JS

- Replace semaphore blocking with `JS_NewPromiseCapability` (same pattern as `shell.run` / `ocr.recognize`)
- `.stream(input, opts)` returns `Promise<string>` (full text)
- `opts.onChunk` is a JS function; each provider chunk is delivered on the main actor via `JS_Call` + `drainJobQueue`
- If `onChunk` is omitted, stream still works; caller only gets the final string

### 3. Saved chats — use existing `localStorage`

No new host API. `localStorage` already persists under the workdir (`data/localStorage.json`).

Example schema (owned by the demo plugin, not the host):

```json
{
  "version": 1,
  "activeId": "uuid",
  "chats": [
    {
      "id": "uuid",
      "title": "Untitled",
      "updatedAt": 1724000000000,
      "messages": [
        { "role": "user", "content": "…" },
        { "role": "assistant", "content": "…" }
      ]
    }
  ]
}
```

Key: `macotron.ai-chat.v1`. Cap list size in the plugin (e.g. 50 chats, trim oldest).

### 4. Demo plugin

Upgrade `Examples/plugins/demo-ai-chat.js` (or workdir copy) to:

- Keep message array in plugin JS
- Stream chunks into the panel via `panel.postMessage`
- Save/load via `localStorage`
- Minimal UI: message list, input, new-chat control (not Raycast polish)

### Architecture

```
Plugin JS ──panel.onMessage──► history[] ──ai.stream(messages,{onChunk})──► Provider
                ▲                      │                                        │
                │                      └──── localStorage.setItem ──────────────┤
                └──── panel.postMessage({type:"chunk"|"done"|"error"}) ◄────────┘
```

## Success criteria

- `await ai.stream(messages, { onChunk })` delivers incremental chunks to JS without blocking the main thread on a semaphore
- Multi-turn requests send a proper messages array to Claude/OpenAI
- Demo chat survives app restart via `localStorage`
- `make build` clean; unit tests cover message normalization without network
