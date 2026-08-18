// LauncherPrefs.swift — Live display prefs pushed into the launcher view
import SwiftUI

@MainActor
public final class LauncherPrefs: ObservableObject {
    /// Font scale for the launcher: 0.8, 1.0, or 1.2 (settings.json ui.textScale).
    @Published public var textScale: CGFloat

    public init(textScale: CGFloat = 1.0) {
        self.textScale = textScale
    }

    /// Snaps an arbitrary value to the nearest supported scale.
    public static func snapTextScale(_ value: Double) -> Double {
        let stops: [Double] = [0.8, 1.0, 1.2]
        return stops.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }
}
