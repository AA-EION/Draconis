import Foundation

/// The one place Draconis runs Windows programs. CrossOver bottles go through
/// CrossOver's own `cxstart`, so a launch behaves like double-clicking the exe
/// in CrossOver; Draconis Wine prefixes go through `WineEngine`.
public actor WineBackendManager {
    public static let shared = WineBackendManager()

    public enum BackendError: Error, LocalizedError {
        case crossOverNotInstalled
        case cxstartMissing
        case launchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .crossOverNotInstalled:
                return "CrossOver isn't installed. Get it from codeweavers.com, or use Draconis Wine."
            case .cxstartMissing:
                return "CrossOver is installed but its `cxstart` helper is missing."
            case .launchFailed(let s):
                return "Launch failed: \(s)"
            }
        }
    }

    /// Every CrossOver bottle and Draconis prefix, Northstar-ready first.
    public func allBottles() async -> [WineBottle] {
        let bottles = await CrossOverDetector.shared.bottles() + WineEngine.prefixes()
        return bottles.sorted {
            ($0.hasNorthstar ? 0 : 1, $0.name) < ($1.hasNorthstar ? 0 : 1, $1.name)
        }
    }

    public func isCrossOverAvailable() async -> Bool {
        await CrossOverDetector.shared.isInstalled()
    }

    // MARK: - Bottles

    public func createBottle(name: String, backend: WineBackend, description: String? = nil) async throws {
        switch backend {
        case .crossover:
            try await WineBottleCreator.shared.createBottle(name: name, description: description)
        case .draconis:
            _ = try await WineEngine.shared.createPrefix(named: name)
        }
    }

    public nonisolated func bottleExists(named name: String, backend: WineBackend) -> Bool {
        switch backend {
        case .crossover:
            return FileManager.default.fileExists(
                atPath: PathResolver.crossOverBottlesRoot.appendingPathComponent(name).path)
        case .draconis:
            return FileManager.default.fileExists(atPath: WineEngine.prefixURL(named: name).path)
        }
    }

    // MARK: - Running programs

    /// Run a Windows program (installer, CLI) and wait for its exit code.
    public func launchAndWait(
        executable: String,
        arguments: [String] = [],
        in bottle: WineBottle,
        workingDirectory: String? = nil,
        wineEnvironment: [String: String] = [:]
    ) async throws -> Int32 {
        let log = Self.prepareLog(for: bottle)
        switch bottle.backend {
        case .crossover:
            guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
                throw BackendError.cxstartMissing
            }
            let args = ["--bottle", bottle.name, "--wait", executable] + arguments
            Log.run("crossover.launch", "\(cxstart.path) \(args.joined(separator: " "))")
            return try await CleanSpawn.spawnAndWait(
                executable: cxstart.path,
                arguments: args,
                stdoutPath: log,
                currentDirectory: workingDirectory
            )
        case .draconis:
            return try await WineEngine.shared.run(
                [executable] + arguments,
                prefix: bottle.prefixURL,
                log: log,
                currentDirectory: workingDirectory,
                environment: wineEnvironment
            )
        }
    }

    /// Start a long-running Windows program (game, launcher) without waiting.
    /// Spawned clean (own session, no inherited fds, responsibility disclaimed):
    /// a Wine tree attributed to Draconis freezes when Draconis is in the background.
    @discardableResult
    public func spawn(
        executable: String,
        arguments: [String] = [],
        in bottle: WineBottle,
        workingDirectory: String? = nil,
        wineEnvironment: [String: String] = [:]
    ) async throws -> pid_t {
        let log = Self.prepareLog(for: bottle)
        switch bottle.backend {
        case .crossover:
            guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
                throw BackendError.cxstartMissing
            }
            let args = ["--bottle", bottle.name, executable] + arguments
            Log.run("crossover.launch", "\(cxstart.path) \(args.joined(separator: " "))")
            return try CleanSpawn.spawn(
                executable: cxstart.path,
                arguments: args,
                stdoutPath: log,
                currentDirectory: workingDirectory
            )
        case .draconis:
            return try await WineEngine.shared.spawn(
                [executable] + arguments,
                prefix: bottle.prefixURL,
                log: log,
                currentDirectory: workingDirectory,
                environment: wineEnvironment
            )
        }
    }

    /// Hand a URL (`link2ea://`, `steam://`) to whatever the bottle registered for it.
    public func open(url: String, in bottle: WineBottle, wineEnvironment: [String: String] = [:]) async throws {
        try await spawn(executable: "C:\\windows\\system32\\start.exe", arguments: [url], in: bottle,
                        wineEnvironment: wineEnvironment)
    }

    /// Stop every Wine process in the bottle.
    public func killAll(in bottle: WineBottle) async {
        switch bottle.backend {
        case .crossover:
            guard let wineserver = await CrossOverDetector.shared.wineserverBinary() else { return }
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = bottle.prefixURL.path
            _ = try? await CleanSpawn.spawnAndWait(executable: wineserver.path, arguments: ["-k"], environment: env)
        case .draconis:
            try? await WineEngine.shared.killAll(prefix: bottle.prefixURL)
        }
    }

    /// Write a registry value inside the bottle.
    public func setRegistry(
        key: String, value: String, type: String = "REG_SZ", data: String, in bottle: WineBottle
    ) async throws {
        let status = try await launchAndWait(
            executable: "reg",
            arguments: ["add", key, "/v", value, "/t", type, "/d", data, "/f"],
            in: bottle
        )
        if status != 0 { throw BackendError.launchFailed("reg add \(key)\\\(value) exited \(status)") }
    }

    private static func prepareLog(for bottle: WineBottle) -> String {
        let url = PathResolver.bottleLogFile(for: bottle)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return url.path
    }
}
