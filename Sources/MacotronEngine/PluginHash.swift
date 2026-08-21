import CryptoKit
import Foundation

public enum PluginHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(source: String) -> String {
        sha256(Data(source.utf8))
    }

    public static func sha256(file url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return sha256(data)
    }
}
