// NativeModule.swift — Protocol all native modules conform to
import Foundation

/// Protocol for native modules that expose APIs to JavaScript
@MainActor
public protocol NativeModule: AnyObject {
    /// The module name (used as namespace under `macotron.{name}`)
    var name: String { get }

    /// Module version number. Bump when API changes.
    var moduleVersion: Int { get }

    /// Default options for this module. User options in config.js override these.
    var defaultOptions: [String: Any] { get }

    /// Register this module's functions in the given engine context
    func register(in engine: Engine, options: [String: Any])

    /// Called when the engine is about to reset (cleanup resources)
    func cleanup()
}

extension NativeModule {
    public var moduleVersion: Int { 1 }
    public var defaultOptions: [String: Any] { [:] }
    public func cleanup() {}
}
