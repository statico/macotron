// ConfigBackup.swift — Keep a copy of a plugin file before the host removes it
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "backup")

@MainActor
public final class ConfigBackup {
    public let configDir: URL
    public let backupsDir: URL

    public init(configDir: URL) {
        self.configDir = configDir
        self.backupsDir = configDir.appending(path: "backups")
    }

    /// Copy one file into `backups/` under a timestamped name, so a delete is
    /// recoverable. Returns the copy, or nil if it could not be made — the
    /// caller must treat nil as "do not delete yet".
    @discardableResult
    public func backup(file: URL) -> URL? {
        // Sorts lexically and is safe in a filename (no colons).
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        let stamp = formatter.string(from: Date())
        let dest = backupsDir.appending(path: "\(stamp)-\(file.lastPathComponent)")
        do {
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: file, to: dest)
            return dest
        } catch {
            logger.error("Failed to back up \(file.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}
