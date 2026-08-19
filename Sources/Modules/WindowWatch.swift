// WindowWatch.swift — window:created / window:focused via AXObserver
import ApplicationServices
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

private final class WindowWatchState: @unchecked Sendable {
    static let shared = WindowWatchState()
    weak var engine: Engine?
    var observers: [pid_t: AXObserver] = [:]
    var launchObserver: NSObjectProtocol?
}

enum WindowWatch {
    static func start(_ engine: Engine) {
        WindowWatchState.shared.engine = engine
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            add(app.processIdentifier)
        }
        WindowWatchState.shared.launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            add(app.processIdentifier)
        }
    }

    static func stop() {
        if let launchObserver = WindowWatchState.shared.launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
        WindowWatchState.shared.launchObserver = nil
        WindowWatchState.shared.observers.removeAll()
        WindowWatchState.shared.engine = nil
    }

    static func add(_ pid: pid_t) {
        guard WindowWatchState.shared.observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, windowAXCallback, &observer) == .success, let observer else {
            return
        }
        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, nil)
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        WindowWatchState.shared.observers[pid] = observer
    }

    static func emit(element: AXUIElement, notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown"
        let win: AXUIElement
        if notification == (kAXFocusedWindowChangedNotification as String) {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &ref) == .success,
                  let focused = ref else { return }
            win = focused as! AXUIElement
        } else {
            win = element
        }
        let info = WindowAX.info(win, pid: pid, app: appName)
        let event = notification == (kAXFocusedWindowChangedNotification as String)
            ? "window:focused"
            : "window:created"
        let id = info["id"] as? Int ?? 0
        let title = info["title"] as? String ?? ""
        DispatchQueue.main.async {
            Task { @MainActor in
                guard let engine = WindowWatchState.shared.engine, let ctx = engine.context else { return }
                let data = JSBridge.newObject(ctx, ["id": id, "title": title, "app": appName])
                engine.eventBus.emit(event, engine: engine, data: data)
                JS_FreeValue(ctx, data)
            }
        }
    }
}

private let windowAXCallback: AXObserverCallback = { _, element, notification, _ in
    WindowWatch.emit(element: element, notification: notification as String)
}
