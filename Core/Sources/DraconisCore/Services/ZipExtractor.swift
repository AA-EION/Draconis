import Foundation
import ZIPFoundation

/// Zip extraction that overwrites existing files (a Northstar update lands on
/// top of the previous one) and refuses entries that escape the destination.
public enum ZipExtractor {
    public enum ExtractError: Error, LocalizedError {
        case unreadable(String)
        case unsafeEntry(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let s):  return "Couldn't open the archive: \(s)"
            case .unsafeEntry(let s): return "Archive entry points outside the target folder: \(s)"
            }
        }
    }

    /// `stripping`: a top-level folder to drop from every entry (Thunderstore
    /// wraps Northstar in `Northstar/`); entries outside it are skipped.
    public static func extract(_ zip: URL, to destination: URL, stripping prefix: String? = nil) throws {
        let archive: Archive
        do {
            archive = try Archive(url: zip, accessMode: .read)
        } catch {
            throw ExtractError.unreadable(error.localizedDescription)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = destination.standardizedFileURL.path

        for entry in archive {
            var relative = entry.path.replacingOccurrences(of: "\\", with: "/")
            if let prefix {
                guard relative.hasPrefix(prefix + "/") else { continue }
                relative.removeFirst(prefix.count + 1)
                if relative.isEmpty { continue }
            }
            let target = destination.appendingPathComponent(relative).standardizedFileURL
            guard target.path == root || target.path.hasPrefix(root + "/") else {
                throw ExtractError.unsafeEntry(entry.path)
            }
            switch entry.type {
            case .directory:
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            case .file:
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                _ = try archive.extract(entry, to: target, skipCRC32: false)
            case .symlink:
                continue
            }
        }
    }

    /// One file from the archive, or nil if it isn't there.
    public static func read(_ path: String, in zip: URL) -> Data? {
        guard let archive = try? Archive(url: zip, accessMode: .read),
              let entry = archive[path] else { return nil }
        var data = Data()
        _ = try? archive.extract(entry, skipCRC32: false) { data.append($0) }
        return data
    }
}
