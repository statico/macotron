import AppKit
import Testing
@testable import Modules

@Suite("GestureEvent")
struct GestureTests {
    @Test("direction from dx/dy")
    func direction() {
        #expect(GestureEvent.direction(dx: -1, dy: 0) == "left")
        #expect(GestureEvent.direction(dx: 1, dy: 0) == "right")
        #expect(GestureEvent.direction(dx: 0, dy: 1) == "up")
        #expect(GestureEvent.direction(dx: 0, dy: -1) == "down")
        #expect(GestureEvent.direction(dx: 3, dy: 1) == "right")
        #expect(GestureEvent.direction(dx: -3, dy: 1) == "left")
        #expect(GestureEvent.direction(dx: 1, dy: 4) == "up")
        #expect(GestureEvent.direction(dx: 1, dy: -4) == "down")
    }

    @Test("type names")
    func typeNames() {
        #expect(GestureEvent.typeName(.swipe) == "swipe")
        #expect(GestureEvent.typeName(.magnify) == "magnify")
        #expect(GestureEvent.typeName(.rotate) == "rotate")
        #expect(GestureEvent.typeName(.keyDown) == nil)
        #expect(GestureEvent.mask(for: "swipe") == .swipe)
        #expect(GestureEvent.mask(for: "magnify") == .magnify)
        #expect(GestureEvent.mask(for: "rotate") == .rotate)
        #expect(GestureEvent.mask(for: "keyDown") == nil)
        #expect(EventPost.tapMask(for: "swipe") == nil)
        #expect(EventPost.tapMask(for: "magnify") == nil)
        #expect(EventPost.tapMask(for: "rotate") == nil)
    }

    @Test("payload builder")
    func payload() {
        let swipe = GestureEvent.payload(type: "swipe", fingers: 3, dx: -1, dy: 0, delta: 0, flags: ["cmd"])
        #expect(swipe.type == "swipe")
        #expect(swipe.fingers == 3)
        #expect(swipe.direction == "left")
        #expect(swipe.delta == 0)
        #expect(swipe.flags == ["cmd"])

        let magnify = GestureEvent.payload(type: "magnify", fingers: 2, dx: 0, dy: 0, delta: 0.25, flags: [])
        #expect(magnify.type == "magnify")
        #expect(magnify.direction == "")
        #expect(magnify.delta == 0.25)

        let rotate = GestureEvent.payload(type: "rotate", fingers: 2, dx: 0, dy: 0, delta: -15, flags: [])
        #expect(rotate.type == "rotate")
        #expect(rotate.delta == -15)

        #expect(GestureEvent.fingers(touchCount: 4, type: "swipe") == 4)
        #expect(GestureEvent.fingers(touchCount: 0, type: "swipe") == 3)
        #expect(GestureEvent.fingers(touchCount: 0, type: "magnify") == 2)
    }
}
