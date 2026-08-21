import Foundation

struct HomeKitHomeSnap {
    var id: String
    var name: String
}

struct HomeKitAccessorySnap {
    var id: String
    var name: String
    var room: String
    var type: String
    var on: Bool?
    var value: Double?
    var reachable: Bool
}

enum HomeKitAccess {
    static func home(_ snap: HomeKitHomeSnap) -> [String: Any] {
        ["id": snap.id, "name": snap.name]
    }

    static func accessory(_ snap: HomeKitAccessorySnap) -> [String: Any] {
        var row: [String: Any] = [
            "id": snap.id,
            "name": snap.name,
            "room": snap.room,
            "type": snap.type,
            "reachable": snap.reachable,
        ]
        if let on = snap.on { row["on"] = on }
        if let value = snap.value { row["value"] = value }
        return row
    }
}
