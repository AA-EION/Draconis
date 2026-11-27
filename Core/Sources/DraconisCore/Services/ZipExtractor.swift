import Foundation
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

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
        #if canImport(ZIPFoundation)
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
        #else
        // bsdtar refuses absolute and `..` paths unless told otherwise.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var args = ["-xf", zip.path, "-C", destination.path]
        if let prefix { args += ["--strip-components=1", prefix + "/"] }
        let status = try windowsTar(args, output: nil)
        if status != 0 { throw ExtractError.unreadable("tar exited \(status)") }
        #endif
    }

    #if !canImport(ZIPFoundation)
    static func windowsTar(_ arguments: [String], output: FileHandle?) throws -> Int32 {
        let process = Process()
        let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#
        process.executableURL = URL(fileURLWithPath: systemRoot).appendingPathComponent("System32/tar.exe")
        process.arguments = arguments
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
    #endif

    /// One file from the archive, or nil if it isn't there.
    public static func read(_ path: String, in zip: URL) -> Data? {
        #if !canImport(ZIPFoundation)
        let pipe = Pipe()
        guard (try? windowsTar(["-xOf", zip.path, path], output: pipe.fileHandleForWriting)) == 0 else { return nil }
        try? pipe.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
        #else
        guard let archive = try? Archive(url: zip, accessMode: .read),
              let entry = archive[path] else { return nil }
        var data = Data()
        _ = try? archive.extract(entry, skipCRC32: false) { data.append($0) }
        return data
        #endif
    }
}
