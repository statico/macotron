import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("HeicToJpeg")
struct HeicToJpegTests {
    @Test("converts each HEIC that has no JPEG yet and counts the rest")
    func converts() throws {
        let engine = try PluginHarness.load(plugin: "heic-to-jpeg.js", mock: #"""
            var run = null;
            var converts = [];
            var toasts = [];
            var logged = [];
            var macotron = {
                plugin: () => ({}),
                command: (title, subtitle, fn) => { run = fn; },
                fs: {
                    list: () => ["a.HEIC", "b.heic", "c.heif", "d.jpg"],
                    exists: (p) => p === "~/Downloads/b.jpg"
                },
                image: {
                    convert: (src, dest, opts) => {
                        converts.push({ src: src, dest: dest, format: opts.format, quality: opts.quality });
                        return Promise.resolve(src.endsWith("c.heif") ? { ok: false, error: "cannot read" } : { ok: true });
                    }
                },
                notify: { toast: (title, body, opts) => { toasts.push({ body: body, color: opts && opts.color }); } },
                log: (s) => { logged.push(s); }
            };
            """#, extra: "run();")
        let result = PluginHarness.run(engine, "JSON.stringify({ converts: converts, toasts: toasts, logged: logged })")
        #expect(result.contains(#"{"src":"~/Downloads/a.HEIC","dest":"~/Downloads/a.jpg","quality":1}"#))
        #expect(!result.contains("b.heic"))
        #expect(result.contains(#""body":"1 converted, 1 already existed, 1 failed","color":"warning""#))
        #expect(result.contains("c.heif: cannot read"))
    }
}
