import Foundation

/// Each Wine backend has its own runtime — we hand off to it instead of
/// invoking `wine` ourselves. That way Draconis behaves exactly like the
/// backend's own UI would: CrossOver's wine patches, Whisky's bundled DXVK,
/// Sikarugir's wrapper engines, etc.
public protocol WineBackendDriver: Sendable {
    var backend: WineBackend { get }
    func isAvailable() async -> Bool
    func bottles() async -> [WineBottle]
    func createBottle(named name: String) async throws -> WineBottle

    /// Run a Windows EXE inside the bottle using the backend's *own* runtime.
    ///
    /// - executable: Path to the exe — expressed as a POSIX path (e.g.
    ///   ".../drive_c/Program Files (x86)/.../NorthstarLauncher.exe"). Drivers
    ///   convert to whatever form their backend prefers (CrossOver's
    ///   `--cx-app` wants a Windows path; wine64 + WINEPREFIX accepts POSIX).
    /// - workingDirectory: POSIX path to chdir into before launch.
    @discardableResult
    func launch(
        executable: String,
        arguments: [String],
        in bottle: WineBottle,
        workingDirectory: String?
    ) async throws -> Process
}

public enum WineBackendError: Error, LocalizedError {
    case backendUnavailable(WineBackend)
    case bottleCreationUnsupported(WineBackend)
    case bottleCreationFailed(String)
    case runtimeMissing(WineBackend, String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .backendUnavailable(let b):
            return "\(b.displayName) is not installed."
        case .bottleCreationUnsupported(let b):
            return "Draconis can't create new bottles for \(b.displayName); use the app itself."
        case .bottleCreationFailed(let s):
            return "Bottle creation failed: \(s)"
        case .runtimeMissing(let b, let what):
            return "\(b.displayName) is installed but its \(what) is missing."
        case .launchFailed(let s):
            return "Launch failed: \(s)"
        }
    }
}

/// Coordinates all known Wine backends.
public actor WineBackendManager {
    public static let shared = WineBackendManager()

    private let drivers: [WineBackendDriver] = [
        CrossOverDriver(),
        GPTKDriver(),
        WhiskyDriver(),
        SikarugirDriver(),
        KegworksDriver(),
    ]

    /// All bottles from all backends, sorted Northstar-ready first.
    public func allBottles() async -> [WineBottle] {
        var collected: [WineBottle] = []
        for driver in drivers {
            if await driver.isAvailable() {
                collected.append(contentsOf: await driver.bottles())
            }
        }
        return collected.sorted {
            ($0.hasNorthstar ? 0 : 1, $0.name) < ($1.hasNorthstar ? 0 : 1, $1.name)
        }
    }

    public func availableBackends() async -> [WineBackend] {
        var out: [WineBackend] = []
        for d in drivers where await d.isAvailable() { out.append(d.backend) }
        return out
    }

    /// Preferred backend for new installs, in this order: CrossOver → GPTK →
    /// Sikarugir → Kegworks → Whisky.
    public func preferredBackend() async -> WineBackend? {
        let order: [WineBackend] = [.crossover, .gptk, .sikarugir, .kegworks, .whisky]
        let avail = Set(await availableBackends())
        return order.first { avail.contains($0) }
    }

    public func driver(for backend: WineBackend) -> WineBackendDriver? {
        drivers.first { $0.backend == backend }
    }
}

// MARK: - CrossOver driver

struct CrossOverDriver: WineBackendDriver {
    let backend: WineBackend = .crossover

    func isAvailable() async -> Bool { await CrossOverDetector.shared.isInstalled() }
    func bottles() async -> [WineBottle] { await CrossOverDetector.shared.bottles() }

    /// Use CrossOver's `cxbottle` to create a fresh win10_64 bottle, exactly
    /// like clicking "New Bottle" in CrossOver's UI.
    func createBottle(named name: String) async throws -> WineBottle {
        Log.info("crossover", "createBottle(\(name))")
        let _ = try await CrossOverBottleCreator.shared
            .createTitanfall2Bottle(named: name, template: "win10_64", installVia: nil)
        let url = PathResolver.crossOverBottlesRoot.appendingPathComponent(name)
        return WineBottle(
            id: "crossover:" + name,
            name: name,
            backend: .crossover,
            prefixURL: url,
            wineBinaryURL: await CrossOverDetector.shared.wineBinary()
        )
    }

    /// CrossOver-native launch: its bundled wine binary with `--bottle` and
    /// `--cx-app` flags. This goes through CrossOver's bottle config and DXVK
    /// settings exactly like double-clicking from the CrossOver UI.
    func launch(
        executable: String, arguments: [String],
        in bottle: WineBottle, workingDirectory: String?
    ) async throws -> Process {
        guard let wine = await CrossOverDetector.shared.wineBinary() else {
            throw WineBackendError.runtimeMissing(.crossover, "wine binary")
        }
        // CrossOver's wine wrapper accepts POSIX paths via --cx-app.
        var args: [String] = ["--bottle", bottle.name, "--cx-app", executable]
        args.append(contentsOf: arguments)

        Log.run("crossover.launch", "\(wine.path) \(args.joined(separator: " "))")
        return try ProcessRunner.shared.detached(
            wine,
            arguments: args,
            environment: nil,                       // CrossOver injects its own
            currentDirectory: workingDirectory.map { URL(fileURLWithPath: $0) }
        )
    }
}

// MARK: - GPTK driver

struct GPTKDriver: WineBackendDriver {
    let backend: WineBackend = .gptk

    func isAvailable() async -> Bool { await wineBinary() != nil }

    func wineBinary() async -> URL? {
        let fm = FileManager.default
        for url in PathResolver.gptkCandidatePaths {
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    func bottles() async -> [WineBottle] {
        let root = PathResolver.managedBottles
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let binary = await wineBinary()
        return entries.compactMap { url -> WineBottle? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue,
                  fm.fileExists(atPath: url.appendingPathComponent("drive_c").path)
            else { return nil }

            let driveC = PathResolver.driveC(in: url)
            let tf2 = CrossOverDetector.locateTitanfall2(in: driveC)
            let ns  = CrossOverDetector.locateNorthstar(in: driveC)
            return WineBottle(
                id: "gptk:" + url.lastPathComponent,
                name: url.lastPathComponent,
                backend: .gptk,
                prefixURL: url,
                wineBinaryURL: binary,
                hasNorthstar: ns != nil,
                hasTitanfall2: tf2 != nil,
                titanfall2InstallPath: tf2?.path
            )
        }
    }

    func createBottle(named name: String) async throws -> WineBottle {
        guard let wine = await wineBinary() else {
            throw WineBackendError.backendUnavailable(.gptk)
        }
        let prefix = PathResolver.managedBottles.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

        let result = try await ProcessRunner.shared.capture(
            wine, arguments: ["wineboot", "--init"],
            environment: ["WINEPREFIX": prefix.path, "WINEDEBUG": "-all"]
        )
        guard result.ok else {
            throw WineBackendError.bottleCreationFailed(result.stderr)
        }
        return WineBottle(
            id: "gptk:" + name, name: name,
            backend: .gptk, prefixURL: prefix, wineBinaryURL: wine
        )
    }

    /// GPTK launches via the `gameportingtoolkit` script (the proper Apple
    /// way), or wine64 directly with the right env if only that's available.
    func launch(
        executable: String, arguments: [String],
        in bottle: WineBottle, workingDirectory: String?
    ) async throws -> Process {
        guard let wine = await wineBinary() else {
            throw WineBackendError.runtimeMissing(.gptk, "gameportingtoolkit/wine64")
        }
        let isScriptWrapper = wine.lastPathComponent == "gameportingtoolkit"
        let args: [String] = isScriptWrapper
            ? [bottle.prefixURL.path, executable] + arguments
            : [executable] + arguments

        let env: [String: String] = [
            "WINEPREFIX": bottle.prefixURL.path,
            "WINEDEBUG": "-all",
            "MTL_HUD_ENABLED": "0",
            "ROSETTA_ADVERTISE_AVX": "1",
            "D3DM_SUPPORT_DXGI_MULTIPLANE_OVERLAY": "1",
        ]
        Log.run("gptk.launch", "\(wine.path) \(args.joined(separator: " "))")
        return try ProcessRunner.shared.detached(
            wine, arguments: args, environment: env,
            currentDirectory: workingDirectory.map { URL(fileURLWithPath: $0) }
        )
    }
}

// MARK: - Whisky driver

struct WhiskyDriver: WineBackendDriver {
    let backend: WineBackend = .whisky

    func isAvailable() async -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: PathResolver.whiskyBottlesRoot.path)
            && fm.fileExists(atPath: PathResolver.whiskyWineBinary.path)
    }

    func bottles() async -> [WineBottle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: PathResolver.whiskyBottlesRoot,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries.compactMap { url in
            guard fm.fileExists(atPath: url.appendingPathComponent("drive_c").path)
            else { return nil }
            let driveC = PathResolver.driveC(in: url)
            let tf2 = CrossOverDetector.locateTitanfall2(in: driveC)
            let ns  = CrossOverDetector.locateNorthstar(in: driveC)
            return WineBottle(
                id: "whisky:" + url.lastPathComponent,
                name: url.lastPathComponent,
                backend: .whisky, prefixURL: url,
                wineBinaryURL: PathResolver.whiskyWineBinary,
                hasNorthstar: ns != nil,
                hasTitanfall2: tf2 != nil,
                titanfall2InstallPath: tf2?.path
            )
        }
    }

    func createBottle(named name: String) async throws -> WineBottle {
        // Whisky is discontinued; never create new ones.
        throw WineBackendError.bottleCreationUnsupported(.whisky)
    }

    func launch(
        executable: String, arguments: [String],
        in bottle: WineBottle, workingDirectory: String?
    ) async throws -> Process {
        let wine = bottle.wineBinaryURL ?? PathResolver.whiskyWineBinary
        guard FileManager.default.fileExists(atPath: wine.path) else {
            throw WineBackendError.runtimeMissing(.whisky, "wine64")
        }
        let env: [String: String] = [
            "WINEPREFIX": bottle.prefixURL.path,
            "WINEDEBUG": "-all",
        ]
        Log.run("whisky.launch", "\(wine.path) \(executable)")
        return try ProcessRunner.shared.detached(
            wine, arguments: [executable] + arguments,
            environment: env,
            currentDirectory: workingDirectory.map { URL(fileURLWithPath: $0) }
        )
    }
}

// MARK: - Wrapper-based drivers (Sikarugir, Kegworks)

/// Common logic for self-contained `.app` wrappers (Sikarugir / Kegworks /
/// Wineskin). Each wrapper bundles its own wine under
/// `Contents/SharedSupport/wine/bin/wine64` and its own prefix at
/// `Contents/Resources/wineprefix`.
private func wrapperBottles(
    backend: WineBackend, roots: [URL]
) -> [WineBottle] {
    let fm = FileManager.default
    var out: [WineBottle] = []
    for root in roots {
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { continue }
        for entry in entries where entry.pathExtension == "app" {
            let prefix = entry.appendingPathComponent("Contents/Resources/wineprefix")
            guard fm.fileExists(atPath: prefix.path) else { continue }
            let driveC = PathResolver.driveC(in: prefix)
            let tf2 = CrossOverDetector.locateTitanfall2(in: driveC)
            let ns  = CrossOverDetector.locateNorthstar(in: driveC)
            let wine = entry.appendingPathComponent(
                "Contents/SharedSupport/wine/bin/wine64"
            )
            out.append(WineBottle(
                id: "\(backend.rawValue):" + entry.deletingPathExtension().lastPathComponent,
                name: entry.deletingPathExtension().lastPathComponent,
                backend: backend,
                prefixURL: prefix,
                wineBinaryURL: fm.fileExists(atPath: wine.path) ? wine : nil,
                hasNorthstar: ns != nil,
                hasTitanfall2: tf2 != nil,
                titanfall2InstallPath: tf2?.path
            ))
        }
    }
    return out
}

/// Launch a wrapper bottle (Sikarugir/Kegworks) using its OWN bundled wine.
private func launchInWrapper(
    backend: WineBackend, executable: String, arguments: [String],
    bottle: WineBottle, workingDirectory: String?
) async throws -> Process {
    guard let wine = bottle.wineBinaryURL,
          FileManager.default.fileExists(atPath: wine.path) else {
        throw WineBackendError.runtimeMissing(backend, "bundled wine64")
    }
    let env: [String: String] = [
        "WINEPREFIX": bottle.prefixURL.path,
        "WINEDEBUG": "-all",
    ]
    Log.run("\(backend.rawValue).launch", "\(wine.path) \(executable)")
    return try ProcessRunner.shared.detached(
        wine, arguments: [executable] + arguments,
        environment: env,
        currentDirectory: workingDirectory.map { URL(fileURLWithPath: $0) }
    )
}

struct SikarugirDriver: WineBackendDriver {
    let backend: WineBackend = .sikarugir

    func isAvailable() async -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: PathResolver.sikarugirAppRoot.path) { return true }
        // Call the free function directly — DON'T name a helper `bottles()`,
        // that would clash with the protocol method and cause infinite
        // recursion under `await` overload resolution.
        return !wrapperBottles(
            backend: .sikarugir,
            roots: PathResolver.sikarugirWrapperRoots
        ).isEmpty
    }

    func bottles() async -> [WineBottle] {
        wrapperBottles(backend: .sikarugir, roots: PathResolver.sikarugirWrapperRoots)
    }

    func createBottle(named name: String) async throws -> WineBottle {
        // Sikarugir wrappers must be created via Creator.app — programmatic
        // wrapper creation isn't supported by the project itself.
        throw WineBackendError.bottleCreationUnsupported(.sikarugir)
    }
    func launch(
        executable: String, arguments: [String],
        in bottle: WineBottle, workingDirectory: String?
    ) async throws -> Process {
        try await launchInWrapper(
            backend: .sikarugir, executable: executable, arguments: arguments,
            bottle: bottle, workingDirectory: workingDirectory
        )
    }
}

struct KegworksDriver: WineBackendDriver {
    let backend: WineBackend = .kegworks
    func isAvailable() async -> Bool { !wrapperBottles(backend: .kegworks, roots: PathResolver.kegworksWrapperRoots).isEmpty }
    func bottles() async -> [WineBottle] {
        wrapperBottles(backend: .kegworks, roots: PathResolver.kegworksWrapperRoots)
    }
    func createBottle(named name: String) async throws -> WineBottle {
        throw WineBackendError.bottleCreationUnsupported(.kegworks)
    }
    func launch(
        executable: String, arguments: [String],
        in bottle: WineBottle, workingDirectory: String?
    ) async throws -> Process {
        try await launchInWrapper(
            backend: .kegworks, executable: executable, arguments: arguments,
            bottle: bottle, workingDirectory: workingDirectory
        )
    }
}
