import Foundation
import Testing
@testable import MacotronEngine

@Suite("PluginSchedule")
struct PluginScheduleTests {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test("every 1h from 12:30 UTC aligns to 13:00")
    func everyHourFrom1230() throws {
        let calendar = utcCalendar()
        let schedule = try PluginSchedule.parseEvery("1h")
        let after = date(2026, 8, 20, 12, 30, calendar: calendar)
        let next = schedule.nextDate(after: after, calendar: calendar)
        #expect(next == date(2026, 8, 20, 13, 0, calendar: calendar))
    }

    @Test("every 1h from exact hour boundary advances to next hour")
    func everyHourFromExactBoundary() throws {
        let calendar = utcCalendar()
        let schedule = try PluginSchedule.parseEvery("1h")
        let after = date(2026, 8, 20, 13, 0, 0, calendar: calendar)
        let next = schedule.nextDate(after: after, calendar: calendar)
        #expect(next == date(2026, 8, 20, 14, 0, calendar: calendar))
    }

    @Test("every 15m from 12:07 UTC aligns to 12:15")
    func every15MinutesFrom1207() throws {
        let calendar = utcCalendar()
        let schedule = try PluginSchedule.parseEvery("15m")
        let after = date(2026, 8, 20, 12, 7, calendar: calendar)
        let next = schedule.nextDate(after: after, calendar: calendar)
        #expect(next == date(2026, 8, 20, 12, 15, calendar: calendar))
    }

    @Test("at 13:00 after 13:05 UTC fires next day")
    func atDailyAfter1305() throws {
        let calendar = utcCalendar()
        let schedule = try PluginSchedule.parseAt("13:00", weekdays: nil)
        let after = date(2026, 8, 20, 13, 5, calendar: calendar)
        let next = schedule.nextDate(after: after, calendar: calendar)
        #expect(next == date(2026, 8, 21, 13, 0, calendar: calendar))
    }

    @Test("at 09:00 weekdays Mon-Fri from Friday 18:00 UTC lands Monday")
    func atWeekdaysFromFriday() throws {
        let calendar = utcCalendar()
        let schedule = try PluginSchedule.parseAt("09:00", weekdays: [1, 2, 3, 4, 5])
        let after = date(2026, 8, 21, 18, 0, calendar: calendar) // Friday
        let next = schedule.nextDate(after: after, calendar: calendar)
        #expect(next == date(2026, 8, 24, 9, 0, calendar: calendar)) // Monday
    }

    @Test("at 1:30am around LA spring-forward returns valid local time")
    func atLASpringForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let schedule = try PluginSchedule.parseAt("1:30am", weekdays: nil)
        let after = date(2026, 3, 7, 22, 0, calendar: calendar)
        let next = schedule.nextDate(after: after, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        #expect(parts.year == 2026)
        #expect(parts.month == 3)
        #expect(parts.day == 8)
        #expect(parts.hour == 1)
        #expect(parts.minute == 30)
    }

    @Test("coalesce fires missed schedule once then advances")
    func coalesceMissedFire() throws {
        let calendar = utcCalendar()
        let schedule = try PluginSchedule.parseAt("13:00", weekdays: nil)
        let scheduled = date(2026, 8, 20, 13, 0, calendar: calendar)
        let now = date(2026, 8, 20, 15, 10, calendar: calendar)
        #expect(PluginSchedule.shouldFireMissed(scheduled: scheduled, now: now))
        let next = schedule.nextDate(after: now, calendar: calendar)
        #expect(next == date(2026, 8, 21, 13, 0, calendar: calendar))
    }

    @Test("parse rejects garbage")
    func parseRejectsGarbage() {
        #expect(throws: Error.self) { try PluginSchedule.parseEvery("foo") }
        #expect(throws: Error.self) { try PluginSchedule.parseEvery("0h") }
    }
}
