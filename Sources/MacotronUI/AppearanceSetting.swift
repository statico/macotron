// AppearanceSetting.swift — ui.appearance: system, dark, or light
import AppKit

public enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    /// nil means follow the system appearance.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    public static func parse(_ raw: Any?) -> AppearanceSetting {
        (raw as? String).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    /// Applies app-wide: every window and panel, including plugin WKWebViews.
    @MainActor
    public func apply() {
        NSApp.appearance = nsAppearance
    }
}
