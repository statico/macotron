// LaunchAtLogin.swift — Login-item registration via SMAppService
import ServiceManagement

@MainActor
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the system accepted the change. Callers re-read
    /// `isEnabled` afterwards so a failed registration reverts the toggle.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[Macotron] Launch at login failed: \(error.localizedDescription)")
            return false
        }
    }
}
