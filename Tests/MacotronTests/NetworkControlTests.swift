import Foundation
import Testing
@testable import Modules

@Suite("NetworkControl")
struct NetworkControlTests {
    @Test("finds the Wi-Fi BSD device from networksetup ports")
    func wifiDevice() {
        let text = """
        Hardware Port: Ethernet
        Device: en0
        Ethernet Address: aa:bb:cc:dd:ee:ff

        Hardware Port: Wi-Fi
        Device: en1
        Ethernet Address: 11:22:33:44:55:66
        """
        #expect(NetworkControl.wifiDevice(from: text) == "en1")
    }

    @Test("accepts AirPort as the Wi-Fi port name")
    func airportDevice() {
        let text = """
        Hardware Port: AirPort
        Device: en0
        """
        #expect(NetworkControl.wifiDevice(from: text) == "en0")
    }

    @Test("parses airport power")
    func power() {
        #expect(NetworkControl.parsePower("Wi-Fi Power (en0): On") == true)
        #expect(NetworkControl.parsePower("Wi-Fi Power (en1): Off") == false)
        #expect(NetworkControl.parsePower("") == nil)
    }

    @Test("parses airport SSID")
    func ssid() {
        #expect(NetworkControl.parseSSID("Current Wi-Fi Network: Cafe") == "Cafe")
        #expect(NetworkControl.parseSSID("You are not associated with an AirPort network.") == nil)
        #expect(NetworkControl.parseSSID("") == nil)
    }

    @Test("normalizes AirDrop discoverable mode")
    func airDropMode() {
        #expect(NetworkControl.parseAirDrop("Off") == "off")
        #expect(NetworkControl.parseAirDrop("Contacts Only") == "contacts")
        #expect(NetworkControl.parseAirDrop("Everyone") == "everyone")
        #expect(NetworkControl.parseAirDrop("contacts") == "contacts")
        #expect(NetworkControl.parseAirDrop(nil) == "off")
        #expect(NetworkControl.airDropPlistValue("off") == "Off")
        #expect(NetworkControl.airDropPlistValue("contacts") == "Contacts Only")
        #expect(NetworkControl.airDropPlistValue("everyone") == "Everyone")
        #expect(NetworkControl.airDropPlistValue("nope") == nil)
    }

    @Test("run merges stdout and stderr, trims, and reports the status")
    func runMergesOutput() {
        // Every networksetup caller below parses `out` as one blob and treats
        // a non-zero status as the error path, so both halves are contract.
        let good = NetworkControl.run("/bin/sh", ["-c", "echo out; echo err >&2"])
        #expect(good.ok)
        #expect(good.out.contains("out"))
        #expect(good.out.contains("err"))
        #expect(!good.out.hasSuffix("\n"))

        let bad = NetworkControl.run("/bin/sh", ["-c", "exit 7"])
        #expect(!bad.ok)
        #expect(bad.out.isEmpty)

        #expect(!NetworkControl.run("/nonexistent/tool", []).ok)
    }

    @Test("wifi set is a no-op in dry run")
    func wifiDryRun() {
        let result = NetworkControl.setWifi(true, dryRun: true)
        #expect(result["ok"] as? Bool == true)
        #expect(result["on"] as? Bool == true)
    }

    @Test("AirDrop set is a no-op in dry run")
    func airDropDryRun() {
        let result = NetworkControl.setAirDrop("everyone", dryRun: true)
        #expect(result["ok"] as? Bool == true)
        #expect(result["mode"] as? String == "everyone")
    }
}

@Suite("BluetoothRadio")
struct BluetoothRadioTests {
    @Test("set is a no-op in dry run")
    func dryRun() {
        let result = BluetoothRadio.set(true, dryRun: true)
        #expect(result["ok"] as? Bool == true)
        #expect(result["on"] as? Bool == true)
    }

    /// Reading the radio goes through TCC, which aborts the whole process when the
    /// bundle ships no usage string.
    @Test("the bundle says why it uses Bluetooth")
    func usageDescription() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Info.plist")
        let data = try Data(contentsOf: plist)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any]
        let reason = root?["NSBluetoothAlwaysUsageDescription"] as? String
        #expect(reason?.isEmpty == false)
    }
}

@Suite("DarkMode")
struct DarkModeTests {
    @Test("parses System Events true/false")
    func parse() {
        #expect(DarkMode.parse("true") == true)
        #expect(DarkMode.parse("false") == false)
        #expect(DarkMode.parse("true\n") == true)
        #expect(DarkMode.parse("nope") == nil)
    }

    @Test("set is a no-op in dry run")
    func dryRun() {
        let result = DarkMode.set(true, dryRun: true)
        #expect(result["ok"] as? Bool == true)
        #expect(result["darkMode"] as? Bool == true)
    }
}
