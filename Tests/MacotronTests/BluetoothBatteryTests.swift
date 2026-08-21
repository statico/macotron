import Foundation
import Testing
@testable import Modules

@Suite("BluetoothBattery")
struct BluetoothBatteryTests {
    @Test("maps connected AirPods and keyboard; skips a mouse with no battery")
    func parse() throws {
        let json = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "AirPods Pro": {
                    "device_address": "11-22-33-44-55-66",
                    "device_batteryLevelLeft": "80%",
                    "device_batteryLevelRight": "42%",
                    "device_batteryLevelCase": "90%"
                  }
                },
                {
                  "Magic Keyboard": {
                    "device_address": "AA-BB-CC-DD-EE-FF",
                    "device_batteryLevel": "87%"
                  }
                }
              ],
              "device_not_connected": [
                {
                  "Magic Mouse": {
                    "device_address": "00-11-22-33-44-55"
                  }
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let map = BluetoothBattery.parse(json)
        #expect(map["AirPods Pro"] == 42)
        #expect(map["11-22-33-44-55-66"] == 42)
        #expect(map["Magic Keyboard"] == 87)
        #expect(map["aa-bb-cc-dd-ee-ff"] == 87)
        #expect(map["Magic Mouse"] == nil)
        #expect(map["00-11-22-33-44-55"] == nil)
    }
}
