// PowerActions.swift — lock screen, sleep, and sleep/lock notifications
import AppKit
import Darwin
import Foundation
import MacotronEngine

enum PowerActions {
    static func lock() -> Bool {
        if let fn = SkyLightLock.lockScreen {
            fn()
            return true
        }
        return run("/usr/bin/osascript", [
            "-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}",
        ])
    }

    static func sleep() -> Bool {
        run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to sleep"])
    }

    private static func run(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private enum SkyLightLock {
    static let lockScreen: (@convention(c) () -> Void)? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/login",
            RTLD_LAZY
        ), let sym = dlsym(handle, "SACLockScreenImmediate") else {
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) () -> Void).self)
    }()
}

@MainActor
enum PowerWatch {
    private static var tokens: [NSObjectProtocol] = []

    static func start(_ engine: Engine) {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, "system:sleep", engine)
        observe(workspace, NSWorkspace.didWakeNotification, "system:wake", engine)
        let dist = DistributedNotificationCenter.default()
        observe(dist, Notification.Name("com.apple.screenIsLocked"), "system:lock", engine)
        observe(dist, Notification.Name("com.apple.screenIsUnlocked"), "system:unlock", engine)
    }

    static func stop() {
        for token in tokens {
            DistributedNotificationCenter.default().removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        tokens = []
    }

    private static func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ event: String,
        _ engine: Engine
    ) {
        tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in
                engine.eventBus.emit(event, engine: engine)
            }
        })
    }
}
