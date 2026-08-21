import Foundation
import Testing
@testable import Modules

@Suite("Reminders")
struct RemindersTests {
    @Test("maps due date to epoch ms")
    func mapsDue() {
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        let row = RemindersStore.row(ReminderItem(
            id: "r1",
            title: "Buy milk",
            due: due,
            completed: false,
            list: "Groceries"
        ))
        #expect(row["id"] as? String == "r1")
        #expect(row["title"] as? String == "Buy milk")
        #expect(row["due"] as? Double == 1_700_000_000_000)
        #expect(row["completed"] as? Bool == false)
        #expect(row["list"] as? String == "Groceries")
    }

    @Test("maps missing due to null")
    func mapsMissingDue() {
        let row = RemindersStore.row(ReminderItem(
            id: "r2",
            title: "Call",
            due: nil,
            completed: true,
            list: "Personal"
        ))
        #expect(row["due"] is NSNull)
        #expect(row["completed"] as? Bool == true)
    }

    @Test("dueMillis converts date components")
    func dueMillisFromComponents() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 8
        comps.day = 21
        comps.hour = 15
        comps.minute = 30
        let date = Calendar.current.date(from: comps)!
        #expect(RemindersStore.dueMillis(comps) as? Double == date.timeIntervalSince1970 * 1000)
        #expect(RemindersStore.dueMillis(nil) is NSNull)
    }

    @Test("incomplete only by default")
    func incompleteOnly() {
        let items = [
            ReminderItem(id: "a", title: "A", due: nil, completed: false, list: "L"),
            ReminderItem(id: "b", title: "B", due: nil, completed: true, list: "L"),
        ]
        #expect(RemindersStore.filter(items, days: nil, completed: false).map(\.id) == ["a"])
        #expect(RemindersStore.filter(items, days: nil, completed: true).map(\.id) == ["b"])
    }

    @Test("days window keeps overdue and undated, drops later dues")
    func daysWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [
            ReminderItem(id: "overdue", title: "O", due: now.addingTimeInterval(-3600), completed: false, list: "L"),
            ReminderItem(id: "soon", title: "S", due: now.addingTimeInterval(3600), completed: false, list: "L"),
            ReminderItem(id: "later", title: "L", due: now.addingTimeInterval(10 * 86400), completed: false, list: "L"),
            ReminderItem(id: "undated", title: "U", due: nil, completed: false, list: "L"),
        ]
        let ids = RemindersStore.filter(items, days: 2, completed: false, now: now).map(\.id)
        #expect(ids == ["overdue", "soon", "undated"])
    }
}
