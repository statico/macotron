import CQuickJS
import EventKit
import Foundation
import MacotronEngine

@MainActor
public final class RemindersModule: NativeModule {
    public let name = "reminders"

    private static let store = EKEventStore()
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
                let daysVal = JSBridge.getProperty(ctx, argv[0], "days")
                if !JS_IsUndefined(daysVal), !JS_IsNull(daysVal) {
                    days = JSBridge.toDouble(ctx, daysVal)
                }
                JS_FreeValue(ctx, daysVal)
                let completedVal = JSBridge.getProperty(ctx, argv[0], "completed")
                if !JS_IsUndefined(completedVal), !JS_IsNull(completedVal) {
                    completed = JSBridge.toBool(ctx, completedVal)
                }
                JS_FreeValue(ctx, completedVal)
            }
            return JSBridge.newArray(ctx, RemindersModule.list(days: days, completed: completed, dryRun: remindersDryRun(ctx)))
        }, "list", 1))

        JS_SetPropertyStr(ctx, reminders, "add", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1 else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "title required"])
            }
            let titleVal = JSBridge.getProperty(ctx, argv[0], "title")
            let title = JSBridge.toString(ctx, titleVal) ?? ""
            JS_FreeValue(ctx, titleVal)
            guard !title.isEmpty else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "title required"])
            }
            var due: Date?
            let dueVal = JSBridge.getProperty(ctx, argv[0], "due")
            if !JS_IsUndefined(dueVal), !JS_IsNull(dueVal) {
                due = Date(timeIntervalSince1970: JSBridge.toDouble(ctx, dueVal) / 1000)
            }
            JS_FreeValue(ctx, dueVal)
            let listVal = JSBridge.getProperty(ctx, argv[0], "list")
            let list = JSBridge.toString(ctx, listVal)
            JS_FreeValue(ctx, listVal)
            return JSBridge.newObject(ctx, RemindersModule.add(title: title, due: due, list: list, dryRun: remindersDryRun(ctx)))
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
            return JSBridge.newObject(ctx, RemindersModule.complete(id: id, on: on, dryRun: remindersDryRun(ctx)))
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

    private static func list(days: Double?, completed: Bool, dryRun: Bool) -> [Any] {
        if dryRun { return [] }
        guard authorized() else { return [] }
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

    private static func item(_ reminder: EKReminder) -> ReminderItem {
        ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            completed: reminder.isCompleted,
            list: reminder.calendar?.title ?? ""
        )
    }

    private static func fetch(_ predicate: NSPredicate) -> [EKReminder] {
        var result: [EKReminder]?
        store.fetchReminders(matching: predicate) { reminders in
            result = reminders ?? []
        }
        let deadline = Date().addingTimeInterval(2)
        while result == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return result ?? []
    }
}

@MainActor
private func remindersDryRun(_ ctx: OpaquePointer) -> Bool {
    guard let opaque = JS_GetContextOpaque(ctx) else { return false }
    return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
}
