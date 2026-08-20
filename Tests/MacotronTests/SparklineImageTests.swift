import Foundation
import Testing
@testable import Modules

@Suite("SparklineImage")
struct SparklineImageTests {
    @Test("sparkline produces a non-empty PNG")
    func nonemptyPNG() throws {
        let png = try #require(SparklineImage.png(
            values: [0.2, 0.4, 0.9, 0.5, 0.1],
            width: 36,
            height: 18,
            color: "#34C759"
        ))
        #expect(png.count > 8)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("empty values returns nil")
    func emptyValues() {
        #expect(SparklineImage.png(values: [], width: 36, height: 18, color: nil) == nil)
    }
}
