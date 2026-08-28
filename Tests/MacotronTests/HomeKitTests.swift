import Testing
@testable import Modules

@Suite("HomeKit")
struct HomeKitTests {
    @Test("maps home id and name")
    func mapsHome() {
        let row = HomeKitAccess.home(HomeKitHomeSnap(id: "h1", name: "Casa"))
        #expect(row["id"] as? String == "h1")
        #expect(row["name"] as? String == "Casa")
    }

    /// An accessory row mirrors the snapshot: `on` and `value` are present only
    /// when the accessory reports them, so an unknown type still lists.
    @Test("accessory rows mirror the snapshot", arguments: [
        HomeKitAccessorySnap(
            id: "lamp", name: "Desk lamp", room: "Office", type: "lightbulb",
            on: true, value: nil, reachable: true
        ),
        HomeKitAccessorySnap(
            id: "x", name: "Bridge", room: "", type: "bridge",
            on: nil, value: nil, reachable: false
        ),
        HomeKitAccessorySnap(
            id: "t", name: "Temp", room: "Hall", type: "sensor",
            on: nil, value: 21.5, reachable: true
        ),
    ])
    func mapsAccessory(snap: HomeKitAccessorySnap) {
        let row = HomeKitAccess.accessory(snap)
        #expect(row["id"] as? String == snap.id)
        #expect(row["name"] as? String == snap.name)
        #expect(row["room"] as? String == snap.room)
        #expect(row["type"] as? String == snap.type)
        #expect(row["reachable"] as? Bool == snap.reachable)
        #expect(row["on"] as? Bool == snap.on)
        #expect((row["on"] == nil) == (snap.on == nil))
        #expect(row["value"] as? Double == snap.value)
        #expect((row["value"] == nil) == (snap.value == nil))
    }
}
