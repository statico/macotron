// DebugServer.swift — HTTP server for development (debug builds only)
import AppKit
import Foundation
import Network
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "debug")

@MainActor
public final class DebugServer {
    private let engine: Engine
    private let snippetManager: SnippetManager
    private let listener: NWListener
    private let port: UInt16

    public var onOpenSettings: (() -> Void)?
    public var onOpenSettingsTab: ((Int) -> Void)?
    public var captureWindow: ((Int?) -> Data?)?
    public var captureLauncher: (() -> Data?)?

    public init(engine: Engine, snippetManager: SnippetManager, port: UInt16 = 7777) {
        self.engine = engine
        self.snippetManager = snippetManager
        self.port = port

        let params = NWParameters.tcp
        self.listener = try! NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }
        let port = self.port
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("Debug server listening on port \(port)")
            case .failed(let error):
                logger.error("Debug server failed: \(error)")
            default:
                break
            }
        }
        listener.start(queue: .main)
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            Task { @MainActor in
                let (body, contentType) = self.route(request)
                let headers = [
                    "HTTP/1.1 200 OK",
                    "Content-Type: \(contentType)",
                    "Content-Length: \(body.count)",
                    "Access-Control-Allow-Origin: *",
                    "",
                    ""
                ].joined(separator: "\r\n")
                let response = headers.data(using: .utf8)! + body
                conn.send(content: response, completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }
    }

    private func route(_ request: String) -> (Data, String) {
        let parts = request.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let fullPath = parts.dropFirst().first.map(String.init) ?? "/"
        let path = fullPath.split(separator: "?").first.map(String.init) ?? fullPath
        let query = fullPath.contains("?") ? String(fullPath.split(separator: "?", maxSplits: 1).last ?? "") : ""

        switch (method, path) {
        case (_, "/eval"):
            let body = extractBody(request)
            let js = parseJSON(body)?["js"] as? String ?? ""
            let (result, error) = engine.evaluate(js, filename: "<debug-eval>")
            let response = error ?? result ?? "undefined"
            return (response.data(using: .utf8)!, "text/plain")

        case (_, "/reload"):
            snippetManager.reloadAll()
            return ("reloaded".data(using: .utf8)!, "text/plain")

        case (_, "/snippets"):
            let snippets = snippetManager.listSnippets()
            let list = snippets.map { ["filename": $0.filename, "description": $0.description] }
            let data = try! JSONSerialization.data(withJSONObject: list)
            return (data, "application/json")

        case (_, "/commands"):
            let cmds = engine.commandRegistry.map { (key, val) in
                ["name": val.name, "description": val.description]
            }
            let data = try! JSONSerialization.data(withJSONObject: cmds)
            return (data, "application/json")

        case (_, "/backups"):
            let backups = snippetManager.backup.listBackups()
            let data = try! JSONSerialization.data(withJSONObject: backups)
            return (data, "application/json")

        case (_, "/health"):
            let info: [String: Any] = [
                "status": "ok",
                "snippets": snippetManager.listSnippets().count,
                "commands": engine.commandRegistry.count,
            ]
            let data = try! JSONSerialization.data(withJSONObject: info)
            return (data, "application/json")

        case (_, "/open-settings"):
            let body = extractBody(request)
            let tab = (parseJSON(body)?["tab"] as? Int) ?? 0
            onOpenSettingsTab?(tab)
            return ("opened".data(using: .utf8)!, "text/plain")

        case (_, "/screenshot"):
            // Optional ?view=launcher or ?tab=N query parameter
            let params = Dictionary(uniqueKeysWithValues:
                query.split(separator: "&").compactMap { param -> (String, String)? in
                    let kv = param.split(separator: "=", maxSplits: 1)
                    guard kv.count == 2 else { return nil }
                    return (String(kv[0]), String(kv[1]))
                }
            )
            if params["view"] == "launcher", let png = captureLauncher?() {
                return (png, "image/png")
            }
            let tab = params["tab"].flatMap(Int.init)
            if let png = captureWindow?(tab) {
                return (png, "image/png")
            }
            return ("no windows found".data(using: .utf8)!, "text/plain")

        default:
            let routes = [
                "GET  /health         - Server status",
                "POST /eval           - Evaluate JS (body: {\"js\": \"...\"})",
                "POST /reload         - Reload all snippets",
                "GET  /snippets       - List loaded snippets",
                "GET  /commands       - List registered commands",
                "GET  /backups        - List config backups",
                "POST /open-settings  - Open settings (body: {\"tab\": 0})",
                "GET  /screenshot     - Screenshot frontmost Macotron window",
            ]
            let text = "Macotron Debug Server\n\nRoutes:\n" + routes.joined(separator: "\n")
            return (text.data(using: .utf8)!, "text/plain")
        }
    }

    private func extractBody(_ request: String) -> String {
        guard let range = request.range(of: "\r\n\r\n") else { return "" }
        return String(request[range.upperBound...])
    }

    private func parseJSON(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
