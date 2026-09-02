import CQuickJS
import EventKit
import Foundation
import MacotronEngine

@MainActor
public final class CalendarModule: NativeModule {
    public let name = "calendar"

    /// Shared with Permissions: EventKit ties access to the store that asked,
    /// and the Settings row and this module have to agree about who asked.
    private static var store: EKEventStore { Permissions.calendarStore }
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

            // The permission prompt has to be raised on the main thread; only
            // the fetch behind it moves off.
            guard Engine.isDryRun(ctx) || CalendarModule.authorized() else {
                return JSBridge.promise(ctx) { .value([Any]()) }
            }
            nonisolated(unsafe) let store = CalendarModule.store
            let window = hours
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(CalendarModule.upcoming(store: store, hours: window))
            }
        }, "upcoming", 1))

        JS_SetPropertyStr(ctx, macotron, "calendar", calendar)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    private static func authorized() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            if !requestedAccess {
                requestedAccess = true
                store.requestFullAccessToEvents { _, _ in }
                Permissions.invalidate()
            }
            return false
        case .fullAccess, .authorized:
            return true
        default:
            return false
        }
    }

    /// Apple's guidance for this synchronous fetch is to keep it off the main
    /// thread; the store is shared, so the granted access comes with it.
    private nonisolated static func upcoming(store: EKEventStore, hours: Double) -> [Any] {
        let start = Date()
        let end = start.addingTimeInterval(max(0, hours) * 3600)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        // EventKit documents the result order as undefined, and every consumer
        // assumes soonest-first.
        return store.events(matching: predicate)
            .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
            .map { event in
            [
                "id": event.eventIdentifier ?? event.calendarItemIdentifier,
                "title": event.title ?? "",
                "start": event.startDate.timeIntervalSince1970 * 1000,
                "end": event.endDate.timeIntervalSince1970 * 1000,
                "allDay": event.isAllDay,
                "location": event.location ?? "",
                "calendar": event.calendar?.title ?? "",
                "url": CalendarEventURL.pick(url: event.url?.absoluteString, location: event.location, notes: event.notes),
            ] as [String: Any]
        }
    }
}

enum CalendarEventURL {
    /// Zoom and Teams paste a wall of text into the notes and Google Meet
    /// leaves a bare link in the location, so the join link is whichever URL
    /// turns up first — with a known meeting host winning over a stray link
    /// to the agenda doc.
    private static let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com"]

    static func pick(url: String?, location: String?, notes: String? = nil) -> String {
        let found = [url, location, notes].compactMap { $0 }.flatMap(links)
        return found.first(where: { link in
            hosts.contains { link.localizedCaseInsensitiveContains($0) }
        }) ?? found.first ?? ""
    }

    private static func links(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let regex = try! NSRegularExpression(pattern: "https://[^\\s<>\"\']+")
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            // Trailing punctuation belongs to the sentence, not the URL.
            return String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]>"))
        }
    }
}
