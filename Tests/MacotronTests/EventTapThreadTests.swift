import XCTest

@testable import MacotronEngine

final class EventTapThreadTests: XCTestCase {
    func testRunsBlocksOffMainAndStaysAlive() {
        for _ in 0..<2 {
            let done = expectation(description: "ran on the tap thread")
            EventTapThread.shared.perform {
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(Thread.current.name, "io.statico.macotron.eventtaps")
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
        }
    }

    func testAddAndRemoveSourceKeepsLoopRunning() {
        var context = CFRunLoopSourceContext()
        guard let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else {
            return XCTFail("no run loop source")
        }
        EventTapThread.shared.add(source)
        EventTapThread.shared.remove(source)

        let done = expectation(description: "still running")
        EventTapThread.shared.perform { done.fulfill() }
        wait(for: [done], timeout: 5)
    }
}
