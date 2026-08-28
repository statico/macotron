import CQuickJS
import EventKit
import Foundation
import MacotronEngine

@MainActor
public final class RemindersModule: NativeModule {
    public let name = "reminders"

    /// One store for the app: EventKit ties the granted access to the store
    /// that asked, and the fetch below runs it off the main thread.
    private nonisolated(unsafe) static let store = EKEventStore()
    private static var requestedAccess = false

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let reminders = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, reminders, "list", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            var days: Double?
            var completed = false
            if let argv, argc > 0, !JS_IsUndefined(argv[0]), !JS_IsNull(argv[0]) {
                days = JSBridge.double(ctx, argv[0], "days")
                completed = JSBridge.bool(ctx, argv[0], "completed") ?? false
            }
            // The permission prompt has to be raised on the main thread; only
            // the fetch behind it moves off.
            guard Engine.isDryRun(ctx) || RemindersModule.authorized() else {
                return JSBridge.promise(ctx) { .value([Any]()) }
            }
            let window = days
            let wantCompleted = completed
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(RemindersModule.list(days: window, completed: wantCompleted))
            }
        }, "list", 1))

        JS_SetPropertyStr(ctx, reminders, "add", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1 else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "title required"])
            }
            let title = JSBridge.string(ctx, argv[0], "title") ?? ""
            guard !title.isEmpty else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "title required"])
            }
            let due = JSBridge.double(ctx, argv[0], "due").map { Date(timeIntervalSince1970: $0 / 1000) }
            let list = JSBridge.string(ctx, argv[0], "list")
            return JSBridge.newObject(ctx, RemindersModule.add(
                title: title, due: due, list: list, dryRun: Engine.isDryRun(ctx)))
        }, "add", 1))

        JS_SetPropertyStr(ctx, reminders, "complete", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]), !id.isEmpty else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "id required"])
            }
            var on = true
            if argc >= 2, !JS_IsUndefined(argv[1]), !JS_IsNull(argv[1]) {
                on = JSBridge.toBool(ctx, argv[1])
            }
            return JSBridge.newObject(ctx, RemindersModule.complete(
                id: id, on: on, dryRun: Engine.isDryRun(ctx)))
        }, "complete", 2))

        JS_SetPropertyStr(ctx, macotron, "reminders", reminders)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    private static func authorized() -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            if !requestedAccess {
                requestedAccess = true
                store.requestFullAccessToReminders { _, _ in }
            }
            return false
        case .fullAccess, .authorized:
            return true
        default:
            return false
        }
    }

    private nonisolated static func list(days: Double?, completed: Bool) -> [Any] {
        let calendars = store.calendars(for: .reminder)
        let predicate = completed
            ? store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let items = fetch(predicate).map(item)
        return RemindersStore.filter(items, days: days, completed: completed).map(RemindersStore.row)
    }

    private static func add(title: String, due: Date?, list: String?, dryRun: Bool) -> [String: Any] {
        if dryRun { return ["ok": true] }
        guard authorized() else { return ["ok": false, "error": "unauthorized"] }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list.flatMap { name in
            store.calendars(for: .reminder).first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
        } ?? store.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
        }
        do {
            try store.save(reminder, commit: true)
            return ["ok": true, "id": reminder.calendarItemIdentifier]
        } catch {
            return ["ok": false, "error": error.localizedDescription]
        }
    }

    private static func complete(id: String, on: Bool, dryRun: Bool) -> [String: Any] {
        if dryRun { return ["ok": true] }
        guard authorized() else { return ["ok": false, "error": "unauthorized"] }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            return ["ok": false, "error": "not found"]
        }
        reminder.isCompleted = on
        do {
            try store.save(reminder, commit: true)
            return ["ok": true]
        } catch {
            return ["ok": false, "error": error.localizedDescription]
        }
    }

    private nonisolated static func item(_ reminder: EKReminder) -> ReminderItem {
        ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            completed: reminder.isCompleted,
            list: reminder.calendar?.title ?? ""
        )
    }

    /// EventKit answers on a queue of its own, so waiting here costs nothing but
    /// this background queue — which is the whole point of getting off main.
    private nonisolated static func fetch(_ predicate: NSPredicate) -> [EKReminder] {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: [EKReminder] = []
        store.fetchReminders(matching: predicate) { reminders in
            result = reminders ?? []
            done.signal()
        }
        done.wait()
        return result
    }
}
