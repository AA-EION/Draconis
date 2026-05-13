import Foundation
import AppKit

/// Creates new CrossOver bottles via CrossOver's own `cxbottle` CLI.
/// The CLI is the publicly-documented, supported way to script CrossOver:
///
///   /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/cxbottle \
///       --create --bottle "<name>" --template <template>
///
/// We default to `win10_64` so Titanfall 2 (a 64-bit game) gets the right
/// environment. After creation, we open CrossOver's app-install flow for the
/// "Titanfall 2" profile, which exists in CrossOver's official compatibility
/// database — that's what the user meant by "ya existe en el manager de
/// crossover".
public actor CrossOverBottleCreator {
    public static let shared = CrossOverBottleCreator()

    public enum CreatorError: Error, LocalizedError {
        case crossOverNotInstalled
        case cxbottleMissing
        case bottleAlreadyExists(String)
        case scriptFailed(String)

        public var errorDescription: String? {
            switch self {
            case .crossOverNotInstalled:    return "CrossOver isn't installed."
            case .cxbottleMissing:          return "CrossOver's `cxbottle` helper wasn't found."
            case .bottleAlreadyExists(let n): return "A bottle named “\(n)” already exists."
            case .scriptFailed(let s):      return "CrossOver scripting failed:\n\(s)"
            }
        }
    }

    /// Path to `cxbottle` inside CrossOver.app.
    public func cxbottleBinary() -> URL? {
        let url = PathResolver.crossOverApp
            .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/cxbottle")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Create a fresh CrossOver bottle and (optionally) trigger CrossOver's
    /// built-in installer profile for Titanfall 2.
    @discardableResult
    public func createTitanfall2Bottle(
        named name: String = "Titanfall 2",
        template: String = "win10_64",
        installVia: InstallProfile? = .titanfall2
    ) async throws -> URL {
        Log.info("crossover.create", "Asked to create bottle “\(name)”")

        guard await CrossOverDetector.shared.isInstalled() else {
            throw CreatorError.crossOverNotInstalled
        }
        guard let cxbottle = cxbottleBinary() else {
            throw CreatorError.cxbottleMissing
        }

        let bottlePath = PathResolver.crossOverBottlesRoot.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: bottlePath.path) {
            Log.warn("crossover.create", "Bottle “\(name)” already exists at \(bottlePath.path)")
            throw CreatorError.bottleAlreadyExists(name)
        }

        Log.run("crossover.create", "cxbottle --create --bottle \"\(name)\" --template \(template)")
        let result = try await ProcessRunner.shared.capture(
            cxbottle,
            arguments: ["--create", "--bottle", name, "--template", template]
        )
        if !result.ok {
            Log.error("crossover.create", result.stderr.isEmpty ? result.stdout : result.stderr)
            throw CreatorError.scriptFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        Log.ok("crossover.create", "Bottle “\(name)” created.")

        if let profile = installVia {
            try await launchInstallerProfile(profile, inBottle: name)
        }

        return bottlePath
    }

    /// Hand off to CrossOver's UI for the Titanfall 2 install profile. CrossOver
    /// ships a Titanfall 2 entry in its compatibility database; opening it via
    /// AppleScript drops the user straight into the install wizard for that
    /// bottle, which legally has to be user-driven (Steam/EA App credentials).
    public func launchInstallerProfile(
        _ profile: InstallProfile, inBottle bottle: String
    ) async throws {
        Log.info("crossover.create", "Opening CrossOver install profile \(profile.rawValue)")
        let script = """
        tell application "CrossOver"
            activate
            install application "\(profile.rawValue)" in bottle "\(bottle)"
        end tell
        """
        try await runAppleScript(script)
    }

    /// Wrap NSAppleScript in async/throws.
    private func runAppleScript(_ source: String) async throws {
        // NSAppleScript is AppKit (main thread). Hop onto the main actor.
        let result: (success: Bool, error: String?) = await MainActor.run {
            var errInfo: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                return (false, "Could not compile AppleScript")
            }
            let _ = script.executeAndReturnError(&errInfo)
            if let err = errInfo,
               let msg = err[NSAppleScript.errorMessage] as? String {
                return (false, msg)
            }
            return (true, nil)
        }
        if !result.success {
            throw CreatorError.scriptFailed(result.error ?? "Unknown AppleScript error")
        }
    }

    public enum InstallProfile: String, Sendable {
        case titanfall2 = "Titanfall 2"
    }
}
