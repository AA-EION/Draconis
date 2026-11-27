import DraconisCore
import Foundation

public enum LaunchMode: String, Codable, Sendable, CaseIterable {
    case northstar, vanilla
}

public struct LaunchCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL?
}

/// Decides how to start Titanfall 2. Invariants (shared with macOS):
/// - Northstar is never `Titanfall2.exe -northstar` outside Steam: that needs
///   Wine's `wsock32=n,b` override to load Northstar's proxy DLL. Prefix and
///   native launches use `NorthstarLauncher.exe`, which loads Northstar itself.
/// - With Northstar installed, "vanilla" is Northstar's vanilla-compatibility
///   mode (`-vanilla`), which can join official servers.
public enum LaunchPlanner {
    public enum PlanError: Error, LocalizedError, Equatable {
        case northstarMissing
        case noRunner
        case noUmu
        case noSteam

        public var errorDescription: String? {
            switch self {
            case .northstarMissing: return "Northstar isn't installed in this copy of Titanfall 2. Install it first."
            case .noRunner: return "Pick a Proton or Wine build in Settings to run this copy."
            case .noUmu: return "umu-launcher is needed to run Proton. Install it from Settings."
            case .noSteam: return "Steam isn't installed, so this Steam copy can't be started."
            }
        }
    }

    public static let titanfallAppID = SteamLocator.titanfallAppID
    public static let gameID = "umu-1237970"

    /// The command that starts the Steam client of a given install kind.
    public static func steamCommand(kind: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> [String]? {
        switch kind {
        case "flatpak": return Executables.find("flatpak", environment: environment).map { [$0.path, "run", "com.valvesoftware.Steam"] }
        case "snap": return Executables.find("snap", environment: environment).map { [$0.path, "run", "steam"] }
        case "windows": return nil
        default: return Executables.find("steam", environment: environment).map { [$0.path] }
        }
    }

    /// Exe inside the game folder and its arguments, for launches outside Steam.
    public static func gameCommand(mode: LaunchMode, hasNorthstar: Bool, wine: Bool) throws -> (exe: String, args: [String]) {
        if mode == .northstar && !hasNorthstar { throw PlanError.northstarMissing }
        guard hasNorthstar else { return ("Titanfall2.exe", []) }
        // Under Wine there's no Origin to start: the EA app is started by Draconis.
        var args = wine ? ["-noOriginStartup"] : []
        if mode == .vanilla { args.append("-vanilla") }
        return ("NorthstarLauncher.exe", args)
    }

    /// Arguments Steam passes to Titanfall2.exe. `-northstar` only works with
    /// `WINEDLLOVERRIDES="wsock32=n,b"` in Titanfall 2's Steam launch options
    /// (see `SteamLaunchOptions`); it goes last because older Protons dropped
    /// arguments after the first.
    public static func steamArguments(mode: LaunchMode, hasNorthstar: Bool) throws -> [String] {
        if mode == .northstar && !hasNorthstar { throw PlanError.northstarMissing }
        guard hasNorthstar else { return [] }
        return mode == .vanilla ? ["-vanilla", "-northstar"] : ["-northstar"]
    }

    public static func plan(
        game: GameInstall,
        mode: LaunchMode,
        runner: Runner? = nil,
        umuRun: URL? = nil,
        steamCommand: [String]? = nil,
        defaultPrefix: URL? = nil,
        prefixRunning: Bool = false
    ) throws -> LaunchCommand {
        switch game.source {
        case .steam(_, let kind, _):
            #if os(Windows)
            return try native(game: game, mode: mode)
            #else
            guard let steam = steamCommand ?? Self.steamCommand(kind: kind) else { throw PlanError.noSteam }
            let args = try steamArguments(mode: mode, hasNorthstar: game.hasNorthstar)
            return LaunchCommand(
                executable: steam[0],
                arguments: Array(steam.dropFirst()) + ["-applaunch", titanfallAppID] + args,
                environment: [:], workingDirectory: nil)
            #endif
        case .native:
            #if os(Windows)
            return try native(game: game, mode: mode)
            #else
            guard let prefix = defaultPrefix else { throw PlanError.noRunner }
            return try wine(game: game, prefix: prefix, mode: mode, runner: runner, umuRun: umuRun, prefixRunning: prefixRunning)
            #endif
        case .prefix(let prefix, _):
            return try wine(game: game, prefix: prefix, mode: mode, runner: runner, umuRun: umuRun, prefixRunning: prefixRunning)
        }
    }

    static func native(game: GameInstall, mode: LaunchMode) throws -> LaunchCommand {
        let (exe, args) = try gameCommand(mode: mode, hasNorthstar: game.hasNorthstar, wine: false)
        return LaunchCommand(executable: game.root.appendingPathComponent(exe).path, arguments: args,
                             environment: [:], workingDirectory: game.root)
    }

    /// Run a Windows program from the prefix with the chosen runner.
    public static func runInPrefix(
        exe: String, arguments: [String], prefix: URL, runner: Runner?, umuRun: URL?,
        prefixRunning: Bool = false, workingDirectory: URL? = nil, extraEnvironment: [String: String] = [:]
    ) throws -> LaunchCommand {
        guard let runner else { throw PlanError.noRunner }
        var env = extraEnvironment
        env["WINEPREFIX"] = prefix.path
        switch runner.kind {
        case .proton:
            guard let umuRun else { throw PlanError.noUmu }
            env["GAMEID"] = gameID
            env["PROTONPATH"] = runner.path.path
            if prefixRunning { env["PROTON_VERB"] = "runinprefix" }
            return LaunchCommand(executable: umuRun.path, arguments: [exe] + arguments,
                                 environment: env, workingDirectory: workingDirectory)
        case .wine:
            let overrides = ["winemenubuilder.exe=d", env["WINEDLLOVERRIDES"]].compactMap { $0 }
            env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
            return LaunchCommand(executable: runner.path.appendingPathComponent("bin/wine").path,
                                 arguments: [exe] + arguments, environment: env, workingDirectory: workingDirectory)
        }
    }

    static func wine(game: GameInstall, prefix: URL, mode: LaunchMode, runner: Runner?, umuRun: URL?,
                     prefixRunning: Bool) throws -> LaunchCommand {
        let (exe, args) = try gameCommand(mode: mode, hasNorthstar: game.hasNorthstar, wine: true)
        return try runInPrefix(
            exe: game.root.appendingPathComponent(exe).path, arguments: args, prefix: prefix,
            runner: runner, umuRun: umuRun, prefixRunning: prefixRunning, workingDirectory: game.root,
            // Harmless for NorthstarLauncher; lets an EA-app relaunch with -northstar load the proxy.
            extraEnvironment: ["WINEDLLOVERRIDES": "wsock32=n,b"])
    }

    /// A `run_northstar.txt` starting with `0` silently turns NorthstarLauncher into vanilla.
    public static func prepareFiles(game: GameInstall, mode: LaunchMode) {
        guard mode == .northstar else { return }
        let file = game.root.appendingPathComponent("run_northstar.txt")
        if let text = try? String(contentsOf: file, encoding: .utf8), text.hasPrefix("0") {
            try? "1".write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
