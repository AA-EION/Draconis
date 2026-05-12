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

        do {
            try process.run()
        } catch {
            throw RunError.launchFailed(error.localizedDescription)
        }

        // Drain pipes off the main actor.
        async let outData: Data = readAll(outPipe.fileHandleForReading)
        async let errData: Data = readAll(errPipe.fileHandleForReading)

        process.waitUntilExit()

        let stdout = String(data: try await outData, encoding: .utf8) ?? ""
        let stderr = String(data: try await errData, encoding: .utf8) ?? ""

        return Result(
            terminationStatus: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    /// Fire-and-monitor: returns a `Process` so callers can stream output or
    /// terminate it. Used when launching the game so the launcher can keep a
    /// "Running…" indicator alive.
    public nonisolated func detached(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            process.environment = env
        }
        process.currentDirectoryURL = currentDirectory
        try process.run()
        return process
    }

    private func readAll(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }.value
    }
}
