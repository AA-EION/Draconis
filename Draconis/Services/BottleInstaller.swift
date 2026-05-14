import Foundation
import AppKit

/// Drives the automated Titanfall 2 bottle creation flow.
///
/// Strategy: ship CrossOver's signed Titanfall2.tie next to the app and hand
/// it off to CrossOver via NSWorkspace. CrossOver then walks the user through
/// its own install profile (win10_64 template, predependencies, Steam install).
///
/// Draconis only watches: it polls CrossOver's bottles directory every few
/// seconds until a bottle appears that contains steam.exe — at which point the
/// game-install step is up to the user.
@MainActor
public final class BottleInstaller {
    public static let shared = BottleInstaller()

    public enum Frontend: String, CaseIterable, Identifiable, Sendable {
        case steam, ea, epic
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .steam: return "Steam"
            case .ea:    return "EA app"
            case .epic:  return "Epic Games"
            }
        }
        public var available: Bool { self == .steam }
    }

    public enum Stage: Equatable, Sendable {
        /// Waiting for CrossOver to finish creating the bottle and for the
        /// Steam install step of CrossOver's profile to land steam.exe inside.
        case waitingForBottle
        /// Bottle + Steam are ready. User now needs to log into Steam and let
        /// Titanfall 2 download to 100% before continuing.
        case waitingForTitanfall(bottleID: String)
        case done(bottleID: String)
    }

    private var pollTask: Task<Void, Never>?

    /// Open the bundled crosstie with CrossOver. Returns false if the resource
    /// is missing or LaunchServices refuses.
    @discardableResult
    public func openTitanfall2Crosstie() -> Bool {
        guard let tie = Bundle.main.url(
            forResource: "Titanfall2", withExtension: "tie"
        ) else {
            DebugLog.shared.error("bottle.auto", "Titanfall2.tie not bundled")
            return false
        }
        DebugLog.shared.info("bottle.auto", "Opening crosstie \(tie.lastPathComponent) with CrossOver")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(
            [tie],
            withApplicationAt: PathResolver.crossOverApp,
            configuration: cfg
        ) { _, error in
            if let error {
                DebugLog.shared.error("bottle.auto", "open .tie failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    /// Start polling every `interval` seconds. `onStage` fires on the main
    /// actor whenever the detected stage advances. Cancel the returned task
    /// (or call `stopWatching`) to stop polling.
    public func startWatching(
        interval: TimeInterval = 5,
        onStage: @escaping @MainActor (Stage) -> Void
    ) {
        stopWatching()
        var lastStage: Stage? = nil
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let stage = await self.detectStage()
                if stage != lastStage {
                    lastStage = stage
                    onStage(stage)
                }
                if case .done = stage { break }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stopWatching() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Snapshot today's bottles and pick the most relevant one to report on.
    /// Preference order:
    ///   1. A bottle that already has Titanfall 2 → `.done`
    ///   2. A bottle that has steam.exe → `.waitingForTitanfall`
    ///   3. Nothing matching → `.waitingForBottle`
    private func detectStage() async -> Stage {
        let bottles = await CrossOverDetector.shared.bottles()
        if let withGame = bottles.first(where: \.hasTitanfall2) {
            return .done(bottleID: withGame.id)
        }
        if let withSteam = bottles.first(where: \.hasSteam) {
            return .waitingForTitanfall(bottleID: withSteam.id)
        }
        return .waitingForBottle
    }
}
