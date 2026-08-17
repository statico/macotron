import Foundation

/// IOHIDAccessType from IOKit. Granted is 0 — not a Bool.
public enum HIDAccess {
    public static let granted: UInt32 = 0
    public static let denied: UInt32 = 1
    public static let unknown: UInt32 = 2

    public static func isGranted(_ raw: UInt32) -> Bool {
        raw == granted
    }
}
