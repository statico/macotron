# Command Arguments and Per-Command Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plugins declare arguments on launcher commands (count + unit for lorem ipsum), and users assign a global shortcut to any command from Settings.

**Architecture:** Extend `macotron.command` with an optional `opts` object (`id`, `arguments`). The engine stores `RegisteredCommand` keyed by a stable id. The launcher stays open and shows a small form when a command has arguments. Command shortcuts live in `settings.json` as `commandShortcuts` and install on the existing `KeyboardModule` event tap (not `GlobalHotkey`, which is a single combo).

**Tech Stack:** Swift 6.2 (strict concurrency, MainActor default), QuickJS via CQuickJS, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-18-command-args-and-shortcuts-design.md`

## Global Constraints

- Stay on plugin API `1.0.0` (not released). Three-argument `macotron.command(name, description, handler)` must keep working.
- Nested command views, password arguments, leftover-query parsing, and a launcher “set shortcut” action are out of scope.
- `make build` must stay clean; `swift test --build-path /tmp/macotron-build` must pass after every task.
- Commit after every task. Message style: imperative sentence case, no prefix.
- No comments that narrate what code does; comments only for non-obvious intent.
- One combo maps to one command. Host bindings win over plugin `keyboard.on` when both match.

## File map

| File | Responsibility |
|---|---|
| Create `Sources/MacotronEngine/CommandArguments.swift` | Argument spec parse + value resolve |
| Create `Sources/MacotronEngine/CommandShortcuts.swift` | id → combo map, reassign, JSON round-trip |
| Create `Sources/MacotronUI/LauncherSession.swift` | Pending argument-mode for shortcut → launcher |
| Create `Tests/MacotronTests/CommandArgumentTests.swift` | Parse, resolve, register, invoke |
| Create `Tests/MacotronTests/CommandShortcutsTests.swift` | Assign / reassign / persist |
| Create `Examples/plugins/demo-lorem.js` | Lorem ipsum command with count + unit |
| Modify `Sources/MacotronEngine/Engine.swift` | `RegisteredCommand`, 4-arg register, `invokeCommand` |
| Modify `Sources/Macotron/Resources/macotron-runtime.js` | Pass `opts` through |
| Modify `Sources/Macotron/Resources/macotron.d.ts` | New `command` overload |
| Modify `Sources/MacotronUI/LauncherView.swift` | Argument form |
| Modify `Sources/Modules/KeyboardModule.swift` | Host bindings on the existing tap |
| Modify `Sources/MacotronUI/SettingsView.swift` | Per-command recorder |
| Modify `Sources/Macotron/AppDelegate.swift` | Search id, invoke, shortcuts, reload |
| Modify `Sources/MacotronEngine/PluginWorkspace.swift` | `commandShortcuts` default + AGENTS.md |
| Modify `Sources/Macotron/DebugServer.swift` | Include `id` and `arguments` |
| Modify tests that look up commands by name |

---

### Task 1: Command model (id, plugin file, argument specs)

**Files:**
- Create: `Sources/MacotronEngine/CommandArguments.swift`
- Modify: `Sources/MacotronEngine/Engine.swift`
- Modify: `Sources/Macotron/Resources/macotron-runtime.js`
- Modify: `Tests/MacotronTests/EngineTests.swift`
- Modify: `Tests/MacotronTests/PluginEnableTests.swift`
- Test: `Tests/MacotronTests/CommandArgumentTests.swift`

**Interfaces:**
- Produces: `CommandArgumentSpec`, `CommandArgumentChoice`, `CommandArgumentSpec.parseList(_:)`, `RegisteredCommand`, registry keyed by `id`, `$$__registerCommand(name, desc, handler, opts?)`

- [ ] **Step 1: Write failing tests**

Create `Tests/MacotronTests/CommandArgumentTests.swift`:

```swift
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Command arguments")
struct CommandArgumentTests {
    @Test("eval without a plugin file keys the registry by name")
    func evalUsesNameAsId() {
        let engine = Engine()
        engine.evaluate("""
            $$__registerCommand("greet", "Says hello", function() {}, {});
        """)
        #expect(engine.commandRegistry["greet"] != nil)
        #expect(engine.commandRegistry["greet"]?.id == "greet")
        #expect(engine.commandRegistry["greet"]?.name == "greet")
        #expect(engine.commandRegistry["greet"]?.pluginFile == "")
        #expect(engine.commandRegistry["greet"]?.arguments.isEmpty == true)
    }

    @Test("plugin file prefixes the default id")
    func pluginFilePrefixesId() {
        let engine = Engine()
        engine.currentEvaluatingFile = "lorem.js"
        engine.evaluate("""
            $$__registerCommand("Generate Lorem Ipsum", "text", function() {}, {});
        """)
        #expect(engine.commandRegistry["lorem.js/Generate Lorem Ipsum"] != nil)
        #expect(engine.commandRegistry["Generate Lorem Ipsum"] == nil)
    }

    @Test("opts.id overrides the default id")
    func explicitIdWins() {
        let engine = Engine()
        engine.currentEvaluatingFile = "lorem.js"
        engine.evaluate("""
            $$__registerCommand("Generate Lorem Ipsum", "text", function() {}, { id: "lorem-ipsum" });
        """)
        #expect(engine.commandRegistry["lorem-ipsum"] != nil)
        #expect(engine.commandRegistry["lorem-ipsum"]?.name == "Generate Lorem Ipsum")
    }

    @Test("parses text, number, and dropdown arguments")
    func parsesArgumentSpecs() {
        let engine = Engine()
        engine.evaluate("""
            $$__registerCommand("Lorem", "text", function() {}, {
              arguments: [
                { name: "count", type: "number", placeholder: "Count", default: 3 },
                { name: "unit", type: "dropdown", placeholder: "Unit", default: "words",
                  choices: [
                    { title: "Words", value: "words" },
                    { label: "Paragraphs", value: "paragraphs" }
                  ]
                }
              ]
            });
        """)
        let args = engine.commandRegistry["Lorem"]?.arguments ?? []
        #expect(args.count == 2)
        #expect(args[0].name == "count")
        #expect(args[0].type == "number")
        #expect(args[0].placeholder == "Count")
        #expect(args[0].required == false)
        if case .number(let n) = args[0].defaultValue { #expect(n == 3) } else { Issue.record("count default") }
        #expect(args[1].choices.map(\.value) == ["words", "paragraphs"])
        #expect(args[1].choices.map(\.title) == ["Words", "Paragraphs"])
    }

    @Test("skips arguments with no name and dropdowns with no choices")
    func skipsInvalidArguments() {
        let list = CommandArgumentSpec.parseList([
            ["type": "text"],
            ["name": "ok", "type": "text"],
            ["name": "empty-dd", "type": "dropdown"],
        ])
        #expect(list.map(\.name) == ["ok"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-path /tmp/macotron-build --filter CommandArgumentTests`

Expected: FAIL (no `RegisteredCommand` / `CommandArgumentSpec`)

- [ ] **Step 3: Add CommandArguments.swift**

```swift
import Foundation

public struct CommandArgumentChoice: Sendable, Equatable {
    public let title: String
    public let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

public enum CommandArgDefault: Sendable, Equatable {
    case none
    case string(String)
    case number(Double)
    case bool(Bool)
}

public struct CommandArgumentSpec: Sendable {
    public let name: String
    public let type: String
    public let placeholder: String
    public let required: Bool
    public let defaultValue: CommandArgDefault
    public let choices: [CommandArgumentChoice]

    public init(
        name: String,
        type: String,
        placeholder: String,
        required: Bool = false,
        defaultValue: CommandArgDefault = .none,
        choices: [CommandArgumentChoice] = []
    ) {
        self.name = name
        self.type = type
        self.placeholder = placeholder
        self.required = required
        self.defaultValue = defaultValue
        self.choices = choices
    }

    public static func parseList(_ raw: Any?) -> [CommandArgumentSpec] {
        guard let items = raw as? [Any] else { return [] }
        var result: [CommandArgumentSpec] = []
        for item in items {
            guard let dict = item as? [String: Any] else { continue }
            guard let name = dict["name"] as? String, !name.isEmpty else { continue }
            var type = (dict["type"] as? String)?.lowercased() ?? "text"
            if type != "text" && type != "number" && type != "dropdown" {
                type = "text"
            }
            let placeholder = (dict["placeholder"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
            let required = dict["required"] as? Bool ?? false
            let defaultValue = parseDefault(dict["default"])
            var choices: [CommandArgumentChoice] = []
            if type == "dropdown" {
                choices = parseChoices(dict["choices"])
                if choices.isEmpty {
                    NSLog("[Macotron] command argument '%@' dropdown has no choices — skipped", name)
                    continue
                }
            }
            result.append(CommandArgumentSpec(
                name: name,
                type: type,
                placeholder: placeholder,
                required: required,
                defaultValue: defaultValue,
                choices: choices
            ))
        }
        return result
    }

    private static func parseDefault(_ raw: Any?) -> CommandArgDefault {
        switch raw {
        case let s as String: return .string(s)
        case let i as Int: return .number(Double(i))
        case let d as Double: return .number(d)
        case let b as Bool: return .bool(b)
        default: return .none
        }
    }

    private static func parseChoices(_ raw: Any?) -> [CommandArgumentChoice] {
        guard let items = raw as? [Any] else { return [] }
        var result: [CommandArgumentChoice] = []
        for item in items {
            guard let dict = item as? [String: Any] else { continue }
            guard let value = dict["value"] as? String, !value.isEmpty else { continue }
            let title = (dict["title"] as? String) ?? (dict["label"] as? String) ?? value
            result.append(CommandArgumentChoice(title: title, value: value))
        }
        return result
    }
}
```

- [ ] **Step 4: Replace the command registry in Engine.swift**

Replace the tuple registry and `$$__registerCommand` (arity 3 → 4). Add `RegisteredCommand` above `Engine`:

```swift
public struct RegisteredCommand {
    public let id: String
    public let name: String
    public let description: String
    public let pluginFile: String
    public let arguments: [CommandArgumentSpec]
    public var callback: JSValue
}
```

Replace `commandRegistry` with:

```swift
    public var commandRegistry: [String: RegisteredCommand] = [:]
```

Replace the `$$__registerCommand` C function with:

```swift
        JS_SetPropertyStr(context, global, "$$__registerCommand",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 3 else { return QJS_Undefined() }
                let name = JSBridge.toString(ctx, argv[0]) ?? ""
                let desc = JSBridge.toString(ctx, argv[1]) ?? ""
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                let callback = JS_DupValue(ctx, argv[2])

                var opts: [String: Any] = [:]
                if argc >= 4, !JSBridge.isUndefined(argv[3]), !JSBridge.isNull(argv[3]) {
                    opts = JSBridge.jsToSwift(ctx, argv[3]) as? [String: Any] ?? [:]
                }

                let pluginFile = engine.currentEvaluatingFile ?? ""
                var commandID = pluginFile.isEmpty ? name : "\(pluginFile)/\(name)"
                if let explicit = opts["id"] as? String, !explicit.isEmpty {
                    commandID = explicit
                }
                let arguments = CommandArgumentSpec.parseList(opts["arguments"])

                if engine.commandRegistry[commandID] != nil {
                    NSLog("[Macotron] command id '%@' overwritten", commandID)
                }

                engine.commandRegistry[commandID] = RegisteredCommand(
                    id: commandID,
                    name: name,
                    description: desc,
                    pluginFile: pluginFile,
                    arguments: arguments,
                    callback: callback
                )
                return QJS_Undefined()
            }, "$$__registerCommand", 4))
```

`reset()` already does `cmd.callback` — that still compiles.

- [ ] **Step 5: Pass opts from macotron-runtime.js**

```js
macotron.command = function(name, description, handler, opts) {
    $$__registerCommand(name, description, handler, opts || {});
};
```

- [ ] **Step 6: Update existing tests that key the registry by name**

In `Tests/MacotronTests/PluginEnableTests.swift`, change lookups to the prefixed ids:

```swift
        #expect(engine.commandRegistry["a-enabled.js/enabled-cmd"] != nil)
        #expect(engine.commandRegistry["b-disabled.js/disabled-cmd"] == nil)
```

and:

```swift
        #expect(engine.commandRegistry["regression.js/regression-cmd"] != nil)
```

`EngineTests.testRegisterCommand` still uses `"greet"` (no `currentEvaluatingFile`). Leave those keys. Add `#expect(engine.commandRegistry["greet"]?.id == "greet")` if you touch that test.

- [ ] **Step 7: Run tests**

Run: `swift test --build-path /tmp/macotron-build --filter CommandArgumentTests --filter PluginEnableTests --filter EngineTests`

Expected: PASS

Also run `make build` and fix `AppDelegate.swift` / `DebugServer.swift` compile errors from the tuple → struct change:

`AppDelegate.search`: `SearchResult(id: cmd.id, title: cmd.name, ...)`

`AppDelegate.executeCommand`: still `engine.commandRegistry[id]` then `cmd.callback` — field name is unchanged.

`DebugServer /commands`:

```swift
            let cmds = engine.commandRegistry.map { (key, val) in
                [
                    "id": val.id,
                    "name": val.name,
                    "description": val.description,
                    "arguments": val.arguments.map(\.name),
                ] as [String: Any]
            }
```

- [ ] **Step 8: Commit**

```bash
git add Sources/MacotronEngine/CommandArguments.swift Sources/MacotronEngine/Engine.swift \
  Sources/Macotron/Resources/macotron-runtime.js Sources/Macotron/AppDelegate.swift \
  Sources/Macotron/DebugServer.swift Tests/MacotronTests/CommandArgumentTests.swift \
  Tests/MacotronTests/EngineTests.swift Tests/MacotronTests/PluginEnableTests.swift
git commit -m "$(cat <<'EOF'
Key launcher commands by a stable id and parse argument specs

EOF
)"
```

---

### Task 2: Resolve argument values and invoke the handler

**Files:**
- Modify: `Sources/MacotronEngine/CommandArguments.swift`
- Modify: `Sources/MacotronEngine/Engine.swift`
- Modify: `Tests/MacotronTests/CommandArgumentTests.swift`

**Interfaces:**
- Consumes: `CommandArgumentSpec`
- Produces: `CommandArgumentResolver.resolve(specs:raw:) -> Result<[String: Any], CommandArgumentResolver.Failure>`, `Engine.invokeCommand(_:args:) -> Bool`

- [ ] **Step 1: Write failing tests**

Append to `CommandArgumentTests.swift`:

```swift
    @Test("resolver fills defaults and coerces numbers")
    func resolverUsesDefaults() {
        let specs = [
            CommandArgumentSpec(name: "count", type: "number", placeholder: "Count", defaultValue: .number(3)),
            CommandArgumentSpec(
                name: "unit", type: "dropdown", placeholder: "Unit",
                defaultValue: .string("words"),
                choices: [CommandArgumentChoice(title: "Words", value: "words")]
            ),
        ]
        let result = CommandArgumentResolver.resolve(specs: specs, raw: [:])
        guard case .success(let values) = result else {
            Issue.record("expected success")
            return
        }
        #expect(values["count"] as? Int == 3)
        #expect(values["unit"] as? String == "words")
    }

    @Test("resolver rejects missing required args")
    func resolverRejectsMissingRequired() {
        let specs = [
            CommandArgumentSpec(name: "q", type: "text", placeholder: "Query", required: true),
        ]
        let result = CommandArgumentResolver.resolve(specs: specs, raw: [:])
        guard case .failure(.missingRequired("q")) = result else {
            Issue.record("expected missingRequired")
            return
        }
    }

    @Test("invokeCommand passes an args object to JS")
    func invokePassesArgs() {
        let engine = Engine()
        engine.evaluate("""
            var seen = null;
            $$__registerCommand("echo", "echo", function(args) { seen = args; }, {});
        """)
        #expect(engine.invokeCommand("echo", args: ["count": 3, "unit": "words"]))
        let seen = engine.evaluate("JSON.stringify(seen)").0
        #expect(seen == "{\"count\":3,\"unit\":\"words\"}" || seen?.contains("\"count\":3") == true)
    }
}
```

JSON key order is not stable. Assert with:

```swift
        let unit = engine.evaluate("seen.unit").0
        let count = engine.evaluate("String(seen.count)").0
        #expect(unit == "words")
        #expect(count == "3")
```

Check `Engine.evaluate` return: `(String?, String?)` — first is the result string. A JS object stringifies as `"[object Object]"` via ToString. Use the property reads above, not `JSON.stringify` unless you eval `JSON.stringify(seen)`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-path /tmp/macotron-build --filter CommandArgumentTests`

Expected: FAIL (`CommandArgumentResolver` / `invokeCommand` missing)

- [ ] **Step 3: Implement the resolver**

Append to `CommandArguments.swift`:

```swift
public enum CommandArgumentResolver {
    public enum Failure: Equatable {
        case missingRequired(String)
        case invalidNumber(String)
        case invalidChoice(String)
    }

    public static func resolve(
        specs: [CommandArgumentSpec],
        raw: [String: String]
    ) -> Result<[String: Any], Failure> {
        var values: [String: Any] = [:]
        for spec in specs {
            let trimmed = (raw[spec.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch spec.type {
            case "number":
                if trimmed.isEmpty {
                    if case .number(let n) = spec.defaultValue {
                        values[spec.name] = intOrDouble(n)
                    } else if spec.required {
                        return .failure(.missingRequired(spec.name))
                    }
                } else if let n = Double(trimmed) {
                    values[spec.name] = intOrDouble(n)
                } else {
                    return .failure(.invalidNumber(spec.name))
                }
            case "dropdown":
                let value: String
                if trimmed.isEmpty {
                    if case .string(let d) = spec.defaultValue {
                        value = d
                    } else if spec.required {
                        return .failure(.missingRequired(spec.name))
                    } else {
                        continue
                    }
                } else {
                    value = trimmed
                }
                if !spec.choices.contains(where: { $0.value == value }) {
                    return .failure(.invalidChoice(spec.name))
                }
                values[spec.name] = value
            default:
                if trimmed.isEmpty {
                    if case .string(let d) = spec.defaultValue {
                        values[spec.name] = d
                    } else if spec.required {
                        return .failure(.missingRequired(spec.name))
                    } else {
                        values[spec.name] = ""
                    }
                } else {
                    values[spec.name] = trimmed
                }
            }
        }
        return .success(values)
    }

    private static func intOrDouble(_ n: Double) -> Any {
        if n.rounded() == n, let i = Int(exactly: n) { return i }
        return n
    }
}
```

- [ ] **Step 4: Add Engine.invokeCommand**

In `Engine.swift`, next to `evaluate`:

```swift
    @discardableResult
    public func invokeCommand(_ id: String, args: [String: Any] = [:]) -> Bool {
        guard let cmd = commandRegistry[id] else { return false }
        var arg = JSBridge.newObject(context, args)
        _ = JS_Call(context, cmd.callback, QJS_Undefined(), 1, &arg)
        JS_FreeValue(context, arg)
        drainJobQueue()
        return true
    }
```

Zero-arg JS handlers ignore the extra object.

- [ ] **Step 5: Point AppDelegate.executeCommand at invokeCommand**

```swift
    private func executeCommand(_ id: String, args: [String: Any] = [:]) {
        if engine.commandRegistry[id] != nil {
            _ = engine.invokeCommand(id, args: args)
            launcherPanel.toggle()
            return
        }

        appSearchProvider.launchApp(bundleID: id)
        launcherPanel.toggle()
    }
```

Keep the `LauncherView` callback as `{ id in self?.executeCommand(id) }` until Task 3.

- [ ] **Step 6: Run tests**

Run: `swift test --build-path /tmp/macotron-build --filter CommandArgumentTests`

Expected: PASS

Run: `make build`

Expected: succeed

- [ ] **Step 7: Commit**

```bash
git add Sources/MacotronEngine/CommandArguments.swift Sources/MacotronEngine/Engine.swift \
  Sources/Macotron/AppDelegate.swift Tests/MacotronTests/CommandArgumentTests.swift
git commit -m "$(cat <<'EOF'
Pass resolved argument values into command handlers

EOF
)"
```

---

### Task 3: Launcher argument form

**Files:**
- Create: `Sources/MacotronUI/LauncherSession.swift`
- Modify: `Sources/MacotronUI/LauncherView.swift`
- Modify: `Sources/Macotron/AppDelegate.swift`
- Modify: `Sources/Macotron/AppSearchProvider.swift` (only if `SearchResult` init gains a parameter — give it a default)

**Interfaces:**
- Consumes: `CommandArgumentSpec`, `CommandArgumentResolver`, `Engine.invokeCommand`
- Produces: `SearchResult.commandArguments`, `LauncherSession.pendingArgs`, `onExecuteCommand: (String, [String: Any]) -> Void`

No unit test for SwiftUI. Verify with `make dev` and `curl -s "http://localhost:7777/screenshot?view=launcher" -o /tmp/launcher.png`.

- [ ] **Step 1: Add LauncherSession**

```swift
import Foundation
import MacotronEngine

@MainActor
public final class LauncherSession: ObservableObject {
    public struct PendingArgs {
        public let commandId: String
        public let title: String
        public let arguments: [CommandArgumentSpec]

        public init(commandId: String, title: String, arguments: [CommandArgumentSpec]) {
            self.commandId = commandId
            self.title = title
            self.arguments = arguments
        }
    }

    @Published public var pendingArgs: PendingArgs?

    public init() {}
}
```

- [ ] **Step 2: Extend SearchResult**

In `LauncherView.swift`, add a property with a default so app results stay unchanged:

```swift
    public let commandArguments: [CommandArgumentSpec]

    public init(
        id: String, title: String, subtitle: String, icon: String, type: ResultType,
        nsImage: NSImage? = nil, appURL: URL? = nil,
        commandArguments: [CommandArgumentSpec] = []
    ) {
        // ...existing assignments...
        self.commandArguments = commandArguments
    }
```

Add `import MacotronEngine` at the top of `LauncherView.swift`.

- [ ] **Step 3: Switch LauncherView into argument mode**

Change the execute callback:

```swift
    public var onExecuteCommand: ((String, [String: Any]) -> Void)?
```

Add session + arg state:

```swift
    @ObservedObject private var session: LauncherSession
    @State private var argValues: [String: String] = [:]
    @State private var argError: String?

    public init(
        prefs: LauncherPrefs = LauncherPrefs(),
        session: LauncherSession = LauncherSession(),
        onExecuteCommand: ((String, [String: Any]) -> Void)? = nil,
        // ...rest unchanged...
    ) {
        self._prefs = ObservedObject(wrappedValue: prefs)
        self._session = ObservedObject(wrappedValue: session)
        // ...
    }
```

In `body`, if `session.pendingArgs != nil`, show the argument form instead of the result list (keep the search row, replace the field with a command chip + “arguments” hint).

Argument form (insert between the search row divider and the results):

```swift
    @ViewBuilder
    private var argumentForm: some View {
        if let pending = session.pendingArgs {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.secondary)
                    Text(pending.title)
                        .font(.system(size: 14 * prefs.textScale, weight: .medium))
                    Spacer()
                    Text("esc")
                        .font(.system(size: 10, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(3)
                    Text("Back")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(pending.arguments, id: \.name) { spec in
                    argumentRow(spec)
                }

                if let argError {
                    Text(argError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
```

`argumentRow`:

- `text` / `number`: `TextField(spec.placeholder, text: binding for argValues[spec.name])`
- `dropdown`: `Picker` over `spec.choices`, tag = `value`

Prefill on entering pending args (`.onChange(of: session.pendingArgs?.commandId)`):

```swift
    private func prefill(_ specs: [CommandArgumentSpec]) {
        var seed: [String: String] = [:]
        for spec in specs {
            switch spec.defaultValue {
            case .string(let s): seed[spec.name] = s
            case .number(let n):
                seed[spec.name] = n.rounded() == n ? String(Int(n)) : String(n)
            case .bool(let b): seed[spec.name] = b ? "true" : "false"
            case .none: seed[spec.name] = ""
            }
        }
        argValues = seed
        argError = nil
    }
```

Change `executeResult`:

```swift
    private func executeResult(_ result: SearchResult) {
        if result.type == .command, !result.commandArguments.isEmpty {
            session.pendingArgs = .init(
                commandId: result.id,
                title: result.title,
                arguments: result.commandArguments
            )
            prefill(result.commandArguments)
            query = ""
            results = []
            return
        }
        onExecuteCommand?(result.id, [:])
    }
```

Change `execute()` so that when `pendingArgs` is set, resolve and submit:

```swift
    private func execute() {
        if let pending = session.pendingArgs {
            switch CommandArgumentResolver.resolve(specs: pending.arguments, raw: argValues) {
            case .success(let values):
                session.pendingArgs = nil
                onExecuteCommand?(pending.commandId, values)
            case .failure(.missingRequired(let name)):
                argError = "\(name) is required"
            case .failure(.invalidNumber(let name)):
                argError = "\(name) must be a number"
            case .failure(.invalidChoice(let name)):
                argError = "\(name) is not a valid choice"
            }
            return
        }
        if selectedIndex < results.count {
            executeResult(results[selectedIndex])
        }
    }
```

Escape: extend `KeyEventHandler` with `onEscape`. If `pendingArgs != nil`, clear it and restore search; otherwise the panel already closes on resign-key. Add `onEscape` to `KeyEventNSView.keyDown` for keyCode `53`.

When `pendingArgs` is set, hide `searchResultsView` (the app list). Show `argumentForm` instead.

- [ ] **Step 4: Wire AppDelegate**

Add `private let launcherSession = LauncherSession()`.

Pass it into `LauncherView`:

```swift
        let launcherView = LauncherView(
            prefs: launcherPrefs,
            session: launcherSession,
            onExecuteCommand: { [weak self] id, args in
                self?.executeCommand(id, args: args)
            },
            // ...
        )
```

In `search`, attach specs:

```swift
                results.append(SearchResult(
                    id: cmd.id,
                    title: cmd.name,
                    subtitle: cmd.description,
                    icon: "terminal.fill",
                    type: .command,
                    commandArguments: cmd.arguments
                ))
```

- [ ] **Step 5: Build and smoke the launcher**

Run: `make build && swift test --build-path /tmp/macotron-build`

Expected: PASS

Manual: `make run`, open the launcher, pick a no-arg command — still runs and closes.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacotronUI/LauncherSession.swift Sources/MacotronUI/LauncherView.swift \
  Sources/Macotron/AppDelegate.swift
git commit -m "$(cat <<'EOF'
Collect command arguments in the launcher before running

EOF
)"
```

---

### Task 4: Lorem ipsum demo plugin

**Files:**
- Create: `Examples/plugins/demo-lorem.js`
- Modify: `Examples/plugins/README.md`

**Interfaces:**
- Consumes: `macotron.command` 4-arg form, `macotron.clipboard.set`, `macotron.notify.show`

- [ ] **Step 1: Write the plugin**

```js
const WORDS = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua".split(" ");

function generate(count, unit) {
    const n = Math.max(1, Number(count) || 1);
    if (unit === "words") {
        return Array.from({ length: n }, (_, i) => WORDS[i % WORDS.length]).join(" ");
    }
    if (unit === "lines") {
        return Array.from({ length: n }, () =>
            Array.from({ length: 8 }, (_, i) => WORDS[i % WORDS.length]).join(" ")
        ).join("\n");
    }
    return Array.from({ length: n }, () => {
        const sentences = Array.from({ length: 4 }, (_, s) => {
            const start = (s * 5) % WORDS.length;
            const body = Array.from({ length: 12 }, (_, i) => WORDS[(start + i) % WORDS.length]).join(" ");
            return body.charAt(0).toUpperCase() + body.slice(1) + ".";
        });
        return sentences.join(" ");
    }).join("\n\n");
}

macotron.command("Generate Lorem Ipsum", "Copy placeholder text to the clipboard", (args) => {
    const text = generate(args.count, args.unit);
    macotron.clipboard.set(text);
    macotron.notify.show("Lorem ipsum", "Copied " + args.count + " " + args.unit);
}, {
    id: "lorem-ipsum",
    arguments: [
        { name: "count", type: "number", placeholder: "Count", default: 3 },
        {
            name: "unit",
            type: "dropdown",
            placeholder: "Unit",
            default: "paragraphs",
            choices: [
                { title: "Words", value: "words" },
                { title: "Lines", value: "lines" },
                { title: "Paragraphs", value: "paragraphs" },
            ],
        },
    ],
});
```

- [ ] **Step 2: List it in Examples/plugins/README.md**

Add a row:

`| demo-lorem.js | command arguments | Generate Lorem Ipsum |`

- [ ] **Step 3: Commit**

```bash
git add Examples/plugins/demo-lorem.js Examples/plugins/README.md
git commit -m "$(cat <<'EOF'
Add a lorem ipsum demo that takes count and unit arguments

EOF
)"
```

Copy `demo-lorem.js` into a workdir `plugins/` folder to try it. `make run`, search “lorem”, Return, confirm the form, Return, paste.

---

### Task 5: Persist commandShortcuts

**Files:**
- Create: `Sources/MacotronEngine/CommandShortcuts.swift`
- Modify: `Sources/MacotronEngine/PluginWorkspace.swift`
- Test: `Tests/MacotronTests/CommandShortcutsTests.swift`

**Interfaces:**
- Produces: `CommandShortcuts.bindings: [String: String]`, `assign(commandId:combo:)`, `clear(commandId:)`, `load(from:)`, `jsonObject()`, `commandId(forCombo:)`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import MacotronEngine

@Suite("Command shortcuts")
struct CommandShortcutsTests {
    @Test("assigning a combo to a second command moves it")
    func reassignMovesCombo() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: "cmd+shift+l")
        table.assign(commandId: "b", combo: "cmd+shift+l")
        #expect(table.bindings["a"] == nil)
        #expect(table.bindings["b"] == "cmd+shift+l")
    }

    @Test("clear removes the binding")
    func clearRemoves() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: "cmd+shift+l")
        table.clear(commandId: "a")
        #expect(table.bindings.isEmpty)
    }

    @Test("round-trips through a JSON object")
    func jsonRoundTrip() {
        var table = CommandShortcuts()
        table.assign(commandId: "lorem-ipsum", combo: "Cmd+Shift+L")
        let loaded = CommandShortcuts.load(from: table.jsonObject())
        #expect(loaded.bindings["lorem-ipsum"] == "cmd+shift+l")
    }

    @Test("empty combo is a clear")
    func emptyComboClears() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: "cmd+shift+l")
        table.assign(commandId: "a", combo: "")
        #expect(table.bindings["a"] == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-path /tmp/macotron-build --filter CommandShortcutsTests`

Expected: FAIL

- [ ] **Step 3: Implement CommandShortcuts.swift**

```swift
import Foundation

public struct CommandShortcuts: Equatable, Sendable {
    public private(set) var bindings: [String: String]

    public init(bindings: [String: String] = [:]) {
        self.bindings = bindings
    }

    public mutating func assign(commandId: String, combo: String) {
        let normalized = combo.lowercased().trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty {
            bindings.removeValue(forKey: commandId)
            return
        }
        bindings = bindings.filter { $0.value != normalized }
        bindings[commandId] = normalized
    }

    public mutating func clear(commandId: String) {
        bindings.removeValue(forKey: commandId)
    }

    public func combo(for commandId: String) -> String {
        bindings[commandId] ?? ""
    }

    public func commandId(forCombo combo: String) -> String? {
        let normalized = combo.lowercased()
        return bindings.first(where: { $0.value == normalized })?.key
    }

    public static func load(from object: Any?) -> CommandShortcuts {
        guard let dict = object as? [String: Any] else { return CommandShortcuts() }
        var bindings: [String: String] = [:]
        for (id, value) in dict {
            guard let combo = value as? String else { continue }
            let normalized = combo.lowercased().trimmingCharacters(in: .whitespaces)
            if !normalized.isEmpty {
                bindings[id] = normalized
            }
        }
        return CommandShortcuts(bindings: bindings)
    }

    public func jsonObject() -> [String: String] {
        bindings
    }
}
```

- [ ] **Step 4: Add the default in PluginWorkspace.swift**

In `defaultSettings`:

```swift
        "commandShortcuts": [:] as [String: String],
```

In the AGENTS.md `settings.json schema` example, add `"commandShortcuts": {}`.

- [ ] **Step 5: Run tests**

Run: `swift test --build-path /tmp/macotron-build --filter CommandShortcutsTests`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/MacotronEngine/CommandShortcuts.swift Sources/MacotronEngine/PluginWorkspace.swift \
  Tests/MacotronTests/CommandShortcutsTests.swift
git commit -m "$(cat <<'EOF'
Store per-command shortcuts in settings.json

EOF
)"
```

---

### Task 6: Host bindings on the keyboard tap

**Files:**
- Modify: `Sources/Modules/KeyboardModule.swift`
- Modify: `Sources/Macotron/AppDelegate.swift`

**Interfaces:**
- Consumes: `CommandShortcuts.bindings`, `KeyboardModule.setHostBindings`
- Produces: `KeyboardModule.onHostCommand: ((String) -> Void)?` — argument is the command id. Host bindings are matched before plugin `keyboard.on` combos.

No CGEventTap unit test (the module is not in the test target). Verification is `make build` plus a manual shortcut after Task 8.

- [ ] **Step 1: Extend KeyboardTapState**

```swift
private struct HostBinding {
    let commandId: String
    let combo: KeyCombo
}

private final class KeyboardTapState: @unchecked Sendable {
    let lock = NSLock()
    var combos: [KeyCombo] = []
    var hostBindings: [HostBinding] = []
    weak var module: KeyboardModule?

    static let shared = KeyboardTapState()
}
```

- [ ] **Step 2: Add the public API on KeyboardModule**

```swift
    public var onHostCommand: ((String) -> Void)?

    public func setHostBindings(_ bindings: [(commandId: String, combo: String)]) {
        let parsed: [HostBinding] = bindings.compactMap { item in
            guard let combo = KeyCombo.parse(item.combo) else {
                NSLog("[Macotron] Skipping invalid command shortcut '%@' for %@", item.combo, item.commandId)
                return nil
            }
            return HostBinding(commandId: item.commandId, combo: combo)
        }
        let state = KeyboardTapState.shared
        state.lock.lock()
        state.hostBindings = parsed
        state.lock.unlock()
    }
```

In `cleanup()`, also `state.hostBindings.removeAll()`.

- [ ] **Step 3: Match host bindings first in the tap callback**

Inside the keyDown branch, after copying `combos`, also copy `hostBindings`. Loop host bindings first:

```swift
            state.lock.lock()
            let combos = state.combos
            let hostBindings = state.hostBindings
            state.lock.unlock()

            for binding in hostBindings {
                if binding.combo.matches(event) {
                    let commandId = binding.commandId
                    DispatchQueue.main.async {
                        KeyboardTapState.shared.module?.onHostCommand?(commandId)
                    }
                    return nil
                }
            }

            for combo in combos {
                // existing plugin keyboard.on path
```

- [ ] **Step 4: Keep a KeyboardModule reference on AppDelegate**

```swift
    private var keyboardModule: KeyboardModule?
```

In `registerModules()`:

```swift
        let keyboard = KeyboardModule()
        keyboard.onTrustFailure = { [weak self] in
            self?.refreshPermissions()
        }
        keyboard.onHostCommand = { [weak self] commandId in
            self?.handleCommandShortcut(commandId)
        }
        self.keyboardModule = keyboard
        engine.addModule(keyboard)
```

Add a stub for now (Task 8 fills it in):

```swift
    private func handleCommandShortcut(_ commandId: String) {
        executeCommand(commandId)
    }

    private func installCommandShortcuts() {
        let table = CommandShortcuts.load(from: workspace.readSettings()["commandShortcuts"])
        let live = table.bindings.filter { engine.commandRegistry[$0.key] != nil }
        keyboardModule?.setHostBindings(live.map { (commandId: $0.key, combo: $0.value) })
    }
```

Call `installCommandShortcuts()` at the end of `registerModules`? No — commands do not exist until `reloadAll()`. Call it from `onDidReload` and after the first `moduleManager.reloadAll()` in `bootstrap`.

```swift
        moduleManager.onDidReload = { [weak self] in
            self?.refreshPermissions()
            self?.applyUIPrefsFromSettings()
            self?.installCommandShortcuts()
        }
```

- [ ] **Step 5: Build**

Run: `make build && swift test --build-path /tmp/macotron-build`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/Modules/KeyboardModule.swift Sources/Macotron/AppDelegate.swift
git commit -m "$(cat <<'EOF'
Install command shortcuts on the shared keyboard event tap

EOF
)"
```

---

### Task 7: Settings UI for per-command shortcuts

**Files:**
- Modify: `Sources/MacotronUI/SettingsView.swift`
- Modify: `Sources/Macotron/AppDelegate.swift`

**Interfaces:**
- Consumes: `CommandShortcuts`, `RegisteredCommand`
- Produces: `ModuleSummary.commands: [PluginCommandSummary]`, `SettingsState.saveCommandShortcut: (String, String) -> Void`

- [ ] **Step 1: Add PluginCommandSummary and SettingsState wiring**

In `SettingsView.swift`:

```swift
public struct PluginCommandSummary: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var shortcut: String

    public init(id: String, name: String, shortcut: String = "") {
        self.id = id
        self.name = name
        self.shortcut = shortcut
    }
}
```

Add to `ModuleSummary`:

```swift
    public let commands: [PluginCommandSummary]
```

Add `commands: [PluginCommandSummary] = []` to the initializer and `self.commands = commands`.

Add to `SettingsState`:

```swift
    public var saveCommandShortcut: ((_ commandId: String, _ combo: String) -> Void)?
```

- [ ] **Step 2: Render command rows on PluginDetailView**

Inside the enabled branch, after badges and before settings:

```swift
                    if !summary.commands.isEmpty { commandsSection }
```

```swift
    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commands")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(summary.commands) { command in
                CommandShortcutRow(command: command, state: state)
            }
        }
    }
```

```swift
struct CommandShortcutRow: View {
    let command: PluginCommandSummary
    @ObservedObject var state: SettingsState
    @State private var combo: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(command.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            HotkeyRecorderView(combo: $combo) {
                state.saveCommandShortcut?(command.id, combo)
                state.refreshModules()
            }
        }
        .onAppear { combo = command.shortcut }
    }
}
```

- [ ] **Step 3: Fill commands in buildPluginSummaries**

```swift
        let shortcuts = CommandShortcuts.load(from: workspace.readSettings()["commandShortcuts"])
```

When constructing each summary, collect:

```swift
            let commands = engine.commandRegistry.values
                .filter { $0.pluginFile == file.filename }
                .sorted { $0.name < $1.name }
                .map {
                    PluginCommandSummary(
                        id: $0.id,
                        name: $0.name,
                        shortcut: shortcuts.combo(for: $0.id)
                    )
                }
```

Pass `commands: commands` into `ModuleSummary(...)`. Disabled plugins: empty commands (they are not in the registry).

- [ ] **Step 4: Persist from Settings**

In `setupSettings()`:

```swift
        settingsState.saveCommandShortcut = { [weak self] commandId, combo in
            guard let self else { return }
            let launcherCombo = self.resolveHotkey().lowercased()
            if !combo.isEmpty, combo.lowercased() == launcherCombo {
                NSLog("[Macotron] Command shortcut collides with the launcher hotkey")
                return
            }
            try? self.workspace.updateSettings { settings in
                var table = CommandShortcuts.load(from: settings["commandShortcuts"])
                table.assign(commandId: commandId, combo: combo)
                settings["commandShortcuts"] = table.jsonObject()
            }
            self.engine.configStore = self.workspace.readSettings()
            self.installCommandShortcuts()
        }
```

Do not call `reloadAll()` — shortcut changes must not re-evaluate plugins.

- [ ] **Step 5: Build**

Run: `make build && swift test --build-path /tmp/macotron-build`

Expected: PASS

Manual: `make run` → Settings → Plugins → a plugin that registers commands → recorder appears.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacotronUI/SettingsView.swift Sources/Macotron/AppDelegate.swift
git commit -m "$(cat <<'EOF'
Let Settings assign a shortcut to each plugin command

EOF
)"
```

---

### Task 8: Shortcut run path (defaults vs argument form)

**Files:**
- Modify: `Sources/Macotron/AppDelegate.swift`
- Modify: `Sources/MacotronUI/LauncherView.swift` (onChange of pendingArgs — already in Task 3; confirm it still works when the panel opens)

**Interfaces:**
- Consumes: `CommandArgumentResolver`, `LauncherSession.pendingArgs`, `Engine.invokeCommand`
- Produces: `handleCommandShortcut` that runs immediately when defaults cover required args, otherwise opens the launcher in argument mode without closing after a failed resolve

- [ ] **Step 1: Replace the Task 6 stub**

```swift
    private func handleCommandShortcut(_ commandId: String) {
        guard let cmd = engine.commandRegistry[commandId] else { return }
        switch CommandArgumentResolver.resolve(specs: cmd.arguments, raw: [:]) {
        case .success(let values):
            _ = engine.invokeCommand(commandId, args: values)
        case .failure:
            launcherSession.pendingArgs = .init(
                commandId: cmd.id,
                title: cmd.name,
                arguments: cmd.arguments
            )
            if !launcherPanel.isVisible {
                launcherPanel.toggle()
            }
        }
    }
```

`executeCommand` from the launcher still toggles the panel closed. Shortcut success must not toggle. Keep that split: `invokeCommand` only vs `executeCommand` which toggles.

- [ ] **Step 2: Prefill when pendingArgs arrives from a shortcut**

In `LauncherView`, `.onChange(of: session.pendingArgs?.commandId)` already calls `prefill`. Confirm it runs when the panel is revealed. If `onAppear` is the only prefill path, add:

```swift
        .onChange(of: session.pendingArgs?.commandId) { _, _ in
            if let pending = session.pendingArgs {
                prefill(pending.arguments)
            }
        }
```

- [ ] **Step 3: Build and test**

Run: `make build && swift test --build-path /tmp/macotron-build`

Expected: PASS

Manual:

1. Copy `demo-lorem.js` into `plugins/`.
2. Assign `cmd+shift+l` to Generate Lorem Ipsum (defaults cover both args).
3. Press the shortcut with the launcher closed. Clipboard gets 3 paragraphs. Launcher stays closed.
4. Clear the count default in the plugin (remove `default: 3`, set `required: true`), reload, press the shortcut. Launcher opens on the form.

- [ ] **Step 4: Commit**

```bash
git add Sources/Macotron/AppDelegate.swift Sources/MacotronUI/LauncherView.swift
git commit -m "$(cat <<'EOF'
Run command shortcuts immediately when argument defaults are complete

EOF
)"
```

---

### Task 9: Types and agent docs

**Files:**
- Modify: `Sources/Macotron/Resources/macotron.d.ts`
- Modify: `Sources/MacotronEngine/PluginWorkspace.swift` (`agentsTemplate`)
- Modify: `docs/10-plugins-workdir.md`

**Interfaces:**
- Consumes: the API from Tasks 1–8
- Produces: documented `command()` overload and `commandShortcuts` schema

- [ ] **Step 1: Update macotron.d.ts**

Replace the `command` line with:

```ts
    command(
        name: string,
        description: string,
        handler: (args: Record<string, any>) => void | Promise<void>,
        opts?: {
            id?: string;
            arguments?: Array<
                | { name: string; type: "text"; placeholder?: string; required?: boolean; default?: string }
                | { name: string; type: "number"; placeholder?: string; required?: boolean; default?: number }
                | {
                      name: string;
                      type: "dropdown";
                      placeholder?: string;
                      required?: boolean;
                      default?: string;
                      choices: Array<{ title?: string; label?: string; value: string }>;
                  }
            >;
        }
    ): void;
```

- [ ] **Step 2: Document in agentsTemplate**

After the `macotron.keyboard.on` example in `PluginWorkspace.agentsTemplate`, add:

```
        ## Launcher commands

        ```js
        macotron.command("Generate Lorem Ipsum", "Placeholder text", (args) => {
          macotron.clipboard.set(String(args.count) + " " + args.unit);
        }, {
          id: "lorem-ipsum",
          arguments: [
            { name: "count", type: "number", placeholder: "Count", default: 3 },
            { name: "unit", type: "dropdown", placeholder: "Unit", default: "paragraphs",
              choices: [
                { title: "Words", value: "words" },
                { title: "Lines", value: "lines" },
                { title: "Paragraphs", value: "paragraphs" },
              ],
            },
          ],
        });
        ```

        The three-argument form still works. `id` is optional; the default is `{filename}/{name}`.
        Set `id` if the user will assign a shortcut. Users set shortcuts in Settings → Plugins.
        Do not call `keyboard.on` for launcher commands.
```

Add `"commandShortcuts": {}` to the settings.json schema block (if Task 5 did not already).

- [ ] **Step 3: Update docs/10-plugins-workdir.md**

Add `commandShortcuts` to the example JSON. Add a short “Launcher commands” note: arguments are declared on `macotron.command`; shortcuts are assigned in Settings, not in plugin source.

- [ ] **Step 4: Build**

Run: `make build && swift test --build-path /tmp/macotron-build`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Macotron/Resources/macotron.d.ts Sources/MacotronEngine/PluginWorkspace.swift \
  docs/10-plugins-workdir.md
git commit -m "$(cat <<'EOF'
Document command arguments and per-command shortcuts

EOF
)"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| Optional `opts.id` / `{file}/{name}` default / eval fallback | 1 |
| Argument schema parse (text/number/dropdown, title\|label) | 1 |
| `invokeCommand` passes args object | 2 |
| Resolver defaults / required / number / dropdown | 2 |
| Launcher form, not search-field tokens | 3 |
| Lorem ipsum example | 4 |
| `commandShortcuts` in settings.json | 5 |
| One combo → one command (reassign) | 5 |
| Host bindings on KeyboardModule tap, before `keyboard.on` | 6 |
| Settings plugin-detail recorder | 7 |
| Reject combo equal to launcher hotkey | 7 |
| Shortcut + complete defaults runs without launcher | 8 |
| Shortcut + missing required opens argument form | 8 |
| d.ts + AGENTS.md + workdir docs | 9 |
| Nested views / leftover query / password args | Out of scope |

## Placeholder scan

No TBD / “implement later” / “similar to Task N” left in the task steps.
