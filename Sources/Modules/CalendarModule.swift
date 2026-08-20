import CQuickJS
import EventKit
import Foundation
import MacotronEngine

@MainActor
public final class CalendarModule: NativeModule {
    public let name = "calendar"

    private static let store = EKEventStore()
    private static var requestedAccess = false

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let calendar = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, calendar, "upcoming",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var hours = 24.0
            if let argv, argc > 0, !JS_IsUndefined(argv[0]), !JS_IsNull(argv[0]) {
                let value = JSBridge.getProperty(ctx, argv[0], "hours")
                if !JS_IsUndefined(value) {
                    hours = JSBridge.toDouble(ctx, value)
                }
                JS_FreeValue(ctx, value)
            }

            return JSBridge.newArray(ctx, CalendarModule.upcoming(hours: hours))
        }, "upcoming", 1))

        JS_SetPropertyStr(ctx, macotron, "calendar", calendar)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    private static func upcoming(hours: Double) -> [Any] {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            if !requestedAccess {
                requestedAccess = true
                store.requestFullAccessToEvents { _, _ in }
            }
            return []
        case .fullAccess, .authorized:
            break
        default:
            return []
        }

        let start = Date()
        let end = start.addingTimeInterval(max(0, hours) * 3600)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        return store.events(matching: predicate).map { event in
            [
                "id": event.eventIdentifier ?? event.calendarItemIdentifier,
                "title": event.title ?? "",
                "start": event.startDate.timeIntervalSince1970 * 1000,
                "end": event.endDate.timeIntervalSince1970 * 1000,
                "allDay": event.isAllDay,
                "location": event.location ?? "",
                "calendar": event.calendar?.title ?? "",
            ] as [String: Any]
        }
    }
}
