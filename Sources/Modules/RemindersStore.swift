import Foundation

struct ReminderItem: Equatable {
    var id: String
    var title: String
    var due: Date?
    var completed: Bool
    var list: String
}

enum RemindersStore {
    static func row(_ item: ReminderItem) -> [String: Any] {
        [
            "id": item.id,
            "title": item.title,
            "due": item.due.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull(),
            "completed": item.completed,
            "list": item.list,
        ]
    }

    static func dueMillis(_ comps: DateComponents?) -> Any {
        guard let comps, let date = Calendar.current.date(from: comps) else { return NSNull() }
        return date.timeIntervalSince1970 * 1000
    }

    static func filter(
        _ items: [ReminderItem],
        days: Double?,
        completed: Bool,
        now: Date = Date()
    ) -> [ReminderItem] {
        items.filter { item in
            guard item.completed == completed else { return false }
            guard let days else { return true }
            guard let due = item.due else { return true }
            return due <= now.addingTimeInterval(days * 86400)
        }
    }
}
