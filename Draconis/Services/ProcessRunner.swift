import Foundation

/// Thin wrapper around `Process` with async/throws ergonomics.
/// All wine / CrossOver / steamcmd invocations go through here so we have
/// one place to add logging, sandbox escape hatches, env var massaging, etc.
public actor ProcessRunner {
    public static let shared = ProcessRunner()

    public struct Result: Sendable {
        public let terminationStatus: Int32
        public let stdout: String
        public let stderr: String
        public var ok: Bool { terminationStatus == 0 }
    }

    public enum RunError: Error, LocalizedError {
        case launchFailed(String)
        case nonZeroExit(Int32, String)

        public var errorDescription: String? {
            switch self {
            case .launchFailed(let s):      return "Could not launch process: \(s)"
            case .nonZeroExit(let c, let s): return "Process exited \(c): \(s)"
            }
        }
    }

    /// Run a binary to completion and capture all output.
    public func capture(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            // Merge with current env so PATH etc. stays sane.
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            process.environment = env
        }
        process.currentDirectoryURL = currentDirectory

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        // The handler must be installed before run(): a process that exits
        // immediately would otherwise finish before anyone is listening.
        // A buffered stream (instead of a continuation) lets us start
        // draining the pipes before awaiting exit, so a chatty child can't
        // fill the pipe buffer and deadlock.
        let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw RunError.launchFailed(error.localizedDescription)
        }

        // Drain pipes off the main actor.
        async let outData: Data = readAll(outPipe.fileHandleForReading)
        async let errData: Data = readAll(errPipe.fileHandleForReading)

        var status: Int32 = -1
        for await code in exitStream { status = code }

        let stdout = String(data: await outData, encoding: .utf8) ?? ""
        let stderr = String(data: await errData, encoding: .utf8) ?? ""

        return Result(
            terminationStatus: status,
            stdout: stdout,
            stderr: stderr
        )
    }

    /// Fire-and-monitor: returns a `Process` so callers can stream output or
    /// terminate it. Used when launching the game so the launcher can keep a
    /// "Running…" indicator alive.
    ///
    /// stdin/stdout/stderr are explicitly redirected to a log file (or
    /// `/dev/null`) instead of letting them inherit Draconis's GUI-app fds.
    /// Wine processes sometimes block or silently fail when their stdio
    /// points at a non-TTY non-pipe fd inherited from a GUI parent, which
    /// presents as "wine processes spawn but no window ever appears."
    public nonisolated func detached(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        logFile: URL? = nil
    ) throws -> Process {
        let process = makeDetached(
            executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            logFile: logFile
        )
        try process.run()
        return process
    }

    public nonisolated func detachedAndWait(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        logFile: URL? = nil
    ) async throws -> Int32 {
        let process = makeDetached(
            executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            logFile: logFile
        )
        return try await Self.runUntilExit(process)
    }

    public static func runUntilExit(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            // Installed before run(): a fast exit must not beat the handler,
            // and a throwing run() must resume the continuation only once.
            process.terminationHandler = { finished in
                cont.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                cont.resume(throwing: error)
            }
        }
    }

    private nonisolated func makeDetached(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: URL?,
        logFile: URL?
    ) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            process.environment = env
        }
        process.currentDirectoryURL = currentDirectory

        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        if let logFile {
            try? FileManager.default.createDirectory(
                at: logFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                process.standardOutput = handle
                process.standardError = handle
            } else {
                process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
                process.standardError = FileHandle(forWritingAtPath: "/dev/null")
            }
        } else {
            process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        }

        return process
    }

    private func readAll(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }.value
    }
}
