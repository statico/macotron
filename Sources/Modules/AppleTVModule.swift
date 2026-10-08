import CQuickJS
import Foundation
import MacotronEngine

enum AppleTVRemote {
    static let types = ["_companion-link._tcp", "_airplay._tcp"]

    /// A browse runs for its whole timeout, so one per key press would leave the
    /// remote unresponsive between presses. Apple TVs do not come and go by the
    /// second, so a recent result is reused.
    static let browseTTL: TimeInterval = 30

    // ponytail: one lock for the whole cache; it guards two fields and is only
    // taken around a browse, so contention is not worth a finer scheme.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: [[String: Any]] = []
    nonisolated(unsafe) private static var browsedAt: Date?

    /// Runs the browse on the calling thread when the cache is cold, so call it
    /// from a promise's queue rather than the main thread.
    static func devices() -> [[String: Any]] {
        lock.lock()
        if let browsedAt, Date().timeIntervalSince(browsedAt) < browseTTL, !cached.isEmpty {
            defer { lock.unlock() }
            return cached
        }
        lock.unlock()

        let rows = merge(BonjourBrowse.browse(types: types, timeout: 1.5, dryRun: false))
        lock.lock()
        cached = rows
        browsedAt = Date()
        lock.unlock()
        return rows
    }

    /// Every cached row, however old, for the synchronous `paired` and
    /// `unpair`, which take an id that an earlier `list()` handed out.
    static func knownDevices() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    static func merge(_ services: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var out: [[String: Any]] = []
        for s in services {
            let host = s["host"] as? String ?? ""
            let port = s["port"] as? Int ?? 0
            guard !host.isEmpty, port > 0 else { continue }
            let id = "\(host):\(port)"
            guard seen.insert(id).inserted else { continue }
            out.append([
                "id": id,
                "name": s["name"] as? String ?? "",
                "host": host,
                "port": port,
                "type": s["type"] as? String ?? "",
            ])
        }
        return out
    }

    // MARK: - Pairing and keys

    /// Pairings live in their own Keychain service, out of reach of
    /// `macotron.keychain`, one item per Apple TV keyed by its Bonjour name.
    struct CredentialStore: Sendable {
        var read: @Sendable (String) -> String?
        var write: @Sendable (String, String) -> Void
        var delete: @Sendable (String) -> Void

        static let service = "io.statico.macotron.appletv"
        static let keychain = CredentialStore(
            read: { KeychainStore.read(account: $0, service: service) },
            write: { KeychainStore.write(account: $0, value: $1, service: service) },
            delete: { KeychainStore.delete(account: $0, service: service) }
        )

        func credentials(_ name: String) -> CompanionCredentials? {
            read(name).flatMap(CompanionCredentials.init(string:))
        }
    }

    /// What the TV lists under Settings > Remotes and Devices.
    static let clientName = "Macotron"

    /// An Apple TV as `list()` described it. Pairings are keyed by `name`
    /// rather than the id, because the companion port changes when the TV
    /// restarts; renaming the TV means pairing again.
    struct Target {
        let name: String
        let host: String?
        let port: Int?
    }

    /// One Apple TV shows up once per service, so whichever row the id names,
    /// the connection goes to its companion-link service.
    static func target(id: String, devices: [[String: Any]]) -> Target? {
        guard let row = devices.first(where: { ($0["id"] as? String) == id }) else { return nil }
        let name = row["name"] as? String ?? ""
        let host = row["host"] as? String
        let companion = devices.first {
            ($0["type"] as? String) == "_companion-link._tcp"
                && (($0["host"] as? String) == host || ($0["name"] as? String) == name)
        }
        return Target(name: name, host: companion?["host"] as? String, port: companion?["port"] as? Int)
    }

    /// Remote keys as pyatv sends them: a HID button press and release, or a
    /// media-control command for play and pause on their own.
    enum Key: Equatable {
        case hid(Int)
        case media(Int)

        init?(_ command: String) {
            switch command {
            case "up": self = .hid(1)
            case "down": self = .hid(2)
            case "left": self = .hid(3)
            case "right": self = .hid(4)
            case "menu": self = .hid(5)
            case "select": self = .hid(6)
            case "home": self = .hid(7)
            case "playpause": self = .hid(14)
            case "play": self = .media(1)
            case "pause": self = .media(2)
            default: return nil
            }
        }

        func press(on link: CompanionLink) throws {
            switch self {
            case let .hid(code):
                try link.request("_hidC", ["_hBtS": 1, "_hidC": .int(code)])
                try link.request("_hidC", ["_hBtS": 2, "_hidC": .int(code)])
            case let .media(code):
                try link.request("_mcc", ["_mcc": .int(code)])
            }
        }
    }

    // ponytail: one serial queue for every Apple TV, so presses to two TVs
    // wait on each other. A queue per TV if anyone drives several at once.
    private static let queue = DispatchQueue(label: "io.statico.macotron.appletv")
    /// Verified sessions kept open so repeated presses skip the handshake.
    nonisolated(unsafe) private static var sessions: [String: CompanionLink] = [:]
    /// Pair-setups waiting for the PIN the TV is showing.
    nonisolated(unsafe) private static var pending: [String: (CompanionLink, CompanionLink.SetupChallenge)] = [:]

    private static func failure(_ error: Error) -> [String: Any] {
        ["ok": false, "error": "\(error)"]
    }

    static func send(
        id: String, command: String, devices: [[String: Any]], dryRun: Bool, store: CredentialStore = .keychain
    ) -> [String: Any] {
        if dryRun { return ["ok": true] }
        guard let target = target(id: id, devices: devices) else { return ["ok": false, "error": "No Apple TV"] }
        guard let key = Key(command) else { return ["ok": false, "error": "Unknown command: \(command)"] }
        guard let credentials = store.credentials(target.name) else { return ["ok": false, "error": "not paired"] }
        guard let host = target.host, let port = target.port else {
            return ["ok": false, "error": "No Companion service"]
        }

        return queue.sync {
            // A kept session can die quietly while idle, so a failure there
            // earns one retry on a fresh connection.
            if let link = sessions[target.name], link.isAlive, (try? key.press(on: link)) != nil {
                return ["ok": true]
            }
            sessions.removeValue(forKey: target.name)?.close()
            let link = CompanionLink(host: host, port: port)
            do {
                try link.open()
                try link.pairVerify(credentials)
                try link.startSession(credentials, name: clientName)
                try key.press(on: link)
                sessions[target.name] = link
                return ["ok": true]
            } catch {
                link.close()
                return failure(error)
            }
        }
    }

    /// A PIN as typed, padded to the 4 digits the TV shows, or nil if it is
    /// not one.
    static func normalizePIN(_ pin: String) -> String? {
        let typed = pin.trimmingCharacters(in: .whitespaces)
        guard (1...4).contains(typed.count), typed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return String(repeating: "0", count: 4 - typed.count) + typed
    }

    /// Without a PIN, starts pair-setup so the TV shows one. With the PIN,
    /// finishes it and stores the pairing.
    static func pair(
        id: String, pin: String?, devices: [[String: Any]], store: CredentialStore = .keychain
    ) -> [String: Any] {
        guard let target = target(id: id, devices: devices) else { return ["ok": false, "error": "No Apple TV"] }
        guard let host = target.host, let port = target.port else {
            return ["ok": false, "error": "No Companion service"]
        }

        guard let pin else {
            return queue.sync {
                pending.removeValue(forKey: target.name)?.0.close()
                let link = CompanionLink(host: host, port: port)
                do {
                    try link.open()
                    pending[target.name] = (link, try link.pairSetupStart())
                    return ["ok": true]
                } catch {
                    link.close()
                    return failure(error)
                }
            }
        }

        guard let code = normalizePIN(pin) else {
            return ["ok": false, "error": "The PIN is the 4 numbers on the TV"]
        }
        return queue.sync {
            guard let (link, challenge) = Optional(pending.removeValue(forKey: target.name)) ?? nil else {
                return ["ok": false, "error": "Call pair(id) first so the TV shows a PIN"]
            }
            defer { link.close() }
            do {
                let credentials = try link.pairSetupFinish(pin: code, challenge: challenge, name: clientName)
                store.write(target.name, credentials.string)
                sessions.removeValue(forKey: target.name)?.close()
                return ["ok": true]
            } catch {
                return failure(error)
            }
        }
    }

    static func paired(id: String, devices: [[String: Any]], store: CredentialStore = .keychain) -> Bool {
        guard let target = target(id: id, devices: devices) else { return false }
        return store.credentials(target.name) != nil
    }

    /// Forgets the pairing on this Mac. The TV keeps its side until it is
    /// removed in Settings > Remotes and Devices.
    static func unpair(id: String, devices: [[String: Any]], store: CredentialStore = .keychain) {
        guard let target = target(id: id, devices: devices) else { return }
        store.delete(target.name)
        queue.async {
            sessions.removeValue(forKey: target.name)?.close()
            pending.removeValue(forKey: target.name)?.0.close()
        }
    }
}

@MainActor
public final class AppleTVModule: NativeModule {
    public let name = "appletv"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let obj = JS_NewObject(ctx)

        JSBridge.fn(ctx, obj, "list", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(AppleTVRemote.devices().map { $0 as Any })
            }
        }

        JSBridge.fn(ctx, obj, "send", 2) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let dry: [String: Any] = ["ok": true]
            guard let argv, argc >= 2,
                  let id = JSBridge.toString(ctx, argv[0]),
                  let command = JSBridge.toString(ctx, argv[1]) else {
                return JSBridge.promise(ctx, dryRun: dry) {
                    .value(["ok": false, "error": "No Apple TV"] as [String: Any])
                }
            }
            return JSBridge.promise(ctx, dryRun: dry) {
                .value(AppleTVRemote.send(
                    id: id, command: command, devices: AppleTVRemote.devices(), dryRun: false
                ))
            }
        }

        JSBridge.fn(ctx, obj, "pair", 2) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let dry: [String: Any] = ["ok": true]
            guard let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.promise(ctx, dryRun: dry) {
                    .value(["ok": false, "error": "No Apple TV"] as [String: Any])
                }
            }
            let pin = argc >= 2 && !JSBridge.isUndefined(argv[1]) && !JSBridge.isNull(argv[1])
                ? JSBridge.toString(ctx, argv[1]) : nil
            return JSBridge.promise(ctx, dryRun: dry) {
                .value(AppleTVRemote.pair(id: id, pin: pin, devices: AppleTVRemote.devices()))
            }
        }

        JSBridge.fn(ctx, obj, "paired", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1, !Engine.isDryRun(ctx), let id = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, AppleTVRemote.paired(id: id, devices: AppleTVRemote.knownDevices()))
        }

        JSBridge.fn(ctx, obj, "unpair", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, !Engine.isDryRun(ctx),
                  let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            AppleTVRemote.unpair(id: id, devices: AppleTVRemote.knownDevices())
            return QJS_Undefined()
        }

        JS_SetPropertyStr(ctx, macotron, "appletv", obj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
