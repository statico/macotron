import Foundation
import Testing
@testable import Modules

@Suite("CalendarUpcoming")
struct CalendarUpcomingTests {
    /// event.url wins, then an https link in the location, then the join link
    /// dug out of the notes (meeting host first), then nothing.
    @Test("picks the best join link", arguments: [
        ("https://meet.example/a", "https://zoom.example/b", nil, "https://meet.example/a"),
        (nil, "https://zoom.example/b", nil, "https://zoom.example/b"),
        ("", "Join https://meet.example/c", nil, "https://meet.example/c"),
        (
            nil, "Room 3",
            "Agenda: https://docs.example/agenda\nJoin Zoom Meeting\nhttps://acme.zoom.us/j/123?pwd=abc.",
            "https://acme.zoom.us/j/123?pwd=abc"
        ),
        (nil, nil, "see https://docs.example/agenda", "https://docs.example/agenda"),
        (nil, "Conference Room A", nil, ""),
        (nil, "http://insecure.example", nil, ""),
        (nil, nil, nil, ""),
    ])
    func picks(url: String?, location: String?, notes: String?, expected: String) {
        #expect(CalendarEventURL.pick(url: url, location: location, notes: notes) == expected)
    }
}
