import AppKit
import CoreAudio
import Foundation
import IOKit.ps
import Testing
@testable import Modules

@Suite("AudioDevices")
struct AudioDevicesTests {
    @Test("volume clamps to 0...1")
    func clamp() {
        #expect(AudioDevices.clampVolume(-1) == 0)
        #expect(AudioDevices.clampVolume(0.25) == 0.25)
        #expect(AudioDevices.clampVolume(2) == 1)
    }

    @Test("mute prefers input scope when the device has input")
    func muteScope() {
        #expect(AudioDevices.muteScope(input: true, output: false) == kAudioObjectPropertyScopeInput)
        #expect(AudioDevices.muteScope(input: false, output: true) == kAudioObjectPropertyScopeOutput)
        #expect(AudioDevices.muteScope(input: true, output: true) == kAudioObjectPropertyScopeInput)
        #expect(AudioDevices.muteScope(input: false, output: false) == kAudioObjectPropertyScopeOutput)
    }
}

@Suite("Spaces")
struct SpacesTests {
    @Test("type names")
    func types() {
        #expect(Spaces.typeName(0) == "user")
        #expect(Spaces.typeName(4) == "fullscreen")
        #expect(Spaces.typeName(9) == "other")
    }

    @Test("parse display dictionaries")
    func parse() {
        let raw: [[String: Any]] = [
            [
                "Display Identifier": "ABC",
                "Current Space": ["id64": 11],
                "Spaces": [
                    ["id64": 10, "type": 0],
                    ["id64": 11, "type": 0],
                    ["id64": 12, "type": 4],
                ],
            ],
        ]
        let spaces = Spaces.parse(raw)
        #expect(spaces.count == 3)
        #expect(spaces[0].desktop == 1)
        #expect(spaces[1].desktop == 2)
        #expect(spaces[1].current)
        #expect(spaces[1].index == 2)
        #expect(spaces[1].display == "ABC")
        #expect(spaces[2].type == "fullscreen")
        #expect(!spaces[0].current)
    }

    @Test("int coercion")
    func ints() {
        #expect(Spaces.int(3) == 3)
        #expect(Spaces.int(NSNumber(value: 9)) == 9)
        #expect(Spaces.int(2.0) == 2)
        #expect(Spaces.int("x") == nil)
    }
}

@Suite("AppMenu")
struct AppMenuTests {
    @Test("shortcut suffix is ignored")
    func shortcut() {
        #expect(AppMenu.stripShortcut("New\t⌘N") == "New")
        #expect(AppMenu.match("New Window…", "New Window"))
        #expect(AppMenu.match("Save", "Save"))
        #expect(!AppMenu.match("Save As…", "Save"))
    }
}

@Suite("ShortcutsCLI")
struct ShortcutsCLITests {
    @Test("list output splits on lines")
    func parse() {
        #expect(ShortcutsCLI.parseList("One\nTwo\n\nThree\n") == ["One", "Two", "Three"])
    }
}

@Suite("AppControl")
struct AppControlTests {
    @Test("empty bundle id uses the frontmost app helper")
    func running() {
        #expect(AppControl.running("io.statico.macotron.missing-app") == nil)
    }
}

@Suite("BatteryStatus")
struct BatteryStatusTests {
    @Test("maps IOPS fields including time remaining")
    func snapshot() {
        let snap = BatteryStatus.snapshot([[
            kIOPSCurrentCapacityKey as String: 80,
            kIOPSMaxCapacityKey as String: 100,
            kIOPSPowerSourceStateKey as String: kIOPSACPowerValue as String,
            kIOPSIsChargedKey as String: false,
            kIOPSTimeToEmptyKey as String: -1,
            kIOPSTimeToFullChargeKey as String: 45,
        ]])
        #expect(snap["level"] as? Double == 80)
        #expect(snap["charging"] as? Bool == true)
        #expect(snap["charged"] as? Bool == false)
        #expect(snap["timeRemaining"] as? Int == -1)
        #expect(snap["timeToFull"] as? Int == 45)
        #expect(snap["source"] as? String == "ac")
    }

    @Test("smart battery extras include health, cycles, and adapter watts")
    func smartExtras() {
        let extras = BatteryStatus.smartExtras([
            "CycleCount": 69,
            "AppleRawMaxCapacity": 6004,
            "DesignCapacity": 6249,
            "AdapterDetails": ["Watts": 87],
        ])
        #expect(extras["cycles"] as? Int == 69)
        #expect(extras["health"] as? Int == 96)
        #expect(extras["watts"] as? Int == 87)
    }

    @Test("low power mode script uses pmset with admin privileges")
    func lowPowerModeScript() {
        #expect(LowPowerMode.script(true).contains("lowpowermode 1"))
        #expect(LowPowerMode.script(false).contains("lowpowermode 0"))
        #expect(LowPowerMode.script(true).contains("administrator privileges"))
    }

    @Test("low power mode dry run skips pmset")
    func lowPowerModeDryRun() {
        let result = LowPowerMode.set(true, dryRun: true)
        #expect(result["ok"] as? Bool == true)
        #expect(result["lowPowerMode"] as? Bool == true)
        #expect(result["error"] == nil)
    }
}

@Suite("ClipboardPasteboard")
struct ClipboardPasteboardTests {
    @Test("types are UTI strings")
    func typeNames() {
        #expect(ClipboardPasteboard.names([.string, .png]) == [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
        ])
    }
}

@Suite("ContactsList")
struct ContactsListTests {
    @Test("search matches name email phone org")
    func matches() {
        #expect(ContactsList.matches("ada", name: "Ada Lovelace", emails: ["ada@x.com"], phones: [], organization: ""))
        #expect(ContactsList.matches("555", name: "Ada", emails: [], phones: ["555-0100"], organization: ""))
        #expect(ContactsList.matches("acme", name: "Ada", emails: [], phones: [], organization: "Acme"))
        #expect(!ContactsList.matches("bob", name: "Ada Lovelace", emails: [], phones: [], organization: ""))
        #expect(ContactsList.matches("", name: "Ada", emails: [], phones: [], organization: ""))
    }
}
