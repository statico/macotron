import Foundation
import Testing
@testable import Modules

@Suite("CalendarUpcoming")
struct CalendarUpcomingTests {
    @Test("prefers event.url over an https location")
    func prefersEventURL() {
        #expect(CalendarEventURL.pick(url: "https://meet.example/a", location: "https://zoom.example/b") == "https://meet.example/a")
    }

    @Test("uses https location when event.url is missing")
    func usesHTTPSLocation() {
        #expect(CalendarEventURL.pick(url: nil, location: "https://zoom.example/b") == "https://zoom.example/b")
        #expect(CalendarEventURL.pick(url: "", location: "Join https://meet.example/c") == "Join https://meet.example/c")
    }

    @Test("empty when there is no url and location has no https")
    func emptyWithoutHTTPS() {
        #expect(CalendarEventURL.pick(url: nil, location: "Conference Room A") == "")
        #expect(CalendarEventURL.pick(url: nil, location: "http://insecure.example") == "")
        #expect(CalendarEventURL.pick(url: nil, location: nil) == "")
    }
}
