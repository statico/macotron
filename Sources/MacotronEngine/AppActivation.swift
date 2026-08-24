// AppActivation.swift — One door for taking focus, so the log can name who did
import AppKit
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "activation")

@MainActor
public enum AppActivation {
    private static var lastReason: (reason: String, at: Date)?

    /// Every deliberate activation goes through here. `NSApp.activate` on its
    /// own leaves nothing behind, so a window that steals focus is impossible
    /// to attribute after the fact.
    public static func activate(_ reason: String, file: String = #fileID, line: Int = #line) {
        lastReason = (reason, Date())
        logger.notice("activate: \(reason, privacy: .public) (\(file, privacy: .public):\(line))")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hooked to `didBecomeActive`. An activation with no fresh reason came
    /// from somewhere that did not ask -- a panel ordering itself in, a click,
    /// or AppKit -- so name the windows on screen instead.
    public static func noteBecameActive() {
        if let last = lastReason, -last.at.timeIntervalSinceNow < 1 {
            logger.notice("became active: \(last.reason, privacy: .public)")
        } else {
            let key = NSApp.keyWindow.map { "\(type(of: $0))" } ?? "none"
            let windows = NSApp.windows
                .filter(\.isVisible)
                .map { "\(type(of: $0))" }
                .joined(separator: ", ")
            logger.notice(
                """
                became active: nothing asked -- key=\(key, privacy: .public) \
                visible=[\(windows, privacy: .public)]
                """
            )
        }
        lastReason = nil
    }

    /// Something took focus without going through `activate` -- a panel that
    /// orders itself in and becomes key. Name it while it happens.
    public static func note(_ reason: String) {
        lastReason = (reason, Date())
        logger.notice("\(reason, privacy: .public)")
    }

    /// Paired with the above: says when focus went away again, so a burst of
    /// activate/resign pairs is visible as a burst.
    public static func noteResignedActive() {
        logger.info("resigned active")
    }
}
