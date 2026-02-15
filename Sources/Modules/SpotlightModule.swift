// SpotlightModule.swift — macotron.spotlight: Spotlight metadata search
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class SpotlightModule: NativeModule {
    public let name = "spotlight"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let spotlightObj = JS_NewObject(ctx)

        // macotron.spotlight.search(query) → array of {path, name, kind}
        JS_SetPropertyStr(ctx, spotlightObj, "search",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let queryString = JSBridge.toString(ctx, argv[0]) ?? ""

            if queryString.isEmpty {
                return JSBridge.newArray(ctx, [])
            }

            let results = SpotlightModule.performSearch(queryString)
            return JSBridge.newArray(ctx, results.map { $0 as Any })
        }, "search", 1))

        JS_SetPropertyStr(ctx, macotronObj, "spotlight", spotlightObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    // MARK: - Spotlight Search

    /// Perform a synchronous Spotlight search using NSMetadataQuery.
    /// NSMetadataQuery is inherently async, so we use a brief RunLoop wait
    /// to gather results before returning.
    private static func performSearch(_ queryString: String) -> [[String: Any]] {
        var results: [[String: Any]] = []

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\(queryString)*")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        // Limit results by collecting only the first 50 after gathering

        var finished = false
        let observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: nil
        ) { _ in
            finished = true
        }

        query.start()

        // Wait up to 2 seconds for results to arrive
        let deadline = Date().addingTimeInterval(2.0)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        query.stop()
        NotificationCenter.default.removeObserver(observer)

        // Collect results (limit to 50)
        for item in query.results.prefix(50) {
            guard let metadataItem = item as? NSMetadataItem else { continue }
            let path = metadataItem.value(forAttribute: kMDItemPath as String) as? String ?? ""
            let name = metadataItem.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
            let kind = metadataItem.value(forAttribute: kMDItemContentType as String) as? String ?? ""

            results.append([
                "path": path,
                "name": name,
                "kind": kind
            ])
        }

        return results
    }
}
