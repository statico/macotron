// LauncherPrefs.swift — Live display prefs pushed into the launcher view
import SwiftUI

@MainActor
public final class LauncherPrefs: ObservableObject {
    /// Font scale for the launcher: 0.8, 1.0, or 1.2 (settings.json ui.textScale).
    @Published public var textScale: CGFloat

    public init(textScale: CGFloat = 1.0) {
        self.textScale = textScale
    }
}
