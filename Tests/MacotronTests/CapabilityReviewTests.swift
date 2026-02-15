// CapabilityReviewTests.swift — Tests for static analysis security review
import Testing
@testable import MacotronEngine

@MainActor
@Suite("CapabilityReview Tests")
struct CapabilityReviewTests {

    // MARK: - Tier Classification

    @Test("Safe code returns .safe tier")
    func testSafeTier() {
        let js = """
            const wins = macotron.window.getAll();
            const focused = macotron.window.focused();
            const text = macotron.clipboard.text();
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .safe)
    }

    @Test("Read-only system APIs return .safe tier")
    func testSafeTierSystemAPIs() {
        let js = """
            const temp = macotron.system.cpuTemp();
            const mem = macotron.system.memory();
            const bat = macotron.system.battery();
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .safe)
    }

    @Test("Moderate code (window.move) returns .moderate tier")
    func testModerateTierWindowMove() {
        let js = """
            macotron.window.move(win, { x: 100, y: 200 });
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .moderate)
    }

    @Test("Moderate code (keyboard.on) returns .moderate tier")
    func testModerateTierKeyboard() {
        let js = """
            macotron.keyboard.on("cmd+shift+t", function() {});
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .moderate)
    }

    @Test("Moderate code (notify.show) returns .moderate tier")
    func testModerateTierNotify() {
        let js = """
            macotron.notify.show("Hello!");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .moderate)
    }

    @Test("Moderate code (clipboard.set) returns .moderate tier")
    func testModerateTierClipboardSet() {
        let js = """
            macotron.clipboard.set("new value");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .moderate)
    }

    @Test("Dangerous code (shell.run) returns .dangerous tier")
    func testDangerousTierShell() {
        let js = """
            macotron.shell.run("rm -rf /tmp/test");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .dangerous)
    }

    @Test("Dangerous code (fs.write) returns .dangerous tier")
    func testDangerousTierFsWrite() {
        let js = """
            macotron.fs.write("/tmp/test.txt", "content");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .dangerous)
    }

    @Test("Dangerous code (fs.delete) returns .dangerous tier")
    func testDangerousTierFsDelete() {
        let js = """
            macotron.fs.delete("/tmp/test.txt");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .dangerous)
    }

    @Test("Dangerous code (http.post) returns .dangerous tier")
    func testDangerousTierHttpPost() {
        let js = """
            macotron.http.post("https://example.com/api", { data: "stuff" });
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .dangerous)
    }

    @Test("Dangerous code (keychain.set) returns .dangerous tier")
    func testDangerousTierKeychainSet() {
        let js = """
            macotron.keychain.set("api-key", "secret");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .dangerous)
    }

    @Test("Dangerous code (url.open) returns .dangerous tier")
    func testDangerousTierUrlOpen() {
        let js = """
            macotron.url.open("https://malicious.example.com");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .dangerous)
    }

    // MARK: - Multiple APIs Take Highest Tier

    @Test("Multiple APIs take the highest tier")
    func testHighestTier() {
        let js = """
            const wins = macotron.window.getAll();
            macotron.window.move(wins[0], { x: 0, y: 0 });
            macotron.shell.run("echo hello");
        """
        let manifest = CapabilityReview.review(js)
        // safe + moderate + dangerous = dangerous
        #expect(manifest.tier == .dangerous)
    }

    @Test("Safe + moderate = moderate")
    func testSafePlusModerate() {
        let js = """
            const focused = macotron.window.focused();
            macotron.notify.show("Moving window");
            macotron.window.move(focused, { x: 0, y: 0 });
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .moderate)
    }

    @Test("No APIs returns .safe tier")
    func testNoAPIs() {
        let js = """
            var x = 1 + 2;
            console.log(x);
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.tier == .safe)
    }

    // MARK: - canAutoFix

    @Test("canAutoFix returns true for safe code")
    func testCanAutoFixSafe() {
        let js = """
            const wins = macotron.window.getAll();
            console.log(wins);
        """
        #expect(CapabilityReview.canAutoFix(source: js) == true)
    }

    @Test("canAutoFix returns true for moderate code")
    func testCanAutoFixModerate() {
        let js = """
            macotron.window.move(win, { x: 0, y: 0 });
            macotron.notify.show("Done");
        """
        #expect(CapabilityReview.canAutoFix(source: js) == true)
    }

    @Test("canAutoFix returns false for dangerous code (shell.run)")
    func testCanAutoFixDangerousShell() {
        let js = """
            macotron.shell.run("rm -rf /");
        """
        #expect(CapabilityReview.canAutoFix(source: js) == false)
    }

    @Test("canAutoFix returns false for dangerous code (fs.write)")
    func testCanAutoFixDangerousFsWrite() {
        let js = """
            macotron.fs.write("/etc/passwd", "hacked");
        """
        #expect(CapabilityReview.canAutoFix(source: js) == false)
    }

    @Test("canAutoFix returns false for dangerous code (fs.delete)")
    func testCanAutoFixDangerousFsDelete() {
        let js = """
            macotron.fs.delete("/important/file");
        """
        #expect(CapabilityReview.canAutoFix(source: js) == false)
    }

    @Test("canAutoFix returns false for dangerous code (http.post)")
    func testCanAutoFixDangerousHttpPost() {
        let js = """
            macotron.http.post("https://evil.com", {});
        """
        #expect(CapabilityReview.canAutoFix(source: js) == false)
    }

    @Test("canAutoFix returns false for dangerous code (keychain.set)")
    func testCanAutoFixDangerousKeychainSet() {
        let js = """
            macotron.keychain.set("key", "value");
        """
        #expect(CapabilityReview.canAutoFix(source: js) == false)
    }

    @Test("canAutoFix returns false when no-autofix pragma is present")
    func testCanAutoFixPragma() {
        let js = """
            // macotron:no-autofix
            const wins = macotron.window.getAll();
        """
        #expect(CapabilityReview.canAutoFix(source: js) == false)
    }

    @Test("canAutoFix returns false when no-autofix pragma is present even for safe code")
    func testCanAutoFixPragmaSafe() {
        let js = """
            // macotron:no-autofix
            var x = 1;
        """
        #expect(CapabilityReview.canAutoFix(source: js) == false)
    }

    @Test("canAutoFix returns true when code has no dangerous patterns and no pragma")
    func testCanAutoFixCleanCode() {
        let js = """
            var x = 1 + 2;
            console.log(x);
        """
        #expect(CapabilityReview.canAutoFix(source: js) == true)
    }

    // MARK: - apisUsed Extraction

    @Test("apisUsed extracts all API calls")
    func testApisUsed() {
        let js = """
            macotron.window.getAll();
            macotron.window.focused();
            macotron.clipboard.text();
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.apisUsed.contains("window.getAll"))
        #expect(manifest.apisUsed.contains("window.focused"))
        #expect(manifest.apisUsed.contains("clipboard.text"))
        #expect(manifest.apisUsed.count == 3)
    }

    @Test("apisUsed deduplicates repeated calls")
    func testApisUsedDedup() {
        let js = """
            macotron.window.getAll();
            macotron.window.getAll();
            macotron.window.getAll();
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.apisUsed.count == 1)
        #expect(manifest.apisUsed.contains("window.getAll"))
    }

    @Test("apisUsed is empty for code with no macotron API calls")
    func testApisUsedEmpty() {
        let js = "var x = 1 + 2;"
        let manifest = CapabilityReview.review(js)
        #expect(manifest.apisUsed.isEmpty)
    }

    // MARK: - shellCommands Extraction

    @Test("shellCommands extracts commands from shell.run calls")
    func testShellCommands() {
        let js = """
            macotron.shell.run("echo hello");
            macotron.shell.run("ls -la");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.shellCommands.contains("echo hello"))
        #expect(manifest.shellCommands.contains("ls -la"))
    }

    @Test("shellCommands is empty when no shell.run calls")
    func testShellCommandsEmpty() {
        let js = "macotron.window.getAll();"
        let manifest = CapabilityReview.review(js)
        #expect(manifest.shellCommands.isEmpty)
    }

    // MARK: - networkTargets Extraction

    @Test("networkTargets extracts URLs from http calls")
    func testNetworkTargets() {
        let js = """
            macotron.http.post("https://api.example.com/data", {});
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.networkTargets.contains("https://api.example.com/data"))
    }

    @Test("networkTargets extracts from multiple http methods")
    func testNetworkTargetsMultiple() {
        let js = """
            macotron.http.get("https://example.com/get");
            macotron.http.post("https://example.com/post", {});
            macotron.http.put("https://example.com/put", {});
            macotron.http.delete("https://example.com/delete");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.networkTargets.count == 4)
    }

    // MARK: - fileTargets Extraction

    @Test("fileTargets extracts paths from fs calls")
    func testFileTargets() {
        let js = """
            macotron.fs.write("/tmp/test.txt", "content");
            macotron.fs.delete("/tmp/old.txt");
        """
        let manifest = CapabilityReview.review(js)
        #expect(manifest.fileTargets.contains("/tmp/test.txt"))
        #expect(manifest.fileTargets.contains("/tmp/old.txt"))
    }

    @Test("fileTargets is empty when no fs write/delete calls")
    func testFileTargetsEmpty() {
        let js = "macotron.window.getAll();"
        let manifest = CapabilityReview.review(js)
        #expect(manifest.fileTargets.isEmpty)
    }

    // MARK: - CapabilityTier Comparable

    @Test("CapabilityTier comparison: safe < moderate")
    func testTierSafeLessThanModerate() {
        #expect(CapabilityTier.safe < CapabilityTier.moderate)
    }

    @Test("CapabilityTier comparison: moderate < dangerous")
    func testTierModerateLessThanDangerous() {
        #expect(CapabilityTier.moderate < CapabilityTier.dangerous)
    }

    @Test("CapabilityTier comparison: safe < dangerous")
    func testTierSafeLessThanDangerous() {
        #expect(CapabilityTier.safe < CapabilityTier.dangerous)
    }

    @Test("CapabilityTier equality")
    func testTierEquality() {
        #expect(CapabilityTier.safe == CapabilityTier.safe)
        #expect(CapabilityTier.moderate == CapabilityTier.moderate)
        #expect(CapabilityTier.dangerous == CapabilityTier.dangerous)
    }
}
