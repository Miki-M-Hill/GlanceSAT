//
//  AppGroupAtomicJSONFile.swift
//  GlanceSATWidgets
//

import Darwin
import Foundation

enum AppGroupAtomicJSONFile {
    static func readArray<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tmpURL = directory.appendingPathComponent("\(url.lastPathComponent).\(ProcessInfo.processInfo.globallyUniqueString).tmp")
        let data = try JSONEncoder().encode(value)
        try data.write(to: tmpURL, options: .atomic)

        let destinationPath = url.path
        let tmpPath = tmpURL.path
        let status = tmpPath.withCString { tmpCString in
            destinationPath.withCString { destCString in
                rename(tmpCString, destCString)
            }
        }
        if status != 0 {
            try? FileManager.default.removeItem(at: tmpURL)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "rename failed for \(url.lastPathComponent)",
            ])
        }
    }

    static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
