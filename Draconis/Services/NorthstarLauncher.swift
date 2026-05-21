import Foundation

/// Launches Titanfall 2 inside a bottle. The exact command depends on
/// six variables; rather than the previous "pick vanilla or northstar
/// at the call site" branching, this actor now walks a single decision
/// matrix:
///
/// | Northstar installed | Mode      | Maxima role           | Command                                                                         |
/// |---------------------|-----------|-----------------------|---------------------------------------------------------------------------------|
/// | yes                 | vanilla   | `.fullReplace`/`.authOnly` | maxima-cli launch + --game-path NorthstarLauncher.exe + -noOriginStartup -vanilla |
/// | yes                 | vanilla   | `.none`               | cxstart NorthstarLauncher.exe -noOriginStartup -vanilla                          |
/// | yes                 | northstar | `.fullReplace`/`.authOnly` | maxima-cli launch + --game-path NorthstarLauncher.exe + -noOriginStartup        |
/// | yes                 | northstar | `.none`               | cxstart NorthstarLauncher.exe -noOriginStartup                                   |
/// | no                  | vanilla   | `.fullReplace`/`.authOnly` | maxima-cli launch + --game-path Titanfall2.exe                                |
/// | no                  | vanilla   | `.none`               | cxstart Titanfall2.exe                                                           |
/// | no                  | northstar | * (any)               | error — Northstar isn't installed                                                |
///
/// Two notable design decisions:
///
///   * **`-northstar` is NEVER passed to `Titanfall2.exe`.** Empirically,
///     this Wine branch ignores the flag and falls back to vanilla.
///     Northstar always goes through `NorthstarLauncher.exe` instead —
///     which loads Northstar's hooks via the `wsock32.dll` proxy
///     regardless of how the executable is invoked.
///
///   * **Vanilla with Northstar installed still uses NorthstarLauncher**
///     (with `-vanilla`). Northstar's wsock32 proxy is in the install
///     dir; even when the user picks vanilla, going through
///     NorthstarLauncher gives us the auth-fix patches Northstar
///     applies. `-vanilla` tells the launcher to skip mod loading.
public actor NorthstarLauncher {
    public static let shared = NorthstarLauncher()

    private let tf2Offer = "Origin.OFR.50.0001456"

    public enum LaunchMode: String, Sendable, CaseIterable, Identifiable {
        case northstar
        case vanilla
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .northstar: return "Northstar"
            case .vanilla:   return "Titanfall 2 (vanilla)"
            }
        }
    }

    public enum LaunchError: Error, LocalizedError {
        case titanfallNotFound
        case northstarNotFound
        case eaAuthBackboneMissing

        public var errorDescription: String? {
            switch self {
            case .titanfallNotFound:
                return "Titanfall 2 wasn't found in this bottle."
            case .northstarNotFound:
                return "NorthstarLauncher.exe wasn't found in this bottle. Install Northstar before launching in Northstar mode."
            case .eaAuthBackboneMissing:
                return "This launch needs an EA-auth backbone — install Maxima or EA Desktop from the onboarding wizard."
            }
        }
    }

    @discardableResult
    public func launch(
        bottle: WineBottle,
        mode: LaunchMode,
        extraArgs: [String] = []
    ) async throws -> Process {
        Log.info(
            "northstar.launch",
            "Asked to launch \(mode.label) in '\(bottle.name)' [role=\(bottle.maximaRole.rawValue), hasNS=\(bottle.hasNorthstar)]"
        )

        guard let tf2Root = bottle.titanfall2InstallPath
            ?? CrossOverDetector.locateTitanfall2(
                in: PathResolver.driveC(in: bottle.prefixURL)
            )?.path
        else {
            Log.error("northstar.launch", "Titanfall 2 root not found in prefix")
            throw LaunchError.titanfallNotFound
        }

        // Build the exe path + per-mode args for the target binary.
        // After this block, `targetExe` is the binary we'll spawn (via
        // Maxima or cxstart) and `targetArgs` is its argv.
        let targetExe: String
        var targetArgs: [String]

        if bottle.hasNorthstar {
            targetExe = (tf2Root as NSString).appendingPathComponent("NorthstarLauncher.exe")
            guard FileManager.default.fileExists(atPath: targetExe) else {
                Log.error("northstar.launch", "NorthstarLauncher.exe missing at \(targetExe)")
                throw LaunchError.northstarNotFound
            }
            // `-noOriginStartup` skips NorthstarLauncher's hardcoded
            // Origin.exe wait (Origin doesn't exist under Wine).
            // `-vanilla` disables Northstar mod loading when the user
            // explicitly picked the vanilla mode.
            targetArgs = ["-noOriginStartup", "-novid"]
            if mode == .vanilla {
                targetArgs.append("-vanilla")
            }
        } else {
            // No Northstar in the bottle; fall back to Titanfall2.exe.
            // Northstar mode without Northstar installed is an error.
            guard mode == .vanilla else {
                Log.error("northstar.launch", "Northstar mode requested but NorthstarLauncher.exe not present")
                throw LaunchError.northstarNotFound
            }
            targetExe = (tf2Root as NSString).appendingPathComponent("Titanfall2.exe")
            guard FileManager.default.fileExists(atPath: targetExe) else {
                Log.error("northstar.launch", "Titanfall2.exe missing at \(targetExe)")
                throw LaunchError.titanfallNotFound
            }
            targetArgs = ["-novid"]
        }
        targetArgs.append(contentsOf: extraArgs)

        // Dispatch on Maxima role.
        switch bottle.maximaRole {
        case .authOnly, .fullReplace:
            // Maxima drives the launch — it sets up LSX + EA env vars
            // and spawns the target through its bootstrap.
            Log.info("northstar.launch", "Routing through maxima-cli (\(bottle.maximaRole.rawValue))")
            return try await MaximaService.shared.launchGame(
                in: bottle,
                gamePath: targetExe,
                gameArgs: targetArgs
            )

        case .none:
            // No Maxima — direct cxstart. This requires EA Desktop to
            // be in the bottle to handle link2ea:// auth requests TF2
            // (or NorthstarLauncher) emits during startup.
            //
            // Must go through CleanSpawn (not WineBackendManager.launch)
            // for the same reason game launches via maxima-cli do:
            // Foundation.Process from a .app freezes the Wine chain.
            // See CleanSpawn.swift's doc-comment for the full reasoning.
            guard bottle.hasEAApp else {
                throw LaunchError.eaAuthBackboneMissing
            }
            guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
                throw LaunchError.titanfallNotFound
            }
            let logURL = PathResolver.bottleLogFile(for: bottle)
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let cxstartArgs = ["--bottle", bottle.name, targetExe] + targetArgs
            Log.info(
                "northstar.launch",
                "CleanSpawn.spawn cxstart=\(cxstart.path) args=\(cxstartArgs.joined(separator: " "))"
            )
            let pid = try CleanSpawn.spawn(
                executable: cxstart.path,
                arguments: cxstartArgs,
                stdinPath: "/dev/null",
                stdoutPath: logURL.path
            )
            Log.info("northstar.launch", "cxstart spawned pid=\(pid)")
            // No Foundation.Process handle (CleanSpawn returns pid_t only).
            // AppEnvironment.pollUntilGameExits tracks lifetime via
            // `pgrep Titanfall2.exe`, so the stub Process here is
            // intentionally unattached.
            return Process()
        }
    }
}
