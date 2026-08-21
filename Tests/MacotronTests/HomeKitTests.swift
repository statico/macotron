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

    @Test("maps accessory name, room, and on")
    func mapsAccessoryOn() {
        let row = HomeKitAccess.accessory(HomeKitAccessorySnap(
            id: "lamp",
            name: "Desk lamp",
            room: "Office",
            type: "lightbulb",
            on: true,
            value: nil,
            reachable: true
        ))
        #expect(row["id"] as? String == "lamp")
        #expect(row["name"] as? String == "Desk lamp")
        #expect(row["room"] as? String == "Office")
        #expect(row["type"] as? String == "lightbulb")
        #expect(row["on"] as? Bool == true)
        #expect(row["value"] == nil)
        #expect(row["reachable"] as? Bool == true)
    }

    @Test("unknown accessory still lists without on or value")
    func unknownAccessory() {
        let row = HomeKitAccess.accessory(HomeKitAccessorySnap(
            id: "x",
            name: "Bridge",
            room: "",
            type: "bridge",
            on: nil,
            value: nil,
            reachable: false
        ))
        #expect(row["name"] as? String == "Bridge")
        #expect(row["on"] == nil)
        #expect(row["value"] == nil)
        #expect(row["reachable"] as? Bool == false)
    }

    @Test("sensor value is a number")
    func sensorValue() {
        let row = HomeKitAccess.accessory(HomeKitAccessorySnap(
            id: "t",
            name: "Temp",
            room: "Hall",
            type: "sensor",
            on: nil,
            value: 21.5,
            reachable: true
        ))
        #expect(row["value"] as? Double == 21.5)
        #expect(row["on"] == nil)
    }
}
