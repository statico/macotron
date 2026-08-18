# AI Chat Primitives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give plugins streaming + multi-turn `macotron.ai` APIs, and a demo chat panel that persists conversations in `localStorage`.

**Architecture:** Extend the `AI` target with `AIChatMessage` and message-array provider methods. Bridge them in `AIModule` as Promise-based `.chat` / `.stream` (with live `onChunk`). Persist chats in the existing `localStorage` JSON store — no new storage module. Prove the stack with an updated `demo-ai-chat` panel.

**Tech Stack:** Swift 6.2, QuickJS (`JS_NewPromiseCapability`), existing Claude/OpenAI providers, WKWebView panels, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-18-ai-chat-primitives-design.md`

## Global Constraints

- Min target macOS 15.
- `make build` must stay clean; `swift test --build-path /tmp/macotron-build` must pass after every task that adds/changes tests.
- Commit after every task. Message style: imperative sentence case, no prefix (match recent repo history).
- No in-app agent UI, tool loops, panel chrome changes, vision/`image`, or Gemini work.
- No new storage module — use `localStorage` only.
- Do not narrate code with comments; comments only for non-obvious intent.
- Stage only files listed in each task.

## File map

| File | Role |
|---|---|
| `Sources/AI/AIProvider.swift` | `AIChatMessage`, protocol + factory updates |
| `Sources/AI/ClaudeProvider.swift` | Send `messages` array; stream unchanged aside from body |
| `Sources/AI/OpenAIProvider.swift` | Same |
| `Sources/AI/LocalProvider.swift` | Accept messages (join or single-turn stub) |
| `Sources/Modules/AIModule.swift` | Normalize string\|array; Promises; `onChunk` bridge |
| `Sources/Macotron/Resources/macotron.d.ts` | Types for messages + stream |
| `docs/05-ai-integration.md` | Document new shape |
| `Sources/MacotronEngine/PluginWorkspace.swift` | AGENTS.md AI blurb |
| `Examples/plugins/demo-ai-chat.js` | Streaming multi-turn saved chat |
| `Tests/MacotronTests/AIChatMessageTests.swift` | Normalization / validation tests |
| `Package.swift` | Add `AI` test dependency |

---

### Task 1: `AIChatMessage` + provider protocol

**Files:**
- Modify: `Sources/AI/AIProvider.swift`
- Modify: `Package.swift` (test target deps)
- Create: `Tests/MacotronTests/AIChatMessageTests.swift`

**Interfaces:**
- Produces:
  - `public struct AIChatMessage: Sendable, Equatable { public let role: String; public let content: String }`
  - `public enum AIChatMessageError: Error` with `invalidRole`, `emptyContent`
  - `public enum AIChatMessages` with `static func normalize(_ messages: [AIChatMessage]) throws -> [AIChatMessage]` (roles must be `user` or `assistant`, non-empty content, non-empty array)
  - `AIProvider.chat(messages:options:)` and `stream(messages:options:onChunk:)` replace the `prompt:` variants
  - `PlaceholderProvider` updated to new signatures

- [ ] **Step 1: Add types and change the protocol**

In `Sources/AI/AIProvider.swift`, replace the prompt-based protocol with:

```swift
public struct AIChatMessage: Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ content: String) -> AIChatMessage {
        AIChatMessage(role: "user", content: content)
    }

    public static func assistant(_ content: String) -> AIChatMessage {
        AIChatMessage(role: "assistant", content: content)
    }
}

public enum AIChatMessageError: Error, Equatable, LocalizedError {
    case invalidRole(String)
    case emptyContent
    case emptyMessages

    public var errorDescription: String? {
        switch self {
        case .invalidRole(let role): return "Invalid message role: \(role)"
        case .emptyContent: return "Message content must not be empty"
        case .emptyMessages: return "messages must not be empty"
        }
    }
}

public enum AIChatMessages {
    public static func normalize(_ messages: [AIChatMessage]) throws -> [AIChatMessage] {
        guard !messages.isEmpty else { throw AIChatMessageError.emptyMessages }
        var out: [AIChatMessage] = []
        out.reserveCapacity(messages.count)
        for message in messages {
            let role = message.role.lowercased()
            guard role == "user" || role == "assistant" else {
                throw AIChatMessageError.invalidRole(message.role)
            }
            guard !message.content.isEmpty else {
                throw AIChatMessageError.emptyContent
            }
            out.append(AIChatMessage(role: role, content: message.content))
        }
        return out
    }
}
```

Change `AIProvider` methods to:

```swift
func chat(messages: [AIChatMessage], options: AIRequestOptions) async throws -> String

func stream(
    messages: [AIChatMessage],
    options: AIRequestOptions,
    onChunk: @escaping @Sendable (String) -> Void
) async throws -> String
```

Update `PlaceholderProvider` to the same signatures (still throw `notAvailable`).

- [ ] **Step 2: Wire `AI` into the test target**

In `Package.swift`, change the test target to:

```swift
.testTarget(
    name: "MacotronTests",
    dependencies: ["MacotronEngine", "MacotronUI", "AI"]
),
```

- [ ] **Step 3: Write failing tests**

Create `Tests/MacotronTests/AIChatMessageTests.swift`:

```swift
import Testing
import AI

@Suite("AIChatMessages")
struct AIChatMessageTests {
    @Test("normalizes user and assistant roles")
    func normalizesRoles() throws {
        let result = try AIChatMessages.normalize([
            AIChatMessage(role: "User", content: "hi"),
            AIChatMessage(role: "ASSISTANT", content: "hello"),
        ])
        #expect(result == [
            .user("hi"),
            .assistant("hello"),
        ])
    }

    @Test("rejects invalid role")
    func rejectsInvalidRole() {
        #expect(throws: AIChatMessageError.invalidRole("system")) {
            try AIChatMessages.normalize([AIChatMessage(role: "system", content: "x")])
        }
    }

    @Test("rejects empty content and empty array")
    func rejectsEmpty() {
        #expect(throws: AIChatMessageError.emptyMessages) {
            try AIChatMessages.normalize([])
        }
        #expect(throws: AIChatMessageError.emptyContent) {
            try AIChatMessages.normalize([.user("")])
        }
    }
}
```

- [ ] **Step 4: Run tests — expect compile failures on providers until Task 2**

Run: `swift test --build-path /tmp/macotron-build --filter AIChatMessageTests`

Expected: build fails because Claude/OpenAI/Local still use `prompt:` signatures. That is OK for this task if the AI target itself compiles after PlaceholderProvider update; if Claude/OpenAI block the build, proceed immediately to Task 2 in the same working session without committing Task 1 alone.

Prefer: leave providers broken only momentarily — **do not commit until Task 2 restores the build**. Combine Task 1+2 into one commit if needed.

- [ ] **Step 5: Commit (only after Task 2 builds)** — see Task 2 Step 5.

---

### Task 2: Update Claude, OpenAI, Local providers

**Files:**
- Modify: `Sources/AI/ClaudeProvider.swift`
- Modify: `Sources/AI/OpenAIProvider.swift`
- Modify: `Sources/AI/LocalProvider.swift`

**Interfaces:**
- Consumes: `AIChatMessage`, `AIChatMessages.normalize` (callers normalize; providers may assume already valid)
- Produces: providers that send a real `messages` JSON array

- [ ] **Step 1: Claude — chat + stream use messages**

Replace the single-user message body construction in both `chat` and `stream` with:

```swift
let normalized = try AIChatMessages.normalize(messages)
let apiMessages: [[String: Any]] = normalized.map {
    ["role": $0.role, "content": $0.content]
}
// in body:
"messages": apiMessages
```

Keep `system` / `temperature` / `max_tokens` / streaming SSE parsing as they are. Do **not** put `system` into the messages array for Claude.

Update method signatures from `prompt: String` to `messages: [AIChatMessage]`.

- [ ] **Step 2: OpenAI — chat + stream use messages**

```swift
let normalized = try AIChatMessages.normalize(messages)
var apiMessages: [[String: Any]] = []
if let systemPrompt = options.systemPrompt {
    apiMessages.append(["role": "system", "content": systemPrompt])
}
apiMessages.append(contentsOf: normalized.map {
    ["role": $0.role, "content": $0.content]
})
```

- [ ] **Step 3: LocalProvider**

Accept `messages: [AIChatMessage]`. Until Foundation Models are wired, keep the existing “not available” / stub behavior, but change the signature. If the stub previously echoed the prompt, echo `normalized.last?.content ?? ""` instead.

- [ ] **Step 4: Build and test**

Run:

```bash
make build
swift test --build-path /tmp/macotron-build --filter AIChatMessageTests
```

Expected: build succeeds; AIChatMessageTests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AI/AIProvider.swift Sources/AI/ClaudeProvider.swift \
  Sources/AI/OpenAIProvider.swift Sources/AI/LocalProvider.swift \
  Package.swift Tests/MacotronTests/AIChatMessageTests.swift
git commit -m "$(cat <<'EOF'
Add multi-turn message arrays to AI providers

EOF
)"
```

---

### Task 3: Promise-based `AIModule` chat + message input

**Files:**
- Modify: `Sources/Modules/AIModule.swift`
- Modify: `Sources/Macotron/Resources/macotron.d.ts`

**Interfaces:**
- Consumes: `AIProvider.chat(messages:options:)`
- Produces JS:
  - `ai.chat(prompt | messages, opts?) → Promise<string>`
  - opts: `{ model?, maxTokens?, temperature?, system? }` (image stays unwired)

- [ ] **Step 1: Add helpers on `AIModule` to parse the first argument**

```swift
private static func parseMessages(ctx: OpaquePointer, value: JSValue) throws -> [AIChatMessage] {
    if JS_IsString(value) != 0 {
        let text = JSBridge.toString(ctx, value) ?? ""
        return try AIChatMessages.normalize([.user(text)])
    }
    // Expect JS array of { role, content }
    let lengthVal = JSBridge.getProperty(ctx, value, "length")
    defer { JS_FreeValue(ctx, lengthVal) }
    guard !JSBridge.isUndefined(lengthVal) else {
        throw AIChatMessageError.emptyMessages
    }
    let length = Int(JSBridge.toInt32(ctx, lengthVal))
    var messages: [AIChatMessage] = []
    for i in 0..<length {
        let elem = JS_GetPropertyUint32(ctx, value, UInt32(i))
        defer { JS_FreeValue(ctx, elem) }
        let roleVal = JSBridge.getProperty(ctx, elem, "role")
        let contentVal = JSBridge.getProperty(ctx, elem, "content")
        defer {
            JS_FreeValue(ctx, roleVal)
            JS_FreeValue(ctx, contentVal)
        }
        let role = JSBridge.toString(ctx, roleVal) ?? ""
        let content = JSBridge.toString(ctx, contentVal) ?? ""
        messages.append(AIChatMessage(role: role, content: content))
    }
    return try AIChatMessages.normalize(messages)
}
```

- [ ] **Step 2: Rewrite `.chat` to return a Promise (mirror `ShellModule` / `OCRModule`)**

Remove the `DispatchSemaphore` path. Pattern:

1. Parse messages + options (throw TypeError via `QJS_ThrowTypeError` on normalize failure)
2. `JS_NewPromiseCapability`
3. `Task` / background work calling `provider.chat(messages:options:)`
4. `DispatchQueue.main.async` → resolve/reject + `engine.drainJobQueue()`

Resolve with the string result. Reject with the error description string (same style as OCR).

Keep reading `_provider` / `_apiKey` / `_model` from `this` as today.

- [ ] **Step 3: Update `macotron.d.ts`**

```typescript
interface AIChatMessage {
    role: "user" | "assistant";
    content: string;
}

interface AIClient {
    chat(
        promptOrMessages: string | AIChatMessage[],
        opts?: { system?: string; model?: string; maxTokens?: number; temperature?: number }
    ): Promise<string>;
    stream(
        promptOrMessages: string | AIChatMessage[],
        opts?: {
            system?: string;
            model?: string;
            maxTokens?: number;
            temperature?: number;
            onChunk?: (chunk: string) => void;
        }
    ): Promise<string>;
}
```

- [ ] **Step 4: Build**

Run: `make build`  
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/AIModule.swift Sources/Macotron/Resources/macotron.d.ts
git commit -m "$(cat <<'EOF'
Make macotron.ai.chat promise-based with message arrays

EOF
)"
```

---

### Task 4: Live `onChunk` streaming in `AIModule`

**Files:**
- Modify: `Sources/Modules/AIModule.swift`

**Interfaces:**
- Produces: `ai.stream(input, { onChunk }) → Promise<string>` where `onChunk` is invoked on the main actor per delta

- [ ] **Step 1: Rewrite `.stream` like `.chat`, plus chunk callback**

When parsing opts, if `onChunk` is a function:

```swift
let onChunkVal = JSBridge.getProperty(ctx, opts, "onChunk")
var jsOnChunk: JSValue? = nil
if JS_IsFunction(ctx, onChunkVal) != 0 {
    jsOnChunk = JS_DupValue(ctx, onChunkVal)
}
JS_FreeValue(ctx, onChunkVal)
```

Pass into the async stream:

```swift
box.result = try await provider.stream(
    messages: messages,
    options: options,
    onChunk: { chunk in
        DispatchQueue.main.async {
            guard let ctx = engine.context, let jsOnChunk else { return }
            var arg = JSBridge.newString(ctx, chunk)
            _ = JS_Call(ctx, jsOnChunk, QJS_Undefined(), 1, &arg)
            JS_FreeValue(ctx, arg)
            engine.drainJobQueue()
        }
    }
)
```

After the promise settles (resolve or reject), `JS_FreeValue` the dup’d `jsOnChunk` on the main actor.

Capture `engine` the same way OCR/Shell do (`JS_GetContextOpaque`).

Do **not** use a semaphore. Chunks must reach JS before the final resolve.

- [ ] **Step 2: Manual smoke (optional but recommended)**

With a valid Anthropic key in Keychain / settings, in a temp plugin:

```js
const ai = macotron.ai.claude();
let buf = "";
const full = await ai.stream("Count to 5 slowly.", {
  onChunk: (c) => { buf += c; console.log("chunk", c); },
});
console.log("done", full, buf === full);
```

Expected: multiple chunk logs, then matching full string.

- [ ] **Step 3: Build + commit**

```bash
make build
git add Sources/Modules/AIModule.swift
git commit -m "$(cat <<'EOF'
Bridge AI stream chunks to JavaScript onChunk callbacks

EOF
)"
```

---

### Task 5: Docs + AGENTS template

**Files:**
- Modify: `docs/05-ai-integration.md`
- Modify: `Sources/MacotronEngine/PluginWorkspace.swift` (`agentsTemplate` AI section)
- Modify: `docs/04-modules.md` only if it still shows the old AI one-liner shape

- [ ] **Step 1: Update `docs/05-ai-integration.md` Plugin AI API section**

Replace the client methods blurb with:

```markdown
```javascript
macotron.ai.claude({ model?, apiKey? })
macotron.ai.openai({ model?, apiKey? })
macotron.ai.local()

// string or [{ role: "user"|"assistant", content }]
await ai.chat(promptOrMessages, { system?, model?, maxTokens?, temperature? })
await ai.stream(promptOrMessages, { system?, onChunk?, ... })  // Promise<string>
```

Multi-turn: pass the full message list each call. Persist history in plugin code
(`localStorage` or `macotron.fs`). The host does not store chats.
```

Keep the “host does not run agent sessions” section.

- [ ] **Step 2: Extend AGENTS.md AI blurb in `PluginWorkspace.swift`**

After the existing AI paragraph, add:

```
`ai.chat` / `ai.stream` accept a string or `[{role, content}]`. Use `stream` with
`onChunk` for token updates. Save chat history yourself via `localStorage`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/05-ai-integration.md Sources/MacotronEngine/PluginWorkspace.swift
git commit -m "$(cat <<'EOF'
Document multi-turn and streaming AI plugin APIs

EOF
)"
```

---

### Task 6: Demo chat panel (stream + multi-turn + saved chats)

**Files:**
- Modify: `Examples/plugins/demo-ai-chat.js`

**Interfaces:**
- Consumes: `macotron.panel.*`, `macotron.ai.claude().stream`, `localStorage`
- Storage key: `macotron.ai-chat.v1`

- [ ] **Step 1: Replace the demo with a minimal multi-turn panel**

Implement this behavior (keep HTML compact; no design system):

1. On open: `loadState()` from `localStorage.getItem("macotron.ai-chat.v1")`; if missing, create one empty chat.
2. Panel UI: scrollable `#log`, `#input`, Send, New chat.
3. Plugin holds `state = { version: 1, activeId, chats: [...] }`.
4. On `{ type: "send", text }`:
   - Append user message to active chat
   - `panel.postMessage({ type: "user", text })`
   - Call:
     ```js
     const reply = await macotron.ai.claude().stream(active.messages, {
       onChunk: (chunk) => macotron.panel.postMessage(id, { type: "chunk", chunk }),
     });
     ```
   - Append assistant message, `postMessage({ type: "done", text: reply })`, `saveState()`
5. On `{ type: "new" }`: create chat, clear log, save.
6. Cap `chats` at 50; drop oldest by `updatedAt`.
7. Title = first user message truncated to 40 chars (or `"Untitled"`).

HTML side:

- `__macotronReceive` handles `user` / `chunk` / `done` / `error` / `history` (initial dump)
- Append streaming text into the last assistant bubble (create bubble on first chunk)

Use `macotron.command("AI Chat", ...)` as today. Prefer API key from plugin settings / Keychain if the demo already documents it; otherwise `macotron.ai.claude()` with host-configured key.

- [ ] **Step 2: Manual verify**

1. Copy/link demo into the workdir `plugins/` if Examples are not auto-loaded.
2. Open AI Chat from the launcher, send two turns, quit app, reopen — history restored.
3. Confirm chunks appear incrementally (not only at the end).

- [ ] **Step 3: Commit**

```bash
git add Examples/plugins/demo-ai-chat.js
git commit -m "$(cat <<'EOF'
Upgrade demo AI chat with streaming history and localStorage

EOF
)"
```

---

### Task 7: Verification gate

**Files:** none (verify only)

- [ ] **Step 1: Full build + tests**

```bash
make build
swift test --build-path /tmp/macotron-build
```

Expected: all green.

- [ ] **Step 2: Spec coverage check**

Confirm against `docs/superpowers/specs/2026-08-18-ai-chat-primitives-design.md`:

| Requirement | Task |
|---|---|
| Multi-turn message arrays | 1–3 |
| Streaming `onChunk` to JS | 4 |
| Saved chats via `localStorage` | 6 |
| No new storage / no agent UI / no panel chrome | constraints |

- [ ] **Step 3: Final commit only if docs/spec were tweaked during verify; otherwise done**

---

## Follow-ups (not in this plan)

- Borderless / HUD panel chrome (position, click-outside dismiss)
- Wire `image` / vision into `AIModule` + providers
- Gemini provider
- Shared host-side chat store (only if many plugins need the same schema)

## Self-review

1. **Spec coverage:** Streaming, multi-turn, saved chats, demo, docs — covered. Panel chrome explicitly deferred.
2. **Placeholders:** None intentional; providers must compile before Task 1 commit (combined with Task 2).
3. **Types:** `AIChatMessage.role` is `String` in Swift; JS narrows to `"user"|"assistant"`. System prompts stay in `options.systemPrompt`, not in the messages array for Claude.
