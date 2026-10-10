import Foundation

/// Programmatic bottle creation via CrossOver's `cxbottle` CLI.
///
/// Replaces the previous "ship a `Titanfall2.tie` and hand it off to
/// CrossOver" approach. The old crosstie referenced CodeWeavers' Titanfall 2
/// install profile (appid `com.codeweavers.c4.17509`) which forcibly
/// installed Steam as part of bottle creation — taking the user's launcher
/// choice away and rooting them in the Steam install path that we now
/// know runs into Steam CEG corruption on macOS/CrossOver. Going through
/// `cxbottle --create` directly means Draconis decides what gets
/// installed and in what order: empty bottle first, launcher (Steam / EA
/// Desktop / Maxima) second, game install (user-driven through that
/// launcher) third.
///
/// Trade-off: bottles created this way don't get the CrossOver "Titanfall 2"
/// CrossTie profile applied (no automatic DXVK toggles, no `<predependency>`
/// vcredist/.NET install). The wizard installs those explicitly as
/// separate steps where they're actually needed.
@MainActor
public final class WineBottleCreator {
    public static let shared = WineBottleCreator()

    public enum CreatorError: Error, LocalizedError {
        case cxbottleMissing(path: String)
        case bottleAlreadyExists(name: String)
        case creationFailed(exitCode: Int32, stderr: String)

        public var errorDescription: String? {
            switch self {
            case .cxbottleMissing(let path):
                return "CrossOver's cxbottle binary not found at \(path). Is CrossOver installed?"
            case .bottleAlreadyExists(let name):
                return "A bottle named \"\(name)\" already exists. Pick a different name, or reuse the existing bottle."
            case .creationFailed(let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmed.isEmpty ? "" : ": \(trimmed)"
                return "cxbottle exited with code \(code)\(suffix)"
            }
        }
    }

    /// Absolute path to CrossOver's `cxbottle` binary. Resolved on every
    /// read so an in-session CrossOver install / update is picked up
    /// without restarting Draconis (same approach `PathResolver.crossOverApp`
    /// uses).
    public var cxbottlePath: URL {
        PathResolver.crossOverApp
            .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/cxbottle")
    }

    /// True if a bottle directory with this exact name already exists in
    /// CrossOver's bottles root. Used by callers to decide between
    /// "create new" and "reuse existing" before invoking `createBottle`.
    public func bottleExists(named name: String) -> Bool {
        let prefix = PathResolver.crossOverBottlesRoot
            .appendingPathComponent(name, isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: prefix.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Create a fresh bottle via `cxbottle --create --template <template>`.
    ///
    /// Default template is `win10_64` — modern 64-bit Windows 10 prefix,
    /// CrossOver's default for newer games. Other templates CrossOver
    /// supports today: `win98`, `win2000`, `winxp`. They're niche and
    /// Draconis doesn't expose them in the UI.
    ///
    /// Throws `.bottleAlreadyExists` if the target name is already taken
    /// — the caller should decide whether to reuse it (just skip creation)
    /// or surface the conflict to the user. `cxbottle` itself doesn't
    /// guarantee a clean refusal in that case (its behavior on an existing
    /// directory is "unspecified" per the help text), so we pre-check.
    public func createBottle(
        name: String,
        description: String? = nil,
        template: String = "win10_64"
    ) async throws {
        let cxbottle = cxbottlePath
        guard FileManager.default.isExecutableFile(atPath: cxbottle.path) else {
            throw CreatorError.cxbottleMissing(path: cxbottle.path)
        }

        if bottleExists(named: name) {
            throw CreatorError.bottleAlreadyExists(name: name)
        }

        var args = [
            "--bottle", name,
            "--create",
            "--template", template,
        ]
        if let description {
            args.append(contentsOf: ["--description", description])
        }
        // What CrossOver itself sets when it creates a Titanfall 2 bottle.
        args += [
            "--param", "EnvironmentVariables:WINEMSYNC=1",
            "--param", "EnvironmentVariables:CX_BOTTLE_CREATOR_APPID=com.codeweavers.c4.17509",
        ]

        DebugLog.shared.info("bottle.create", "cxbottle \(args.joined(separator: " "))")

        // Output goes to a file, not a pipe: wineboot starts a wineserver that
        // inherits the descriptors and outlives cxbottle, and wine is chatty
        // enough to fill an undrained pipe and stall the creation.
        let logURL = PathResolver.launchLogs.appendingPathComponent("cxbottle-\(name).log")
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = cxbottle
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle

        let status = try await ProcessRunner.runUntilExit(process)

        if status != 0 {
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let tail = String(output.suffix(2000))
            DebugLog.shared.error("bottle.create", "cxbottle exit=\(status) — see \(logURL.path)")
            throw CreatorError.creationFailed(exitCode: status, stderr: tail)
        }

        DebugLog.shared.ok("bottle.create", "Bottle \"\(name)\" created (template: \(template))")
    }
}
