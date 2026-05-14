import Foundation

/// Draconis-only ↔ CrossOver bridge. We don't try to be a wine front-end of
/// our own — we hand off to CrossOver's `cxstart` so every launch behaves
/// exactly like double-clicking the same exe from inside CrossOver's UI.
///
/// (Earlier prototypes had GPTK / Whisky / Sikarugir drivers. None reached a
///  state where Titanfall 2 + Northstar + Maxima ran end-to-end, so they
///  were dropped. This module assumes CrossOver is the only backend.)
public actor WineBackendManager {
    public static let shared = WineBackendManager()

    public enum BackendError: Error, LocalizedError {
        case crossOverNotInstalled
        case cxstartMissing
        case launchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .crossOverNotInstalled:
                return "CrossOver isn't installed. Get it from codeweavers.com."
            case .cxstartMissing:
                return "CrossOver is installed but its `cxstart` helper is missing."
            case .launchFailed(let s):
                return "Launch failed: \(s)"
            }
        }
    }

    /// Discover every CrossOver bottle, Northstar-ready first.
    public func allBottles() async -> [WineBottle] {
        let bottles = await CrossOverDetector.shared.bottles()
        return bottles.sorted {
            ($0.hasNorthstar ? 0 : 1, $0.name) < ($1.hasNorthstar ? 0 : 1, $1.name)
        }
    }

    public func isCrossOverAvailable() async -> Bool {
        await CrossOverDetector.shared.isInstalled()
    }

    /// Run a Windows EXE inside a CrossOver bottle via `cxstart`.
    ///
    /// - wait: true for installers / CLIs whose exit code we want; false for
    ///   long-running GUI apps (games) — keeping `cxstart` alive lets macOS
    ///   App Nap throttle the whole tree and the wine app never renders.
    @discardableResult
    public func launch(
        executable: String,
        arguments: [String] = [],
        in bottle: WineBottle,
        workingDirectory: String? = nil,
        wait: Bool = true
    ) async throws -> Process {
        guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
            throw BackendError.cxstartMissing
        }
        var args: [String] = ["--bottle", bottle.name]
        if wait { args.append("--wait") }
        args.append(executable)
        args.append(contentsOf: arguments)

        Log.run("crossover.launch", "\(cxstart.path) \(args.joined(separator: " "))")
        return try ProcessRunner.shared.detached(
            cxstart,
            arguments: args,
            environment: nil,                   // CrossOver injects its own
            currentDirectory: workingDirectory.map { URL(fileURLWithPath: $0) },
            logFile: PathResolver.bottleLogFile(for: bottle)
        )
    }
}
