//
//  HTTPLogMirror.swift
//  ENlink
//

import BetterBlueKit
import Foundation

/// Mirrors each HTTP log, already scrubbed by BetterBlueKit's redactor, as one
/// JSON line under `Library/Logs/` in the App Group container — one file per
/// process, so the app and the widget never append to the same file.
///
/// The SwiftData store sits at the container root, which `devicectl` cannot
/// copy from, and it also holds the account's password and PIN in plain text.
/// `Library/` can be copied, so `scripts/pull-phone-logs.sh` reads these files
/// off the phone without the credentials ever leaving it. They are the source
/// for Phase 2 fixtures and latency, and for counting widget refreshes in
/// Phase 7.
enum HTTPLogMirror {
    /// Past this size a file is rotated to `<name>.1`, replacing the previous one.
    static let maxBytes = 5_000_000

    private static let queue = DispatchQueue(label: "HTTPLogMirror")

    private struct Entry: Encodable {
        let source: String
        let log: HTTPLog
    }

    static func record(_ log: HTTPLog, from deviceType: DeviceType) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = try? encoder.encode(Entry(source: deviceType.rawValue, log: log)) else { return }
        let line = json + [0x0A]

        let file = directory().appending(path: "http-\(deviceType.rawValue.lowercased()).jsonl")
        let limit = maxBytes
        queue.async { JSONLineFile.append(line, to: file, maxBytes: limit) }
    }

    private static func directory() -> URL {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup
        ) {
            return group.appending(path: "Library/Logs", directoryHint: .isDirectory)
        }
        return URL.libraryDirectory.appending(path: "Logs", directoryHint: .isDirectory)
    }
}

/// Appends newline-terminated records to a file, rotating it once to `<name>.1`
/// when it would grow past `maxBytes`. Callers serialize access per file.
enum JSONLineFile {
    static func append(_ line: Data, to url: URL, maxBytes: Int) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > 0, size + line.count > maxBytes {
            let rotated = url.appendingPathExtension("1")
            try? fileManager.removeItem(at: rotated)
            try? fileManager.moveItem(at: url, to: rotated)
        }

        guard fileManager.fileExists(atPath: url.path) else {
            fileManager.createFile(atPath: url.path, contents: line)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
