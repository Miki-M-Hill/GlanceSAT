//
//  AppGroupFileLock.swift
//  GlanceSATWidgets
//

import Darwin
import Foundation

/// Cross-process advisory lock for App Group JSON / UserDefaults RMW (host + widget extension).
enum AppGroupFileLock {
    private static let appGroupID = GlanceSATWidgetConstants.appGroupIdentifier
    private static let lockFilename = ".widget_app_group.lock"

    static var lockFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(lockFilename, isDirectory: false)
    }

    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        guard let url = lockFileURL else {
            return try body()
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        }

        let fd = open(url.path, O_RDWR)
        guard fd >= 0 else {
            return try body()
        }

        defer {
            _ = flock(fd, LOCK_UN)
            _ = close(fd)
        }

        while flock(fd, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            break
        }

        return try body()
    }
}
