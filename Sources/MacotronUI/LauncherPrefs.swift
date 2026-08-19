// LauncherPrefs.swift — Live display prefs pushed into the launcher view
import SwiftUI

public enum LauncherBackground: String, CaseIterable, Identifiable, Sendable {
    case translucent
    case glass
    case opaque

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .translucent: return "Translucent"
        case .glass: return "Glass"
        case .opaque: return "Opaque"
        }
    }

    public static func parse(_ raw: Any?) -> LauncherBackground {
        (raw as? String).flatMap(LauncherBackground.init(rawValue:)) ?? .translucent
    }
}

@MainActor
public final class LauncherPrefs: ObservableObject {
    /// Font scale for the launcher: 0.8, 1.0, or 1.2 (settings.json ui.textScale).
    @Published public var textScale: CGFloat
    @Published public var background: LauncherBackground

    public init(textScale: CGFloat = 1.0, background: LauncherBackground = .translucent) {
        self.textScale = textScale
        self.background = background
    }

    /// Snaps an arbitrary value to the nearest supported scale.
    public static func snapTextScale(_ value: Double) -> Double {
        let stops: [Double] = [0.8, 1.0, 1.2]
        return stops.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }
}
