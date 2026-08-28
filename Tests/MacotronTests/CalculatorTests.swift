import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Calculator")
struct CalculatorTests {
    /// Runs the real plugin in the real engine, so this also proves QuickJS
    /// accepts the syntax the parser leans on (spread, lookbehind).
    private func result(_ query: String) throws -> String {
        try PluginHarness.eval(plugin: "calculator.js", mock: #"""
            var __query = null;
            var macotron = {
                plugin: () => ({}),
                launcher: { query: (_id, fn) => { __query = fn; } },
                clipboard: {}, notify: {},
            };
            """#, extra: """
            (function () {
                var hits = __query(\(String(reflecting: query)));
                return hits.length ? hits[0].title : "";
            })()
            """)
    }

    @Test("arithmetic")
    func arithmetic() throws {
        #expect(try result("2+2*10") == "22")
        #expect(try result("(3+4)/2") == "3.5")
        #expect(try result("2^10") == "1,024")
        #expect(try result("sqrt(16)") == "4")
        #expect(try result("1e3 * 2") == "2,000")
    }

    @Test("percentages")
    func percentages() throws {
        #expect(try result("20% of 85") == "17")
        #expect(try result("85 + 20%") == "102")
        #expect(try result("200 - 15%") == "170")
    }

    @Test("unit conversion")
    func units() throws {
        #expect(try result("5 mi to km") == "8.04672 km")
        #expect(try result("2 GB in MB") == "2,000 MB")
        #expect(try result("1 day in minutes") == "1,440 minutes")
        #expect(try result("3 in in cm") == "7.62 cm")
    }

    @Test("temperature pivots through kelvin")
    func temperature() throws {
        #expect(try result("0c in f") == "32 f")
        #expect(try result("212 f to c") == "100 c")
    }

    @Test("ordinary launcher text yields nothing")
    func passthrough() throws {
        for query in ["safari", "hello world", "5", "open 2 files", "1 kg in miles", "2 apples in oranges"] {
            #expect(try result(query) == "", "\(query) should not produce a result")
        }
    }
}
