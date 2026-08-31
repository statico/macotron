// NotifyModule.swift — macotron.notify: native macOS notifications from JS
import AppKit
import CQuickJS
import Foundation
import MacotronEngine
@preconcurrency import UserNotifications
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "notify")

/// Banners are otherwise suppressed while Macotron is the active app (launcher).
private final class NotifyPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        // The URL rides in userInfo so a click still works after the app
        // restarts, when any in-memory handler is gone.
        let url = (response.notification.request.content.userInfo["url"] as? String)
            .flatMap(URL.init(string:))
        await MainActor.run {
            if let url {
                logger.notice("notification \(id, privacy: .public) opens \(url.absoluteString, privacy: .public)")
                NSWorkspace.shared.open(url)
            }
            NotifyModule.onTap[id]?()
        }
    }
}

@MainActor
public final class NotifyModule: NativeModule {
    public let name = "notify"
    public let moduleVersion = 1

    private var notificationCenter: UNUserNotificationCenter?
    private let presenter = NotifyPresenter()

    public init() {}

    private var center: UNUserNotificationCenter {
        if let notificationCenter { return notificationCenter }
        let c = UNUserNotificationCenter.current()
        notificationCenter = c
        return c
    }

    public enum Delivery: Equatable {
        case deliver
        case askFirst
        case drop
    }

    nonisolated static func deliveryDecision(for status: UNAuthorizationStatus) -> Delivery {
        switch status {
        case .notDetermined: return .askFirst
        case .denied: return .drop
        default: return .deliver
        }
    }

    /// What to run when the user clicks one of the host's own notifications,
    /// keyed by the identifier passed to `post`.
    public static var onTap: [String: () -> Void] = [:]

    /// A notification from the host itself, for something the user has to see
    /// even when Macotron is not the app they are looking at.
    nonisolated public static func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        deliver(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated private static func deliver(_ request: UNNotificationRequest) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch deliveryDecision(for: settings.authorizationStatus) {
            case .deliver:
                add(request, to: center)
            case .askFirst:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        logger.error("Notification authorization failed: \(error.localizedDescription)")
                    }
                    if granted { add(request, to: center) }
                }
            case .drop:
                break
            }
        }
    }

    nonisolated private static func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) {
        center.add(request) { error in
            if let error {
                logger.error("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__notifyModule"] = self
        if !engine.dryRun {
            center.delegate = presenter
        }

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JS_GetPropertyStr(ctx, global, "macotron")

        let notifyObj = JS_NewObject(ctx)

        // -----------------------------------------------------------------
        // macotron.notify.show(title, body, opts?)
        //   opts.sound   — Bool (default true)
        //   opts.subtitle — String (optional)
        //   opts.id      — String (optional, for replacing existing)
        //   opts.url     — String (optional, opened when the banner is clicked)
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, notifyObj, "show", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "notify.show requires at least title and body")
            }

            guard let title = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "notify.show: title must be a string")
            }
            guard let body = JSBridge.toString(ctx, argv[1]) else {
                return QJS_ThrowTypeError(ctx, "notify.show: body must be a string")
            }

            if Engine.isDryRun(ctx) { return QJS_Undefined() }

            // Parse optional opts object
            var sound = true
            var subtitle: String? = nil
            var identifier = UUID().uuidString
            var url: String? = nil

            if argc > 2 && !JS_IsUndefined(argv[2]) && !JS_IsNull(argv[2]) {
                let opts = argv[2]
                sound = JSBridge.bool(ctx, opts, "sound") ?? sound
                subtitle = JSBridge.string(ctx, opts, "subtitle")
                identifier = JSBridge.string(ctx, opts, "id") ?? identifier
                url = JSBridge.string(ctx, opts, "url")
            }

            if let url, URL(string: url) == nil {
                return QJS_ThrowTypeError(ctx, "notify.show: url is not a valid URL")
            }

            // Build and schedule the notification
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let subtitle { content.subtitle = subtitle }
            if sound { content.sound = .default }
            if let url { content.userInfo = ["url": url] }

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil // deliver immediately
            )

            NotifyModule.deliver(request)

            return QJS_Undefined()
        }, "show", 3))

        // macotron.notify.toast(title, body?, opts?)
        //   opts.position — "top" | "bottom" (default "bottom")
        //   opts.duration — milliseconds (default 3000)
        //   opts.color    — "info" | "success" | "error" | "warning" | name | #RRGGBB
        JS_SetPropertyStr(ctx, notifyObj, "toast", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "notify.toast requires a title")
            }
            guard let title = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "notify.toast: title must be a string")
            }

            if Engine.isDryRun(ctx) { return QJS_Undefined() }

            var body: String?
            var opts: JSValue?
            if argc >= 2 {
                if JS_IsObject(argv[1]) && !JS_IsString(argv[1]) {
                    opts = argv[1]
                } else {
                    let text = JSBridge.toString(ctx, argv[1]) ?? ""
                    body = text.isEmpty ? nil : text
                    if argc >= 3 && JS_IsObject(argv[2]) {
                        opts = argv[2]
                    }
                }
            }

            var position = ToastPosition.bottom
            var duration: TimeInterval = 3
            var sfSymbol: String?
            var color: String?
            if let opts {
                if let name = JSBridge.string(ctx, opts, "position") {
                    position = ToastPosition.parse(name)
                }
                if let ms = JSBridge.double(ctx, opts, "duration"), ms > 0 {
                    duration = ms / 1000
                }
                sfSymbol = JSBridge.string(ctx, opts, "sfSymbol")
                color = JSBridge.string(ctx, opts, "color")
            }

            ToastHost.shared.show(
                title: title,
                body: body,
                position: position,
                duration: duration,
                sfSymbol: sfSymbol,
                color: color
            )
            return QJS_Undefined()
        }, "toast", 3))
        JS_SetPropertyStr(ctx, macotron, "notify", notifyObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        notificationCenter?.removeAllPendingNotificationRequests()
        ToastHost.shared.hide()
    }
}
