import Foundation
import Testing
@testable import Modules

@Suite("BonjourBrowse")
struct BonjourBrowseTests {
    @Test("strips trailing local. from service types")
    func normalizeType() {
        #expect(BonjourBrowse.normalizeType("_companion-link._tcp") == "_companion-link._tcp")
        #expect(BonjourBrowse.normalizeType("_airplay._tcp.") == "_airplay._tcp")
        #expect(BonjourBrowse.normalizeType("_airplay._tcp.local.") == "_airplay._tcp")
        #expect(BonjourBrowse.normalizeType("_companion-link._tcp.local") == "_companion-link._tcp")
        #expect(BonjourBrowse.normalizeType("  _http._tcp.local.  ") == "_http._tcp")
    }

    @Test("maps a resolved service to the JS dict shape")
    func rowFromFixture() {
        let row = BonjourBrowse.row(
            name: "Living Room",
            type: "_airplay._tcp.local.",
            host: "Living-Room.local.",
            port: 7000,
            txt: ["deviceid": Data("AA:BB".utf8), "features": Data("0x1".utf8)]
        )
        #expect(row["name"] as? String == "Living Room")
        #expect(row["type"] as? String == "_airplay._tcp")
        #expect(row["host"] as? String == "Living-Room.local.")
        #expect(row["port"] as? Int == 7000)
        let txt = row["txt"] as? [String: String]
        #expect(txt?["deviceid"] == "AA:BB")
        #expect(txt?["features"] == "0x1")
    }

    @Test("dry-run browse returns no services")
    func dryRun() {
        #expect(BonjourBrowse.browse(type: "_airplay._tcp", timeout: 0.1, dryRun: true).isEmpty)
    }
}
