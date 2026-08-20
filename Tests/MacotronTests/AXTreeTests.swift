import CoreGraphics
import Testing
@testable import Modules

@Suite("AX handles")
struct AXHandleTests {
    @Test func allocLookup() {
        let table = AXHandleTable<String>()
        let a = table.alloc("one")
        let b = table.alloc("two")
        #expect(a != b)
        #expect(table.lookup(a) == "one")
        #expect(table.lookup(b) == "two")
        #expect(table.lookup(99) == nil)
        table.clear()
        #expect(table.lookup(a) == nil)
        #expect(table.lookup(b) == nil)
    }
}

@Suite("AX attributes")
struct AXAttrsTests {
    @Test func mapsRoleNames() {
        #expect(AXAttrs.matchRole("AXButton", "button"))
        #expect(AXAttrs.matchRole("AXButton", "AXButton"))
        #expect(AXAttrs.matchRole("AXTextField", "textfield"))
        #expect(!AXAttrs.matchRole("AXButton", "textfield"))
    }

    @Test func mapsNode() {
        let dict = AXAttrs.js(
            id: 3,
            role: "AXButton",
            title: "OK",
            value: "",
            frame: CGRect(x: 1, y: 2, width: 10, height: 20)
        )
        #expect(dict["id"] as? Int == 3)
        #expect(dict["role"] as? String == "AXButton")
        #expect(dict["title"] as? String == "OK")
        let frame = dict["frame"] as? [String: CGFloat]
        #expect(frame?["x"] == 1)
        #expect(frame?["y"] == 2)
        #expect(frame?["width"] == 10)
        #expect(frame?["height"] == 20)
    }

    @Test func findNeedsAFilter() {
        #expect(!AXAttrs.matches(role: "AXButton", title: "OK", wantRole: nil, wantTitle: nil))
        #expect(AXAttrs.matches(role: "AXButton", title: "OK", wantRole: "button", wantTitle: nil))
        #expect(AXAttrs.matches(role: "AXButton", title: "OK", wantRole: nil, wantTitle: "ok"))
        #expect(!AXAttrs.matches(role: "AXButton", title: "OK", wantRole: "textfield", wantTitle: nil))
    }
}
