// StepTimer.swift — millisecond step timing for slow interactive paths
import Foundation
import os

/// Logs how long each step of a slow path took, plus a running total. Timing
/// only: it never changes behavior, so it is safe to leave in place.
public final class StepTimer {
    private let logger: Logger
    private let name: String
    private let start = CFAbsoluteTimeGetCurrent()
    private var last = CFAbsoluteTimeGetCurrent()

    public init(_ name: String, category: String) {
        self.name = name
        self.logger = Logger(subsystem: "io.statico.macotron", category: category)
    }

    public func step(_ label: String) {
        let now = CFAbsoluteTimeGetCurrent()
        logger.info(
            "\(self.name, privacy: .public) \(label, privacy: .public) +\(Self.ms(now - self.last))ms total \(Self.ms(now - self.start))ms"
        )
        last = now
    }

    public func total(_ label: String = "done") {
        logger.info(
            "\(self.name, privacy: .public) \(label, privacy: .public) \(Self.ms(CFAbsoluteTimeGetCurrent() - self.start))ms"
        )
    }

    private static func ms(_ seconds: CFAbsoluteTime) -> Int { Int(seconds * 1000) }
}
