import Foundation
import Testing
@testable import MacotronEngine

/// Runs a real `Examples/plugins/*.js` file in a real engine against a mock
/// `macotron` global. Every plugin suite wants the same three things: find the
/// plugin next to the repository root, splice a mock in front of it, and read a
/// value back out.
@MainActor
enum PluginHarness {
    /// `#filePath` is this file, which lives in `Tests/MacotronTests/`, so three
    /// steps up is the repository root.
    static func url(_ plugin: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/\(plugin)")
    }

    /// Evaluates mock + plugin (+ optional trailing script) in a fresh engine
    /// and hands the engine back for follow-up reads. `evaluate` drains the job
    /// queue on its way out, so anything the plugin paints from a promise has
    /// settled by the time this returns.
    static func load(plugin: String, mock: String, extra: String = "") throws -> Engine {
        let url = url(plugin)
        let source = try String(contentsOf: url, encoding: .utf8)
        let engine = Engine()
        let (_, error) = engine.evaluate("\(mock)\n\(source)\n\(extra)", filename: url.path)
        #expect(error == nil)
        return engine
    }

    @discardableResult
    static func run(_ engine: Engine, _ js: String) -> String {
        let (result, error) = engine.evaluate(js)
        #expect(error == nil)
        return result ?? ""
    }

    /// One-shot: mock + plugin + `extra` in a single evaluation, returning the
    /// value of the last expression.
    static func eval(plugin: String, mock: String, extra: String) throws -> String {
        let url = url(plugin)
        let source = try String(contentsOf: url, encoding: .utf8)
        let engine = Engine()
        let (result, error) = engine.evaluate("\(mock)\n\(source)\n\(extra)", filename: url.path)
        #expect(error == nil)
        return result ?? ""
    }

    /// Two-shot: load the plugin, let the job queue drain, *then* read. Plugins
    /// that paint from a promise only settle once the first evaluation returns,
    /// so the assertion has to run in a second one.
    static func evalSettled(plugin: String, mock: String, extra: String) throws -> String {
        run(try load(plugin: plugin, mock: mock), extra)
    }
}
