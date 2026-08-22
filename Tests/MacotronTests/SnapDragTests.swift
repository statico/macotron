import CoreGraphics
import Darwin
import Testing
@testable import Modules

@Suite("SnapDrag")
struct SnapDragTests {
    @Test("a click does not snap")
    func click() {
        var drag = SnapDrag()
        drag.down(CGPoint(x: 10, y: 10))
        drag.moved(CGPoint(x: 12, y: 11))
        let snapped = drag.up()
        #expect(!snapped)
    }

    @Test("a drag past slop snaps")
    func drag() {
        var drag = SnapDrag()
        drag.down(CGPoint(x: 0, y: 0))
        drag.moved(CGPoint(x: SnapDrag.slop + 1, y: 0))
        let snapped = drag.up()
        #expect(snapped)
    }
}

@Suite("CoreTopology")
struct CoreTopologyTests {
    @Test("the cluster split covers every logical core")
    func split() {
        let split = CoreTopology.split
        #expect(split.efficiency + split.performance == CoreTopology.count("hw.logicalcpu"))
        #expect(split.performance > 0)
        #expect(split.efficiency >= 0)
    }
}

@Suite("CPULoad")
struct CPULoadTests {
    @Test("busy ticks are a percent of the total")
    func percent() {
        var prev = host_cpu_load_info()
        prev.cpu_ticks = (100, 50, 850, 0)
        var now = host_cpu_load_info()
        now.cpu_ticks = (150, 70, 870, 0)
        #expect(CPULoad.percent(from: prev, to: now) == (70.0 / 90.0) * 100)
    }

    @Test("zero delta is zero")
    func zero() {
        var ticks = host_cpu_load_info()
        ticks.cpu_ticks = (1, 2, 3, 4)
        #expect(CPULoad.percent(from: ticks, to: ticks) == 0)
    }
}
