// NativeModule.swift — Protocol all native modules conform to
import Foundation

/// Protocol for native modules that expose APIs to JavaScript
@MainActor
public protocol NativeModule: AnyObject {
    /// The module name (used as namespace under `macotron.{name}`)
    var name: String { get }

    /// Register this module's functions in the given engine context
    func register(in engine: Engine, options: [String: Any])

    /// Called when the engine is about to reset (cleanup resources)
    func cleanup()
    func didReload()
}

extension NativeModule {
    public func cleanup() {}
    public func didReload() {}
}
