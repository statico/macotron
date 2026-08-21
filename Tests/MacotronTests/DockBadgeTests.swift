import Testing
@testable import Modules

@Suite("DockBadge")
struct DockBadgeTests {
    @Test("reads AXStatusLabel as the badge")
    func statusLabel() {
        #expect(DockBadges.badgeString(["AXStatusLabel": "3"]) == "3")
    }

    @Test("falls back to AXBadgeDescription")
    func badgeDescription() {
        #expect(DockBadges.badgeString(["AXBadgeDescription": "•"]) == "•")
        #expect(DockBadges.badgeString(["AXStatusLabel": "", "AXBadgeDescription": "9+"]) == "9+")
    }

    @Test("empty badge is skipped")
    func skipsEmpty() {
        let rows = DockBadges.parse([
            ["title": "Mail", "attributes": ["AXStatusLabel": "2"], "bundleID": "com.apple.mail"],
            ["title": "Safari", "attributes": ["AXStatusLabel": ""]],
            ["title": "Notes", "attributes": [:] as [String: String]],
        ])
        #expect(rows.count == 1)
        #expect(rows[0]["app"] as? String == "Mail")
        #expect(rows[0]["badge"] as? String == "2")
        #expect(rows[0]["bundleID"] as? String == "com.apple.mail")
    }

    @Test("number attributes stringify")
    func numberBadge() {
        #expect(DockBadges.badgeString(["AXStatusLabel": 12]) == "12")
    }
}
