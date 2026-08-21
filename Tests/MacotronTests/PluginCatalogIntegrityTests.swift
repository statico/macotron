import Foundation
import Testing
@testable import MacotronEngine
@testable import MacotronUI

@Suite("PluginHash")
struct PluginHashTests {
    @Test func sha256IsStable() {
        #expect(PluginHash.sha256(source: "hello") == PluginHash.sha256(source: "hello"))
        #expect(PluginHash.sha256(source: "hello") != PluginHash.sha256(source: "Hello"))
        #expect(PluginHash.sha256(source: "hello").count == 64)
    }
}

@Suite("PluginTrust")
@MainActor
struct PluginTrustTests {
    @Test func matchesApprovedHash() {
        let store = MemoryHashStore()
        PluginTrust.store = store
        defer { PluginTrust.store = KeychainHashStore() }
        PluginTrust.approve(filename: "demo.js", source: "ok")
        #expect(PluginTrust.matches(filename: "demo.js", source: "ok"))
        #expect(!PluginTrust.matches(filename: "demo.js", source: "changed"))
    }

    @Test func grandfathersEmptyLedger() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-trust-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "a".write(to: dir.appending(path: "a.js"), atomically: true, encoding: .utf8)

        let store = MemoryHashStore()
        PluginTrust.grandfatherIfEmpty(pluginsDir: dir, store: store)
        #expect(store.read(filename: "a.js") == PluginHash.sha256(source: "a"))
        store.write(filename: "a.js", hash: "old")
        PluginTrust.grandfatherIfEmpty(pluginsDir: dir, store: store)
        #expect(store.read(filename: "a.js") == "old")
    }
}

@Suite("PluginScan")
struct PluginScanTests {
    @Test func chunksOverlap() {
        let chunks = PluginScan.chunks(String(repeating: "a", count: 50), maxChars: 20, overlap: 5)
        #expect(chunks.count > 1)
        #expect(chunks[0].text.count == 20)
        #expect(chunks[1].text.hasPrefix(String(chunks[0].text.suffix(5))))
    }

    @Test func flagsEval() {
        #expect(PluginScan.staticFlags("eval(code)").contains("Uses eval()"))
        #expect(PluginScan.staticFlags("const x = 1").isEmpty)
    }

    @Test func anyPassFailureFailsReport() {
        let report = PluginScan.failed(
            anyPassFails: [
                [],
                [PluginScanFinding(pass: 2, message: "exfil")],
            ],
            staticFlags: []
        )
        #expect(!report.approved)
        #expect(report.needsOverride)
        #expect(report.findings.map(\.pass) == [2])
    }

    @Test func unavailableModelNeedsOverride() {
        let report = PluginScan.unavailableReport(reason: "Turn on Apple Intelligence in System Settings to get automated checks.")
        #expect(!report.modelAvailable)
        #expect(!report.approved)
        #expect(report.needsOverride)
        #expect(report.unavailableReason?.contains("Apple Intelligence") == true)
    }

    @Test func tokenChunksHonorBudget() {
        let chunks = PluginScan.chunks(
            String(repeating: "a", count: 50),
            maxTokens: 20,
            overlapTokens: 5,
            tokenCount: { $0.count }
        )
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= 20 })
    }
}

@Suite("PluginCatalog")
struct PluginCatalogTests {
    @Test func overwriteKinds() {
        #expect(PluginCatalog.overwriteKind(existingHash: nil, bundledHash: "a") == nil)
        #expect(PluginCatalog.overwriteKind(existingHash: "a", bundledHash: "a") == .unmodifiedStock)
        #expect(PluginCatalog.overwriteKind(existingHash: "b", bundledHash: "a") == .modified)
    }

    @Test func loadsFromJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-cat-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        macotron.plugin({ title: "Weather", description: "Sky", permissions: ["accessibility"] });
        """.write(to: dir.appending(path: "demo-weather.js"), atomically: true, encoding: .utf8)
        let json = dir.appending(path: "catalog.json")
        try """
        {"plugins":[{"filename":"demo-weather.js","kind":"stock","highlighted":true,"category":"Menu bar"}]}
        """.write(to: json, atomically: true, encoding: .utf8)
        let plugins = PluginCatalog.load(jsonURL: json)
        #expect(plugins.count == 1)
        #expect(plugins[0].title == "Weather")
        #expect(plugins[0].highlighted)
        #expect(plugins[0].isStock)
        #expect(plugins[0].permissions == [.accessibility])
    }
}

@Suite("WizardStep")
struct WizardStepTests {
    @Test func catalogIsBeforePermissions() {
        let steps = WizardStep.allCases
        let catalog = steps.firstIndex(of: .catalog)!
        let folder = steps.firstIndex(of: .folder)!
        let permissions = steps.firstIndex(of: .permissions)!
        #expect(folder < catalog)
        #expect(catalog < permissions)
    }
}
