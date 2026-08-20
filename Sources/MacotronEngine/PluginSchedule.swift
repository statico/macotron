import Foundation

public enum PluginSchedule: Equatable, Sendable {
    case interval(TimeInterval)
    case everyMinutes(Int)
    case everyHours(Int)
    case everyDays(Int)
    case at(hour: Int, minute: Int, second: Int, weekdays: Set<Int>?)

    public static func parseEvery(_ raw: String) throws -> PluginSchedule {
        guard let match = raw.wholeMatch(
            of: /(?i)^(\d+)\s*(ms|s|m|h|d|sec|secs|second|seconds|min|mins|minute|minutes|hr|hrs|hour|hours|day|days)$/
        ) else {
            throw ParseError.invalid(raw)
        }
        guard let value = Int(match.1), value > 0 else {
            throw ParseError.invalid(raw)
        }
        switch String(match.2).lowercased() {
        case "ms":
            return .interval(Double(value) / 1000)
        case "s", "sec", "secs", "second", "seconds":
            return .interval(TimeInterval(value))
        case "m", "min", "mins", "minute", "minutes":
            if 60 % value == 0 { return .everyMinutes(value) }
            return .interval(TimeInterval(value * 60))
        case "h", "hr", "hrs", "hour", "hours":
            if 24 % value == 0 { return .everyHours(value) }
            return .interval(TimeInterval(value * 3600))
        case "d", "day", "days":
            return .everyDays(value)
        default:
            throw ParseError.invalid(raw)
        }
    }

    public static func parseAt(_ time: String, weekdays: [Int]?) throws -> PluginSchedule {
        let parsed = try parseTimeOfDay(time)
        let weekdaySet = weekdays.map { Set($0) }
        return .at(hour: parsed.hour, minute: parsed.minute, second: parsed.second, weekdays: weekdaySet)
    }

    public static func shouldFireMissed(scheduled: Date, now: Date) -> Bool {
        now >= scheduled
    }

    public func nextDate(after date: Date, calendar: Calendar) -> Date {
        switch self {
        case .interval(let interval):
            return date.addingTimeInterval(interval)
        case .everyMinutes(let n):
            return Self.nextAlignedMinute(after: date, every: n, calendar: calendar)
        case .everyHours(let n):
            return Self.nextAlignedHour(after: date, every: n, calendar: calendar)
        case .everyDays(let n):
            return Self.nextEveryDays(after: date, every: n, calendar: calendar)
        case .at(let hour, let minute, let second, let weekdays):
            return Self.nextAt(
                after: date,
                hour: hour,
                minute: minute,
                second: second,
                weekdays: weekdays,
                calendar: calendar
            )
        }
    }

    private static func parseTimeOfDay(_ raw: String) throws -> (hour: Int, minute: Int, second: Int) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        if let match = lower.wholeMatch(of: /^(\d{1,2})(?::(\d{2}))?(?::(\d{2}))?\s*(am|pm)$/) {
            var hour = Int(match.1)!
            let minute = match.2.map { Int($0)! } ?? 0
            let second = match.3.map { Int($0)! } ?? 0
            let meridiem = String(match.4)
            if meridiem == "am" {
                if hour == 12 { hour = 0 }
            } else if hour != 12 {
                hour += 12
            }
            guard (0..<24).contains(hour), (0..<60).contains(minute), (0..<60).contains(second) else {
                throw ParseError.invalid(raw)
            }
            return (hour, minute, second)
        }

        let parts = trimmed.split(separator: ":").map { Int($0) }
        guard parts.count == 2 || parts.count == 3,
              let hour = parts[0], (0..<24).contains(hour),
              let minute = parts[1], (0..<60).contains(minute) else {
            throw ParseError.invalid(raw)
        }
        let second = parts.count == 3 ? parts[2]! : 0
        guard (0..<60).contains(second) else { throw ParseError.invalid(raw) }
        return (hour, minute, second)
    }

    private static func nextAlignedMinute(after date: Date, every n: Int, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        let onBoundary = second == 0 && minute % n == 0
        var targetMinute = onBoundary ? minute + n : ((minute / n) + 1) * n
        var hour = comps.hour ?? 0
        var dayOffset = 0
        if targetMinute >= 60 {
            targetMinute -= 60
            hour += 1
        }
        if hour >= 24 {
            dayOffset = hour / 24
            hour = hour % 24
        }
        comps.hour = hour
        comps.minute = targetMinute
        comps.second = 0
        comps.nanosecond = 0
        guard var result = calendar.date(from: comps) else { return date.addingTimeInterval(TimeInterval(n * 60)) }
        if dayOffset > 0 {
            result = calendar.date(byAdding: .day, value: dayOffset, to: result)!
        }
        return result
    }

    private static func nextAlignedHour(after date: Date, every n: Int, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        let onBoundary = minute == 0 && second == 0 && hour % n == 0
        let targetHour = onBoundary ? hour + n : ((hour / n) + 1) * n
        comps.minute = 0
        comps.second = 0
        comps.nanosecond = 0
        if targetHour < 24 {
            comps.hour = targetHour
            return calendar.date(from: comps)!
        }
        comps.hour = targetHour % 24
        let base = calendar.date(from: comps)!
        return calendar.date(byAdding: .day, value: targetHour / 24, to: base)!
    }

    private static func nextEveryDays(after date: Date, every n: Int, calendar: Calendar) -> Date {
        var candidate = date
        repeat {
            candidate = calendar.date(byAdding: .day, value: n, to: candidate)!
        } while candidate <= date
        return candidate
    }

    private static func nextAt(
        after date: Date,
        hour: Int,
        minute: Int,
        second: Int,
        weekdays: Set<Int>?,
        calendar: Calendar
    ) -> Date {
        var match = DateComponents()
        match.hour = hour
        match.minute = minute
        match.second = second
        if let weekdays {
            var best: Date?
            for jsDay in weekdays {
                var dayMatch = match
                dayMatch.weekday = jsWeekdayToCalendar(jsDay)
                if let next = calendar.nextDate(
                    after: date,
                    matching: dayMatch,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                ), best == nil || next < best! {
                    best = next
                }
            }
            return best ?? date.addingTimeInterval(86400)
        }
        return calendar.nextDate(
            after: date,
            matching: match,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
    }

    private static func jsWeekdayToCalendar(_ jsDay: Int) -> Int {
        jsDay + 1
    }

    enum ParseError: Error, Equatable {
        case invalid(String)
    }
}
