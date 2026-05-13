import Foundation

/// Auto-installs free Wine backends via Homebrew when possible.
///
/// We never bundle the backends themselves — instead we drive Homebrew, which
/// is the de-facto package manager on macOS and is already the official install
/// path for every backend Draconis supports.
public actor BackendInstaller {
    public static let shared = BackendInstaller()

    public enum InstallError: Error, LocalizedError {
        case homebrewMissing
        case homebrewFailed(String)
        case unsupportedBackend(WineBackend)

        public var errorDescription: String? {
            switch self {
            case .homebrewMissing:
                return "Homebrew isn't installed. Visit https://brew.sh to install it, then try again."
            case .homebrewFailed(let stderr):
                return "Homebrew failed:\n\(stderr)"
            case .unsupportedBackend(let b):
                return "Draconis can't auto-install \(b.displayName)."
            }
        }
    }

    /// Apple Silicon → /opt/homebrew/bin/brew. Intel → /usr/local/bin/brew.
    public func homebrewBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func canAutoInstall() -> Bool { homebrewBinary() != nil }

    /// Map a backend to its Homebrew cask coordinates.
    /// Each tuple is (tap, cask) — `nil` tap means it's in homebrew/cask.
    private func homebrewCoordinates(for backend: WineBackend) -> (tap: String?, cask: String)? {
        switch backend {
        case .gptk:
            // Apple's official tap.
            return ("apple/apple", "game-porting-toolkit")
        case .sikarugir:
            return ("Sikarugir-App/sikarugir", "sikarugir")
        case .crossover, .whisky, .custom:
            return nil
        }
    }

    public func isAutoInstallable(_ backend: WineBackend) -> Bool {
        homebrewCoordinates(for: backend) != nil && canAutoInstall()
    }

    /// Install a backend via Homebrew. Streams progress + stdout to the log.
    public func install(_ backend: WineBackend) async throws {
        Log.info("backend.install", "Requested install for \(backend.displayName)")

        guard let brew = homebrewBinary() else {
            Log.error("backend.install", "Homebrew not found")
            throw InstallError.homebrewMissing
        }
        guard let (tap, cask) = homebrewCoordinates(for: backend) else {
            throw InstallError.unsupportedBackend(backend)
        }

        // brew tap (idempotent)
        if let tap = tap {
            Log.run("backend.install", "brew tap \(tap)")
            let tapResult = try await ProcessRunner.shared.capture(
                brew, arguments: ["tap", tap]
            )
            if !tapResult.ok {
                Log.error("backend.install", "tap failed: \(tapResult.stderr)")
                throw InstallError.homebrewFailed(tapResult.stderr)
            }
        }

        // brew install --cask
        let fullCask = tap.map { "\($0)/\(cask)" } ?? cask
        Log.run("backend.install", "brew install --cask --no-quarantine \(fullCask)")
        let result = try await ProcessRunner.shared.capture(
            brew,
            arguments: ["install", "--cask", "--no-quarantine", fullCask]
        )
        if !result.ok {
            Log.error("backend.install", result.stderr.isEmpty ? result.stdout : result.stderr)
            throw InstallError.homebrewFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        Log.ok("backend.install", "\(backend.displayName) installed")
    }

    /// Apple Silicon needs Rosetta 2 for GPTK / wine-crossover.
    public func ensureRosetta() async throws {
        Log.info("backend.install", "Checking Rosetta status")
        let arch = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/uname"),
            arguments: ["-m"]
        )
        guard arch.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "arm64" else {
            Log.info("backend.install", "Intel Mac — Rosetta not required.")
            return
        }
        // Check for Rosetta marker file
        let marker = "/Library/Apple/usr/share/rosetta/rosetta"
        if FileManager.default.fileExists(atPath: marker) {
            Log.ok("backend.install", "Rosetta already present.")
            return
        }
        Log.run("backend.install", "softwareupdate --install-rosetta --agree-to-license")
        let installer = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/sbin/softwareupdate"),
            arguments: ["--install-rosetta", "--agree-to-license"]
        )
        if !installer.ok {
            Log.warn("backend.install", "Rosetta install returned non-zero: \(installer.stderr)")
        } else {
            Log.ok("backend.install", "Rosetta installed.")
        }
    }
}
