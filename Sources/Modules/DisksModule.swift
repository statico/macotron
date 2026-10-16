// DisksModule.swift — macotron.disks: mounted volumes and eject
import CQuickJS
import Foundation
import MacotronEngine

/// One row of the kernel's mount table, before Foundation adds names and
/// flags to it.
struct Mount {
    let path: String
    let device: String
    let fsType: String
    let flags: UInt32
    let total: Int
    let free: Int

    var visible: Bool { flags & UInt32(MNT_DONTBROWSE) == 0 }
    var local: Bool { flags & UInt32(MNT_LOCAL) != 0 }
}

enum Disks {
    static let keys: Set<URLResourceKey> = [
        .volumeLocalizedNameKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
    ]

    /// The volumes Finder shows. getmntinfo with MNT_NOWAIT answers from the
    /// kernel's cache, so a dead network share cannot hang the caller; only
    /// local volumes are asked for the resource values that would.
    static func list() -> [[String: Any]] {
        mounts().filter(\.visible).map { mount in
            let values = mount.local
                ? try? URL(fileURLWithPath: mount.path).resourceValues(forKeys: keys)
                : nil
            return entry(mount, values)
        }
    }

    static func mounts() -> [Mount] {
        var buf: UnsafeMutablePointer<statfs>?
        let count = Int(getmntinfo(&buf, MNT_NOWAIT))
        guard let buf else { return [] }
        return (0..<count).map { i in
            var s = buf[i]
            let bsize = Int(s.f_bsize)
            return Mount(
                path: cString(&s.f_mntonname),
                device: cString(&s.f_mntfromname),
                fsType: cString(&s.f_fstypename),
                flags: s.f_flags,
                total: Int(s.f_blocks) * bsize,
                free: Int(s.f_bavail) * bsize)
        }
    }

    /// `available` counts purgeable space (caches, local snapshots) as free,
    /// which is the figure Finder and About This Mac show; `free` is what the
    /// file system would hand out right now.
    static func entry(_ mount: Mount, _ values: URLResourceValues?) -> [String: Any] {
        let root = mount.flags & UInt32(MNT_ROOTFS) != 0
        let important = values?.volumeAvailableCapacityForImportantUsage.map(Int.init) ?? 0
        let name = values?.volumeLocalizedName
            ?? (root ? "/" : (mount.path as NSString).lastPathComponent)
        return [
            "name": name,
            "path": mount.path,
            "device": mount.device.hasPrefix("/dev/") ? String(mount.device.dropFirst(5)) : mount.device,
            "fsType": mount.fsType,
            "total": mount.total,
            "free": mount.free,
            "available": max(important, mount.free),
            "internal": values?.volumeIsInternal ?? false,
            "removable": values?.volumeIsRemovable ?? false,
            "ejectable": values?.volumeIsEjectable ?? false,
            "network": !mount.local,
            "readOnly": mount.flags & UInt32(MNT_RDONLY) != 0,
            "root": root,
        ]
    }

    private static func cString<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}

@MainActor
public final class DisksModule: NativeModule {
    public let name = "disks"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let disks = JS_NewObject(ctx)

        JSBridge.fn(ctx, disks, "list", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, Disks.list())
        }

        // FileManager unmounts on its own queue and calls back when the disk
        // is gone or refused, so there is no thread of ours to block.
        JSBridge.fn(ctx, disks, "eject", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let path = JSBridge.toString(ctx, argv[0]), !path.isEmpty else {
                return QJS_ThrowTypeError(ctx, "disks.eject requires a volume path")
            }
            let (promise, settle) = JSBridge.deferred(ctx, dryRun: ["ok": true])
            guard !Engine.isDryRun(ctx) else { return promise }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            FileManager.default.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk]) { error in
                let message = error?.localizedDescription
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        settle(.value(message.map { ["ok": false, "error": $0] } ?? ["ok": true]))
                    }
                }
            }
            return promise
        }

        JS_SetPropertyStr(ctx, macotron, "disks", disks)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
