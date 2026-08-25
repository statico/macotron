// EventTapThread.swift — one dedicated run loop that hosts the CGEvent taps
import CoreGraphics
import Foundation

/// macOS gives a CGEvent tap a short deadline to return and disables the tap when it is
/// missed, so hosting the tap sources here instead of on the main run loop keeps input
/// handling alive while the main thread renders or runs plugin JS. One thread serves every
/// tap: callbacks are short, and sharing keeps their ordering as predictable as it was on main.
public final class EventTapThread: @unchecked Sendable {
    public static let shared = EventTapThread()

    private let lock = NSLock()
    private var runLoop: CFRunLoop?

    private init() {}

    public func add(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(started(), source, .commonModes)
    }

    public func remove(_ source: CFRunLoopSource) {
        CFRunLoopRemoveSource(started(), source, .commonModes)
    }

    /// Runs `block` on the tap thread; the taps themselves need no such hop, this is the
    /// seam that lets callers (and tests) reach the loop.
    public func perform(_ block: @escaping @Sendable () -> Void) {
        let loop = started()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    private func started() -> CFRunLoop {
        lock.lock()
        defer { lock.unlock() }
        if let runLoop { return runLoop }

        let ready = DispatchSemaphore(value: 0)
        let box = Box()
        let thread = Thread {
            box.loop = CFRunLoopGetCurrent()
            ready.signal()
            // An idle run loop with no sources returns immediately, so keep a port attached.
            RunLoop.current.add(NSMachPort(), forMode: .common)
            while true { CFRunLoopRun() }
        }
        thread.name = "io.statico.macotron.eventtaps"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        runLoop = box.loop
        return box.loop!
    }

    private final class Box: @unchecked Sendable {
        var loop: CFRunLoop?
    }
}
