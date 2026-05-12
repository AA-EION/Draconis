import Foundation

/// Backends know how to: find their wine binary, list existing bottles,
/// and (where supported) create a fresh bottle.
public protocol WineBackendDriver: Sendable {
    var backend: WineBackend { get }
    func isAvailable() async -> Bool
    func wineBinary() async -> URL?
    func bottles() async -> [WineBottle]
    func createBottle(named name: String) async throws -> WineBottle
}

public enum WineBackendError: Error, LocalizedError {
    case backendUnavailable(WineBackend)
    case bottleCreationUnsupported(WineBackend)
    case bottleCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .backendUnavailable(let b):
            return "\(b.displayName) is not installed."
        case .bottleCreationUnsupported(let b):
            return "Draconis can't create new bottles for \(b.displayName); use the app itself."
        case .bottleCreationFailed(let s):
            return "Bottle creation failed: \(s)"
        }
    }
}

/// Coordinates all known Wine backends.
public actor WineBackendManager {
    public static let shared = WineBackendManager()

    private let drivers: [WineBackendDriver] = [
        CrossOverDriver(),
        GPTKDriver(),
        KegworksDriver(),
        WhiskyDriver(),
    ]

    /// All bottles from all backends, sorted by Northstar-readiness first.
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

    /// Preferred backend for *new* installs, in this order:
    /// CrossOver → GPTK → Kegworks → custom.
    public func preferredBackend() async -> WineBackend? {
        let order: [WineBackend] = [.crossover, .gptk, .kegworks]
        let avail = Set(await availableBackends())
        return order.first { avail.contains($0) }
    }

    public func driver(for backend: WineBackend) -> WineBackendDriver? {
        drivers.first { $0.backend == backend }
    }
}

// MARK: - Drivers

struct CrossOverDriver: WineBackendDriver {
    let backend: WineBackend = .crossover
    func isAvailable() async -> Bool { await CrossOverDetector.shared.isInstalled() }
    func wineBinary() async -> URL? { await CrossOverDetector.shared.wineBinary() }
    func bottles() async -> [WineBottle] { await CrossOverDetector.shared.bottles() }
    func createBottle(named name: String) async throws -> WineBottle {
        // CrossOver bottle creation is best driven by the user via CrossOver
        // itself; programmatically scripting it would require licensing
        // considerations. Surface a clear error so the UI can tell the user
        // what to do.
        throw WineBackendError.bottleCreationUnsupported(.crossover)
    }
}

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
        // GPTK doesn't impose a bottle layout — Draconis manages its own under
        // ~/Library/Application Support/Draconis/Bottles/<name>.
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
            let tf2 = CrossOverDetector.shared.locateTitanfall2(in: driveC)
            let ns  = CrossOverDetector.shared.locateNorthstar(in: driveC)
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

        // Initialise the prefix with `wineboot --init`.
        let result = try await ProcessRunner.shared.capture(
            wine, arguments: ["wineboot", "--init"],
            environment: [
                "WINEPREFIX": prefix.path,
                "WINEDEBUG": "-all",
            ]
        )
        guard result.ok else {
            throw WineBackendError.bottleCreationFailed(result.stderr)
        }
        return WineBottle(
            id: "gptk:" + name, name: name,
            backend: .gptk, prefixURL: prefix, wineBinaryURL: wine
        )
    }
}

struct KegworksDriver: WineBackendDriver {
    let backend: WineBackend = .kegworks

    func isAvailable() async -> Bool { !(await wrapperApps().isEmpty) }

    func wineBinary() async -> URL? {
        // Kegworks bottles are self-contained .app bundles, each shipping its
        // own wine. There isn't a single "wine binary" — we resolve per-bottle.
        return nil
    }

    func bottles() async -> [WineBottle] {
        await wrapperApps().compactMap { app in
            // Each wrapper app has Contents/Resources/wineprefix
            let prefix = app.appendingPathComponent("Contents/Resources/wineprefix")
            guard FileManager.default.fileExists(atPath: prefix.path) else { return nil }
            let driveC = PathResolver.driveC(in: prefix)
            let tf2 = CrossOverDetector.shared.locateTitanfall2(in: driveC)
            let ns  = CrossOverDetector.shared.locateNorthstar(in: driveC)
            // Wine binary is usually Contents/SharedSupport/wine/bin/wine64
            let wine = app.appendingPathComponent(
                "Contents/SharedSupport/wine/bin/wine64"
            )
            return WineBottle(
                id: "kegworks:" + app.deletingPathExtension().lastPathComponent,
                name: app.deletingPathExtension().lastPathComponent,
                backend: .kegworks,
                prefixURL: prefix,
                wineBinaryURL: FileManager.default.fileExists(atPath: wine.path) ? wine : nil,
                hasNorthstar: ns != nil,
                hasTitanfall2: tf2 != nil,
                titanfall2InstallPath: tf2?.path
            )
        }
    }

    func createBottle(named name: String) async throws -> WineBottle {
        // Creating a Kegworks wrapper requires the Kegworks UI; we can't
        // scaffold one ourselves without bundling Kegworks itself.
        throw WineBackendError.bottleCreationUnsupported(.kegworks)
    }

    private func wrapperApps() async -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for root in PathResolver.kegworksWrapperRoots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                // Heuristic: only wrappers have Contents/Resources/wineprefix.
                let prefix = entry.appendingPathComponent("Contents/Resources/wineprefix")
                if fm.fileExists(atPath: prefix.path) { out.append(entry) }
            }
        }
        return out
    }
}

struct WhiskyDriver: WineBackendDriver {
    let backend: WineBackend = .whisky

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: PathResolver.whiskyBottlesRoot.path)
    }

    func wineBinary() async -> URL? { nil } // Whisky bundles its own
    func bottles() async -> [WineBottle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: PathResolver.whiskyBottlesRoot,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries.compactMap { url in
            let prefix = url.appendingPathComponent("drive_c").deletingLastPathComponent()
            guard fm.fileExists(atPath: prefix.appendingPathComponent("drive_c").path)
            else { return nil }
            let driveC = PathResolver.driveC(in: prefix)
            let tf2 = CrossOverDetector.shared.locateTitanfall2(in: driveC)
            let ns  = CrossOverDetector.shared.locateNorthstar(in: driveC)
            return WineBottle(
                id: "whisky:" + url.lastPathComponent,
                name: url.lastPathComponent,
                backend: .whisky, prefixURL: prefix,
                hasNorthstar: ns != nil,
                hasTitanfall2: tf2 != nil,
                titanfall2InstallPath: tf2?.path
            )
        }
    }

    func createBottle(named name: String) async throws -> WineBottle {
        throw WineBackendError.bottleCreationUnsupported(.whisky)
    }
}
