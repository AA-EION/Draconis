import DraconisCore
import Foundation

/// Starts helper tools and games. Games are detached (Draconis can quit
/// while they run) and get a clean environment.
public enum Spawner {
    public struct Failure: Error, LocalizedError {
        public var command: String
        public var status: Int32
        public var errorDescription: String? { "\(command) failed (exit \(status))." }
    }

    /// Variables an AppImage or Flatpak runtime sets for itself; a game
    /// started from Draconis must not inherit them.
    static let leakingVariables: Set<String> = [
        "LD_LIBRARY_PATH", "LD_PRELOAD", "PYTHONHOME", "PYTHONPATH", "APPDIR", "APPIMAGE",
        "ARGV0", "OWD", "QT_PLUGIN_PATH", "GST_PLUGIN_PATH", "GST_PLUGIN_SYSTEM_PATH",
        "GTK_PATH", "GIO_MODULE_DIR", "GDK_PIXBUF_MODULE_FILE", "XDG_DATA_DIRS_APPIMAGE",
        "WINEPREFIX", "WINEDLLOVERRIDES", "WINEDEBUG", "PROTONPATH", "GAMEID",
    ]

    /// Running as a Flatpak: host tools (Steam, umu-run, Proton, Wine) are
    /// reached through `flatpak-spawn --host`.
    public static let inFlatpak: Bool = {
        ProcessInfo.processInfo.environment["FLATPAK_ID"] != nil
            || FileManager.default.fileExists(atPath: "/.flatpak-info")
    }()

    /// Wrap a command so it runs on the host when sandboxed.
    static func hostCommand(_ executable: String, _ arguments: [String], _ environment: [String: String],
                            _ workingDirectory: URL?) -> (String, [String], [String: String]) {
        guard inFlatpak else { return (executable, arguments, cleanEnvironment(adding: environment)) }
        var args = ["--host", "--watch-bus"]
        if let workingDirectory { args.append("--directory=\(workingDirectory.path)") }
        args += environment.sorted { $0.key < $1.key }.map { "--env=\($0.key)=\($0.value)" }
        return ("/usr/bin/flatpak-spawn", args + [executable] + arguments, ProcessInfo.processInfo.environment)
    }

    public static func cleanEnvironment(adding extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !leakingVariables.contains($0.key) }
        env.merge(extra) { $1 }
        return env
    }

    /// Start without waiting. Output goes to `log` (appended).
    @discardableResult
    public static func launch(_ executable: String, _ arguments: [String],
                              environment: [String: String] = [:],
                              workingDirectory: URL? = nil,
                              log: URL? = nil) throws -> Process {
        let process = Process()
        let (exe, args, env) = hostCommand(executable, arguments, environment, workingDirectory)
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.environment = env
        if let workingDirectory, !inFlatpak { process.currentDirectoryURL = workingDirectory }
        process.standardInput = FileHandle.nullDevice
        if let log, let handle = appendHandle(log) {
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        Log.run("launch", ([executable] + arguments).joined(separator: " "))
        try process.run()
        return process
    }

    /// Run to completion; throws on a non-zero exit.
    public static func run(_ executable: String, _ arguments: [String],
                           environment: [String: String] = [:],
                           workingDirectory: URL? = nil,
                           log: URL? = nil) async throws {
        let status = try await status(executable, arguments, environment: environment,
                                      workingDirectory: workingDirectory, log: log)
        if status != 0 { throw Failure(command: ([executable] + arguments).joined(separator: " "), status: status) }
    }

    public static func status(_ executable: String, _ arguments: [String],
                              environment: [String: String] = [:],
                              workingDirectory: URL? = nil,
                              log: URL? = nil) async throws -> Int32 {
        let process = Process()
        return try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do {
                let (exe, args, env) = hostCommand(executable, arguments, environment, workingDirectory)
                process.executableURL = URL(fileURLWithPath: exe)
                process.arguments = args
                process.environment = env
                if let workingDirectory, !inFlatpak { process.currentDirectoryURL = workingDirectory }
                process.standardInput = FileHandle.nullDevice
                if let log, let handle = appendHandle(log) {
                    process.standardOutput = handle
                    process.standardError = handle
                } else {
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                }
                Log.run("run", ([executable] + arguments).joined(separator: " "))
                try process.run()
            } catch {
                process.terminationHandler = nil
                cont.resume(throwing: error)
            }
        }
    }

    /// Run and return stdout (small outputs only).
    public static func capture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func appendHandle(_ url: URL) -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }
}
