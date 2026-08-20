import Testing
@testable import Modules

@Suite("HIDFilter")
struct HIDFilterTests {
    @Test("parses hidapitester vid/pid strings")
    func vidpid() {
        #expect(HIDFilter.parseVidPid("27b8/1ed") == (0x27b8, 0x1ed))
        #expect(HIDFilter.parseVidPid("0x27b8:0x01ed") == (0x27b8, 0x1ed))
        #expect(HIDFilter.parseVidPid("27b8") == (0x27b8, nil))
        #expect(HIDFilter.parseVidPid("0/1ed") == (nil, 0x1ed))
    }

    @Test("object filter matches vendor and usage")
    func matches() {
        let filter = HIDFilter(["vidpid": "27b8/1ed", "usagePage": 0xFF00])
        #expect(filter.vendorID == 0x27b8)
        #expect(filter.productID == 0x1ed)
        #expect(filter.usagePage == 0xFF00)
        #expect(filter.matches([
            "vendorID": 0x27b8,
            "productID": 0x1ed,
            "usagePage": 0xFF00,
            "usage": 1,
            "serial": "",
            "path": "a",
        ]))
        #expect(!filter.matches([
            "vendorID": 0x27b8,
            "productID": 0x1ed,
            "usagePage": 1,
            "usage": 6,
            "serial": "",
            "path": "a",
        ]))
    }
}

@Suite("HIDBytes")
struct HIDBytesTests {
    @Test("parses arrays and comma lists")
    func parse() {
        #expect(HIDBytes.parse([1, 99, 0, 255]) == [1, 99, 0, 255])
        #expect(HIDBytes.parse("1,99,0,0xff") == [1, 99, 0, 255])
        #expect(HIDBytes.parse("bad") == nil)
    }

    @Test("pads to length")
    func pad() {
        #expect(HIDBytes.pad([3, 42], length: 4) == [3, 42, 0, 0])
        #expect(HIDBytes.pad([3, 42], length: 2) == [3, 42])
    }
}

@Suite("HIDReport")
struct HIDReportTests {
    @Test("skips a leading zero report id")
    func setSlice() {
        #expect(HIDReport.setSlice([0, 0x4f, 33]) == (0, 1))
        #expect(HIDReport.setSlice([3, 42]) == (3, 0))
        #expect(HIDReport.setSlice([0]) == (0, 0))
    }
}
