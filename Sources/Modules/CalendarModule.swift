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

        JSBridge.fn(ctx, calendar, "upcoming", 1) { ctx, _, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var hours = 24.0
            var from: Double?
            var titles: [String]?
            if let argv, argc > 0, !JS_IsUndefined(argv[0]), !JS_IsNull(argv[0]) {
                let value = JSBridge.getProperty(ctx, argv[0], "hours")
                if !JS_IsUndefined(value) {
                    hours = JSBridge.toDouble(ctx, value)
                }
                JS_FreeValue(ctx, value)
                from = JSBridge.double(ctx, argv[0], "from")
                if let list = JSBridge.stringArray(ctx, argv[0], "calendars"), !list.isEmpty {
                    titles = list
                }
            }

            // The permission prompt has to be raised on the main thread; only
            // the fetch behind it moves off.
            guard Engine.isDryRun(ctx) || CalendarModule.authorized() else {
                return JSBridge.promise(ctx) { .value([Any]()) }
            }
            nonisolated(unsafe) let store = CalendarModule.store
            let window = hours
            let since = from.map { Date(timeIntervalSince1970: $0 / 1000) }
            let wanted = titles
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(CalendarModule.upcoming(store: store, from: since, hours: window, titles: wanted))
            }
        }

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
    /// `titles` narrows the search to calendars with those names (see
    /// `namedEventCalendars`); nil is all of them. A bare title also matches
    /// every calendar by that title, as settings saved before names carried
    /// the account. The window opens at `from` (or now) and closes `hours`
    /// from now.
    private nonisolated static func upcoming(store: EKEventStore, from: Date? = nil, hours: Double, titles: [String]? = nil) -> [Any] {
        var calendars: [EKCalendar]?
        if let titles {
            let picked = store.namedEventCalendars()
                .filter { titles.contains($0.name) || titles.contains($0.calendar.title) }
                .map(\.calendar)
            // Every picked calendar is gone (renamed, account removed): answer
            // with no events rather than handing EventKit an empty array,
            // whose behavior its docs leave undefined.
            guard !picked.isEmpty else { return [] }
            calendars = picked
        }
        let now = Date()
        let start = min(from ?? now, now)
        let end = now.addingTimeInterval(max(0, hours) * 3600)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)

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
