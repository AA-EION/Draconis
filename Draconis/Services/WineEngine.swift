import CryptoKit
import Foundation

/// Draconis's own Wine, for players without CrossOver: Wine built from
/// CodeWeavers' published CrossOver sources, plus DXMT (Direct3D 11 → Metal).
/// Both are open source (LGPL / MIT) and downloaded on demand, checksum-pinned.
///
/// Every prefix lives under `Draconis/Prefixes/<name>` and every command gets
/// an explicit WINEPREFIX — nothing ever touches the global `~/.wine`.
public actor WineEngine {
    public static let shared = WineEngine()

    struct Artifact: Sendable {
        let url: URL
        let sha256: String
    }

    static let wineArtifact = Artifact(
        url: URL(string: "https://github.com/yaagl/anime-game-wine/releases/download/wine-crossover-11.0-1/wine-crossover-11.0-1-osx64.tar.xz")!,
        sha256: "6695910d290505712177c48db1963d9028a2f73efe3199d1cb94d7e15cf645d7"
    )
    static let dxmtArtifact = Artifact(
        url: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!,
        sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
    )
    public static let version = "wine-crossover-11.0-1+dxmt-0.80"

    /// DXMT's Metal code needs macOS 15.
    public static let minimumMacOS = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)

    public enum EngineError: Error, LocalizedError {
        case unsupportedMacOS
        case rosettaMissing
        case checksumMismatch(String)
        case commandFailed(String, Int32)
        case notInstalled
        case invalidPrefix(String)
        case prefixExists(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedMacOS:
                return "Draconis Wine needs macOS 15 or newer."
            case .rosettaMissing:
                return "Draconis Wine needs Rosetta 2. Install it from the setup wizard or run `softwareupdate --install-rosetta`."
            case .checksumMismatch(let file):
                return "\(file) didn't match its expected checksum; the download was discarded."
            case .commandFailed(let what, let code):
                return "\(what) failed (exit \(code)). See ~/Library/Application Support/Draconis/Logs."
            case .notInstalled:
                return "Draconis Wine isn't installed yet."
            case .invalidPrefix(let path):
                return "Refusing to use \(path) as a Wine prefix: it isn't inside Draconis's Prefixes folder."
            case .prefixExists(let name):
                return "A Draconis prefix named \"\(name)\" already exists."
            }
        }
    }

    // MARK: - Locations

    public static var root: URL {
        PathResolver.draconisSupport.appendingPathComponent("Engine", isDirectory: true)
    }
    public static var wineRoot: URL { root.appendingPathComponent("wine", isDirectory: true) }
    public static var wineBinary: URL { wineRoot.appendingPathComponent("bin/wine") }
    public static var wineserverBinary: URL { wineRoot.appendingPathComponent("bin/wineserver") }
    public static var prefixesRoot: URL {
        PathResolver.draconisSupport.appendingPathComponent("Prefixes", isDirectory: true)
    }
    private static var markerURL: URL { root.appendingPathComponent("engine-version") }

    public nonisolated static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: wineBinary.path)
            && (try? String(contentsOf: markerURL, encoding: .utf8)) == version
    }

    public nonisolated static var isSupportedMacOS: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumMacOS)
    }

    public nonisolated static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    /// The engine is x86_64; Apple Silicon runs it through Rosetta 2.
    public nonisolated static func isRosettaAvailable() async -> Bool {
        guard isAppleSilicon else { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        p.arguments = ["-x86_64", "/usr/bin/true"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return (try? await ProcessRunner.runUntilExit(p)) == 0
    }

    // MARK: - Install

    public typealias ProgressHandler = NorthstarUpdater.ProgressHandler

    public func install(progress: ProgressHandler? = nil) async throws {
        guard Self.isSupportedMacOS else { throw EngineError.unsupportedMacOS }
        guard await Self.isRosettaAvailable() else { throw EngineError.rosettaMissing }

        let fm = FileManager.default
        let staging = Self.root.deletingLastPathComponent()
            .appendingPathComponent("Engine.staging", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let wineArchive = try await fetch(Self.wineArtifact, label: "Wine", progress: progress)
        let dxmtArchive = try await fetch(Self.dxmtArtifact, label: "DXMT", progress: progress)

        progress?(.init(phase: .extracting, fraction: -1, detail: "Unpacking Wine…"))
        try await run("/usr/bin/tar", ["-xJf", wineArchive.path, "-C", staging.path], what: "Unpacking Wine")
        let dxmtDir = staging.appendingPathComponent("dxmt", isDirectory: true)
        try fm.createDirectory(at: dxmtDir, withIntermediateDirectories: true)
        try await run("/usr/bin/tar", ["-xzf", dxmtArchive.path, "-C", dxmtDir.path, "--strip-components=1"],
                      what: "Unpacking DXMT")

        // DXMT "builtin": replaces Wine's own d3d11/dxgi/d3d10core, no DLL overrides needed.
        let wine = staging.appendingPathComponent("wine", isDirectory: true)
        let lib = wine.appendingPathComponent("lib/wine", isDirectory: true)
        let copies: [(String, [String])] = [
            ("x86_64-windows", ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]),
            ("i386-windows", ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]),
            ("x86_64-unix", ["winemetal.so"]),
        ]
        for (arch, files) in copies {
            for file in files {
                let dest = lib.appendingPathComponent(arch).appendingPathComponent(file)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: dxmtDir.appendingPathComponent(arch).appendingPathComponent(file), to: dest)
            }
        }
        try await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", wine.path], what: "Clearing quarantine",
                      allowFailure: true)

        try? fm.removeItem(at: Self.root)
        try fm.createDirectory(at: Self.root, withIntermediateDirectories: true)
        try fm.moveItem(at: wine, to: Self.wineRoot)
        try Self.version.write(to: Self.markerURL, atomically: true, encoding: .utf8)
        try? fm.removeItem(at: wineArchive)
        try? fm.removeItem(at: dxmtArchive)
        progress?(.init(phase: .done, fraction: 1, detail: "Draconis Wine ready"))
        Log.ok("engine", "Installed \(Self.version)")
    }

    private func fetch(_ artifact: Artifact, label: String, progress: ProgressHandler?) async throws -> URL {
        let dest = PathResolver.downloadsCache.appendingPathComponent(artifact.url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path),
           (try? Self.sha256(of: dest)) == artifact.sha256 {
            return dest
        }
        Log.info("engine", "Downloading \(artifact.url.absoluteString)")
        let tmp = try await DownloadCoordinator.download(from: artifact.url) { p in
            progress?(.init(phase: .downloading, fraction: p.fraction, detail: "\(label): \(p.detail)"))
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        guard try Self.sha256(of: dest) == artifact.sha256 else {
            try? FileManager.default.removeItem(at: dest)
            throw EngineError.checksumMismatch(artifact.url.lastPathComponent)
        }
        return dest
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Prefixes

    public nonisolated static func prefixURL(named name: String) -> URL {
        prefixesRoot.appendingPathComponent(name, isDirectory: true)
    }

    /// Every path handed to Wine must sit inside our Prefixes folder.
    nonisolated static func validated(_ prefix: URL) throws -> URL {
        let root = prefixesRoot.standardizedFileURL.path + "/"
        let path = prefix.standardizedFileURL.path
        guard path.hasPrefix(root), path.count > root.count else {
            throw EngineError.invalidPrefix(path)
        }
        return prefix
    }

    /// Environment for any Wine command against `prefix`. Built from scratch
    /// rather than inherited so a user's WINEPREFIX can never leak in.
    /// Extra environment for Steam: builtin bcrypt/ncrypt for Chromium's
    /// BoringSSL, no overlay (it deadlocks DXMT games).
    /// Steam also starts the EA app, so it gets that app's settings too.
    public static let steamEnvironment = eaAppEnvironment.merging([
        "WINEDLLOVERRIDES": "winemenubuilder.exe=d;bcrypt,ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d",
    ]) { $1 }
    /// The EA app's Chromium (Qt WebEngine) draws nothing on the GPU path here.
    public static let eaAppEnvironment = [
        "QTWEBENGINE_CHROMIUM_FLAGS": "--disable-gpu",
        "QTWEBENGINE_DISABLE_SANDBOX": "1",
    ]

    public nonisolated static func environment(prefix: URL, extra: [String: String] = [:]) throws -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var env: [String: String] = [
            "WINEPREFIX": try validated(prefix).path,
            "WINEDEBUG": "fixme-all",
            "WINEMSYNC": "1",
            "WINEESYNC": "0",
            "ROSETTA_ADVERTISE_AVX": "1",
            // No Launchpad / Dock shortcuts for apps installed into the prefix.
            "WINEDLLOVERRIDES": "winemenubuilder.exe=d",
            "PATH": wineRoot.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL"] {
            if let value = inherited[key] { env[key] = value }
        }
        env.merge(extra) { $1 }
        return env
    }

    public func createPrefix(named name: String) async throws -> URL {
        guard Self.isInstalled else { throw EngineError.notInstalled }
        let prefix = try Self.validated(Self.prefixURL(named: name))
        if FileManager.default.fileExists(atPath: prefix.path) {
            // No kernel32: an earlier creation failed (e.g. C: mapped to a mounted volume).
            let kernel32 = PathResolver.driveC(in: prefix).appendingPathComponent("windows/system32/kernel32.dll")
            guard !FileManager.default.fileExists(atPath: kernel32.path) else {
                throw EngineError.prefixExists(name)
            }
            try FileManager.default.removeItem(at: prefix)
        }
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try Self.createDriveLinks(in: prefix)
        let log = PathResolver.launchLogs.appendingPathComponent("prefix-\(name).log").path

        do {
            try await check(["wineboot", "-u"], prefix: prefix, log: log, what: "Creating the Wine prefix")
            try await check(["winecfg", "-v", "win10"], prefix: prefix, log: log, what: "Setting Windows 10")
            try await check(["reg", "add", "HKCU\\Software\\Wine\\Mac Driver", "/v", "RetinaMode", "/t", "REG_SZ",
                             "/d", "n", "/f"], prefix: prefix, log: log, what: "Writing display settings")
            try await wineserverWait(prefix: prefix)
        } catch {
            // A half-made prefix would be reused (and stay broken) on the next try.
            try? await killAll(prefix: prefix)
            try? FileManager.default.removeItem(at: prefix)
            throw error
        }
        Log.ok("engine", "Created prefix \(prefix.path)")
        return prefix
    }

    /// Wine assigns drive letters to mounted volumes as it boots; on a fresh
    /// prefix C: can go to whatever is mounted (e.g. the Draconis DMG) before
    /// Wine links it to drive_c. Link C: and Z: first.
    static func createDriveLinks(in prefix: URL) throws {
        let fm = FileManager.default
        let dosdevices = prefix.appendingPathComponent("dosdevices", isDirectory: true)
        try fm.createDirectory(at: PathResolver.driveC(in: prefix), withIntermediateDirectories: true)
        try fm.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        for (drive, target) in [("c:", "../drive_c"), ("z:", "/")] {
            let link = dosdevices.appendingPathComponent(drive)
            try? fm.removeItem(at: link)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target)
        }
    }

    /// Run a Windows program in `prefix` and return its exit code. Always via
    /// CleanSpawn so the Wine tree is its own responsible process.
    public func run(
        _ arguments: [String],
        prefix: URL,
        log: String? = nil,
        currentDirectory: String? = nil,
        environment extra: [String: String] = [:]
    ) async throws -> Int32 {
        guard Self.isInstalled else { throw EngineError.notInstalled }
        Log.run("engine", "wine \(arguments.joined(separator: " "))")
        return try await CleanSpawn.spawnAndWait(
            executable: Self.wineBinary.path,
            arguments: arguments,
            environment: try Self.environment(prefix: prefix, extra: extra),
            stdoutPath: log ?? "/dev/null",
            currentDirectory: currentDirectory
        )
    }

    private func check(_ arguments: [String], prefix: URL, log: String, what: String) async throws {
        let status = try await run(arguments, prefix: prefix, log: log)
        guard status == 0 else { throw EngineError.commandFailed(what, status) }
    }

    /// Start a long-running Windows program (game, launcher) and return its pid.
    public func spawn(
        _ arguments: [String],
        prefix: URL,
        log: String,
        currentDirectory: String? = nil,
        environment extra: [String: String] = [:]
    ) throws -> pid_t {
        guard Self.isInstalled else { throw EngineError.notInstalled }
        Log.run("engine", "wine \(arguments.joined(separator: " "))")
        return try CleanSpawn.spawn(
            executable: Self.wineBinary.path,
            arguments: arguments,
            environment: try Self.environment(prefix: prefix, extra: extra),
            stdoutPath: log,
            currentDirectory: currentDirectory
        )
    }

    public func wineserverWait(prefix: URL) async throws {
        _ = try await CleanSpawn.spawnAndWait(
            executable: Self.wineserverBinary.path,
            arguments: ["-w"],
            environment: try Self.environment(prefix: prefix)
        )
    }

    public func killAll(prefix: URL) async throws {
        _ = try await CleanSpawn.spawnAndWait(
            executable: Self.wineserverBinary.path,
            arguments: ["-k"],
            environment: try Self.environment(prefix: prefix)
        )
    }

    private func run(_ tool: String, _ args: [String], what: String, allowFailure: Bool = false) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let status = try await ProcessRunner.runUntilExit(p)
        if status != 0 && !allowFailure { throw EngineError.commandFailed(what, status) }
    }

    // MARK: - Discovery

    /// Prefixes created by Draconis. Same detection as CrossOver bottles.
    public nonisolated static func prefixes() -> [WineBottle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: prefixesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { url in
            let driveC = PathResolver.driveC(in: url)
            guard fm.fileExists(atPath: driveC.path) else { return nil }
            return CrossOverDetector.scanBottle(
                id: "draconis:" + url.lastPathComponent,
                name: url.lastPathComponent,
                backend: .draconis,
                prefixURL: url
            )
        }
    }
}
