// ConfigBackup.swift — Compress & backup ~/Library/Application Support/Macotron/ before changes
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "backup")

@MainActor
public final class ConfigBackup {
    public let configDir: URL
    public let backupsDir: URL

    private let maxBackups = 100
    private let maxAgeDays = 30

    public init(configDir: URL) {
        self.configDir = configDir
        self.backupsDir = configDir.appending(path: "backups")
    }

    /// Create a compressed backup of the entire config directory (excluding backups/ itself)
    /// Returns the path to the backup file, or nil on failure.
    @discardableResult
    public func createBackup() -> URL? {
        do {
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create backups dir: \(error)")
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "\(timestamp).tar.gz"
        let backupPath = backupsDir.appending(path: backupName)

        // Use tar to create compressed backup, excluding backups/ and logs/
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "czf", backupPath.path(),
            "--exclude", "backups",
            "--exclude", "logs",
            "-C", configDir.deletingLastPathComponent().path(),
            configDir.lastPathComponent
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logger.info("Created backup: \(backupName)")
                pruneOldBackups()
                return backupPath
            } else {
                logger.error("tar exited with status \(process.terminationStatus)")
                return nil
            }
        } catch {
            logger.error("Failed to create backup: \(error)")
            return nil
        }
    }

    /// Restore from a backup file
    public func restore(from backupName: String) -> Bool {
        let backupPath = backupsDir.appending(path: backupName)
        guard FileManager.default.fileExists(atPath: backupPath.path()) else {
            logger.error("Backup not found: \(backupName)")
            return false
        }

        // Remove current config (except backups/)
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil) {
            for item in contents {
                if item.lastPathComponent != "backups" {
                    try? fm.removeItem(at: item)
                }
            }
        }

        // Extract backup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "xzf", backupPath.path(),
            "-C", configDir.deletingLastPathComponent().path()
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logger.info("Restored from backup: \(backupName)")
                return true
            }
        } catch {
            logger.error("Failed to restore backup: \(error)")
        }
        return false
    }

    /// List available backups (newest first)
    public func listBackups() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "gz" }
            .map { $0.lastPathComponent }
            .sorted()
            .reversed()
            .map { String($0) }
    }

    /// Remove backups older than maxAgeDays or beyond maxBackups count
    private func pruneOldBackups() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let backups = contents
            .filter { $0.pathExtension == "gz" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        // Prune by count
        if backups.count > maxBackups {
            for backup in backups.dropFirst(maxBackups) {
                try? fm.removeItem(at: backup)
                logger.info("Pruned old backup: \(backup.lastPathComponent)")
            }
        }

        // Prune by age
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)
        for backup in backups {
            if let attrs = try? fm.attributesOfItem(atPath: backup.path()),
               let created = attrs[.creationDate] as? Date,
               created < cutoff {
                try? fm.removeItem(at: backup)
                logger.info("Pruned expired backup: \(backup.lastPathComponent)")
            }
        }
    }
}
