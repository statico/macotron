import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("MenuPlugins")
struct MenuPluginsTests {
    private func pluginURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/\(name)")
    }

    private func load(plugin: String, mock: String) throws -> Engine {
        let url = pluginURL(plugin)
        let source = try String(contentsOf: url, encoding: .utf8)
        let harness = """
            \(mock)
            \(source)
            """
        let engine = Engine()
        let (_, error) = engine.evaluate(harness, filename: url.path)
        #expect(error == nil)
        return engine
    }

    @discardableResult
    private func run(_ engine: Engine, _ extra: String) -> String {
        let (result, error) = engine.evaluate(extra)
        #expect(error == nil)
        return result ?? ""
    }

    private func eval(plugin: String, mock: String, extra: String) throws -> String {
        run(try load(plugin: plugin, mock: mock), extra)
    }

    @Test("mic mute click toggles input and paints a red slash")
    func micMuteToggles() throws {
        let result = try eval(plugin: "mic-mute.js", mock: #"""
            var muted = false;
            var controllable = true;
            var setCalls = [];
            var statusConfig = null;
            var checkRows = [];
            var toasts = [];
            var macotron = {
                plugin: () => ({}),
                on: () => {},
                audio: {
                    input: () => ({ id: 7, name: "Mic", uid: "mic" }),
                    isMuted: () => muted,
                    setMuted: (on, id) => { muted = on; setCalls.push({ on: on, id: id }); return controllable; }
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                checks: (rows) => { checkRows = rows; },
                notify: { toast: (t, b) => { toasts.push(b); } }
            };
            """#, extra: #"""
            statusConfig.onClick();
            JSON.stringify({
                symbol: statusConfig.sfSymbol,
                color: statusConfig.color,
                setCalls: setCalls
            })
            """#)
        #expect(result.contains(#""symbol":"mic.slash.fill""#))
        #expect(result.contains(#""color":"red""#))
        #expect(result.contains(#""on":true"#))
        #expect(result.contains(#""id":7"#))
    }

    /// Many built-in and USB mics expose no settable mute, and Core Audio just
    /// reports the write as failed. Say so rather than pretending it worked.
    @Test("a mic with no mute control reports instead of failing quietly")
    func micMuteUnsupported() throws {
        let result = try eval(plugin: "mic-mute.js", mock: #"""
            var muted = false;
            var controllable = false;
            var setCalls = [];
            var statusConfig = null;
            var checkRows = [];
            var toasts = [];
            var macotron = {
                plugin: () => ({}),
                on: () => {},
                audio: {
                    input: () => ({ id: 7, name: "Mic", uid: "mic" }),
                    isMuted: () => muted,
                    setMuted: (on, id) => { setCalls.push({ on: on, id: id }); return controllable; }
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                checks: (rows) => { checkRows = rows; },
                notify: { toast: (t, b) => { toasts.push(b); } }
            };
            """#, extra: #"""
            statusConfig.onClick();
            JSON.stringify({ checks: checkRows, toasts: toasts, muted: muted })
            """#)
        #expect(result.contains(#""ok":false"#))
        #expect(result.contains("no mute control"))
        #expect(result.contains(#""muted":false"#))
    }

    @Test("headphones unplug pauses; HDMI to speakers does not")
    func headphonePause() throws {
        let result = try eval(plugin: "headphone-pause.js", mock: #"""
            var output = { id: 1, name: "AirPods", uid: "pods" };
            var playing = true;
            var pauses = 0;
            var handler = null;
            var macotron = {
                plugin: () => ({}),
                on: (ev, fn) => { handler = fn; },
                audio: { output: () => output },
                media: {
                    nowPlaying: () => ({ playing: playing }),
                    playPause: () => { pauses++; playing = false; }
                }
            };
            """#, extra: #"""
            output = null;
            handler({ flags: ["output"] });
            var afterUnplug = pauses;
            output = { id: 2, name: "HDMI", uid: "hdmi" };
            last = output;
            playing = true;
            output = { id: 3, name: "Speakers", uid: "spk" };
            handler({ flags: ["output"] });
            JSON.stringify({ afterUnplug: afterUnplug, afterHdmi: pauses })
            """#)
        #expect(result.contains(#""afterUnplug":1"#))
        #expect(result.contains(#""afterHdmi":1"#))
    }

    @Test("profiles switch appearance from SSID")
    func profilesApply() throws {
        let result = try eval(plugin: "profiles.js", mock: #"""
            var dark = null;
            var toasts = [];
            var wifi = { ssid: "HomeNet", on: true };
            var handler = null;
            var macotron = {
                plugin: () => ({ homeSSID: "HomeNet", workSSID: "Office" }),
                on: (ev, fn) => { handler = fn; },
                network: { wifi: () => wifi },
                system: { setDarkMode: (on) => { dark = on; return { ok: true, darkMode: on }; } },
                notify: { toast: (title, body) => { toasts.push({ title: title, body: body }); } }
            };
            """#, extra: #"""
            var homeDark = dark;
            var homeToast = toasts[toasts.length - 1];
            wifi = { ssid: "Office", on: true };
            handler({ ssid: "Office" });
            JSON.stringify({ homeDark: homeDark, workDark: dark, homeToast: homeToast, workToast: toasts[toasts.length - 1] })
            """#)
        #expect(result.contains(#""homeDark":false"#))
        #expect(result.contains(#""workDark":true"#))
        #expect(result.contains(#""body":"Home""#))
        #expect(result.contains(#""body":"Work""#))
    }

    @Test("USB attach speaks and toasts; remove only toasts")
    func usbAnnounces() throws {
        let result = try eval(plugin: "usb.js", mock: #"""
            var toasts = [];
            var says = [];
            var handler = null;
            var macotron = {
                plugin: () => ({}),
                on: (ev, fn) => { handler = fn; },
                notify: { toast: (title, body) => { toasts.push({ title: title, body: body }); } },
                shell: { run: (cmd, args) => { says.push(args); return Promise.resolve({ exitCode: 0 }); } },
                usb: { list: () => [] },
                command: () => {}
            };
            """#, extra: #"""
            handler({ action: "add", name: "Hub" });
            handler({ action: "remove", name: "Hub" });
            JSON.stringify({ toasts: toasts, says: says })
            """#)
        #expect(result.contains("USB Attached"))
        #expect(result.contains("USB Removed"))
        #expect(result.contains(#""Device","Hub","connected""#) || result.contains("Device"))
        #expect(!result.contains(#""remove""#))
    }

    @Test("translate empty selection toasts; success opens a panel")
    func translateSelection() throws {
        let empty = try eval(plugin: "translate.js", mock: #"""
            var toast = null;
            var panels = [];
            var macotron = {
                plugin: () => ({ locale: "" }),
                ax: { selectedText: () => "" },
                notify: { toast: (title, body, opts) => { toast = { title: title, body: body, opts: opts }; } },
                panel: { open: (opts) => { panels.push(opts); } },
                system: { locale: () => ({ language: "es" }) },
                ai: { local: () => ({ chat: () => Promise.resolve("hola") }) },
                command: (name, desc, fn) => { macotron._cmd = fn; }
            };
            """#, extra: #"""
            macotron._cmd();
            JSON.stringify({ toast: toast, panels: panels.length })
            """#)
        #expect(empty.contains(#""title":"Cannot translate""#))
        #expect(empty.contains("No selected text"))
        #expect(empty.contains(#""color":"error""#))
        #expect(empty.contains(#""panels":0"#))

        let engine = try load(plugin: "translate.js", mock: #"""
            var toast = null;
            var panels = [];
            var macotron = {
                plugin: (def) => { macotron._def = def; return { locale: "fr" }; },
                ax: { selectedText: () => "hello" },
                notify: { toast: (title, body) => { toast = { title: title, body: body }; } },
                panel: { open: (opts) => { panels.push(opts); } },
                system: { locale: () => ({ language: "es" }) },
                ai: { local: () => ({ chat: (text, opts) => Promise.resolve("bonjour") }) },
                command: (name, desc, fn) => { macotron._cmd = fn; }
            };
            """#)
        run(engine, "macotron._cmd()")
        let ok = run(engine, "JSON.stringify(panels[0])")
        #expect(ok.contains("hello"))
        #expect(ok.contains("bonjour"))
        #expect(ok.contains(#""title":"Translate""#))
        #expect(ok.contains("Translation to fr:"))

        // The empty locale field hints the system locale instead of saying so in the label.
        let placeholder = run(engine, "macotron._def.options.locale.placeholder")
        #expect(placeholder == "es")
    }

    @Test("world clock paints each zone every 30s")
    func worldClock() throws {
        let result = try eval(plugin: "world-clock.js", mock: #"""
            var statuses = [];
            var everyMs = 0;
            var macotron = {
                plugin: () => ({ zones: "America/Los_Angeles\nEurope/London\nUTC" }),
                menubar: { status: (id, cfg) => { statuses.push({ id: id, title: cfg.title, subtitle: cfg.subtitle, secondary: cfg.secondary, minWidth: cfg.minWidth }); } },
                every: (ms) => { everyMs = ms; },
                system: { timeIn: () => "09:41" }
            };
            """#, extra: #"""
            JSON.stringify({
                everyMs: everyMs,
                statuses: statuses,
                labels: ["America/Los_Angeles", "Europe/London"].map(zoneLabel)
            })
            """#)
        #expect(result.contains(#""everyMs":30000"#))
        #expect(result.contains("clock-America/Los_Angeles"))
        #expect(result.contains("Los Angeles"))
        #expect(result.contains("London"))
        #expect(result.contains(#""minWidth":48"#))
        #expect(result.contains(#""secondary":true"#))
        #expect(result.contains(#""title":"09:41""#))
    }

    @Test("eject skips Macintosh HD and Data")
    func ejectFilter() throws {
        let result = try eval(plugin: "eject.js", mock: #"""
            var statusConfig = null;
            var runs = [];
            var confirmOk = false;
            function confirm() { return confirmOk; }
            var macotron = {
                plugin: () => ({}),
                command: () => {},
                fs: { list: () => ["Macintosh HD", "Macintosh HD - Data", "Data", "Backup", ".hidden"] },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                every: () => {},
                shell: { run: (cmd, args) => { runs.push({ cmd: cmd, args: args }); } }
            };
            """#, extra: #"""
            var names = userVolumes(["Macintosh HD", "Data", "Stick", ".foo"]);
            statusConfig.menu[0].onClick();
            var menu = statusConfig.menu.map(r => r.title);
            confirmOk = false;
            statusConfig.menu[menu.length - 1].onClick();
            var afterNo = runs.length;
            confirmOk = true;
            statusConfig.menu[menu.length - 1].onClick();
            JSON.stringify({
                names: names,
                symbol: statusConfig.sfSymbol,
                runs: runs,
                afterNo: afterNo,
                menu: menu,
                last: menu[menu.length - 1]
            })
            """#)
        #expect(result.contains(#""Stick""#))
        #expect(!result.contains("Macintosh HD"))
        #expect(result.contains("eject.fill"))
        #expect(result.contains("/Volumes/Backup") || result.contains("Eject Backup"))
        #expect(result.contains(#""eject""#))
        #expect(result.contains(#""last":"Empty Trash""#))
        #expect(result.contains(#""afterNo":1"#))
        #expect(result.contains("/usr/bin/osascript"))
        #expect(result.contains("empty the trash"))
    }

    @Test("tmutil parser maps percent and idle")
    func timeMachineParse() throws {
        let fixture = "BackupPhase = Copying;\nPercent = \"0.42\";\nBytes = 1024;\nRunning = 1;"
        let idle = "ClientID = \"com.apple.backupd\";\nPercent = \"-1\";\nRunning = 0;"
        let result = try eval(plugin: "time-machine.js", mock: """
            var statusConfig = null;
            var macotron = {
                plugin: () => ({}),
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                every: () => {},
                shell: { run: () => Promise.resolve({ stdout: \(String(reflecting: fixture)) }) }
            };
            """, extra: """
            JSON.stringify({
                running: parseTmutil(\(String(reflecting: fixture))),
                idle: parseTmutil(\(String(reflecting: idle))),
                title: statusConfig.title,
                icon: statusConfig.sfSymbol
            })
            """)
        #expect(result.contains(#""percent":42"#))
        #expect(result.contains(#""bytes":1024"#))
        #expect(result.contains(#""phase":"Copying""#))
        #expect(result.contains(#""running":false"#))
        #expect(result.contains(#""title":"TM 42%""#))
        #expect(result.contains("externaldrive.badge.timemachine"))
    }

    @Test("markdown converts headings, bold, and code")
    func markdownPreview() throws {
        let result = try eval(plugin: "markdown.js", mock: #"""
            var panel = null;
            var macotron = {
                plugin: () => ({}),
                clipboard: { text: () => "# Hi\\n\\nUse **bold** and `code`" },
                panel: { open: (opts) => { panel = opts; } },
                command: (name, desc, fn) => { macotron._cmd = fn; }
            };
            """#, extra: #"""
            macotron._cmd();
            JSON.stringify(panel)
            """#)
        #expect(result.contains("<h1>"))
        #expect(result.contains("Hi"))
        #expect(result.contains("<strong>bold</strong>"))
        #expect(result.contains("<code>code</code>"))
        #expect(result.contains(#""title":"Markdown""#))
    }
}
