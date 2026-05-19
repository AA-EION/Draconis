import Foundation
import AppKit

/// Polls CrossOver's bottles directory and reports progress through the
/// Titanfall 2 setup stages.
///
/// Strategy changed in the wizard rewrite: bottle creation is no longer
/// handed off to a CrossTie file (which forced Steam to be the launcher).
/// `WineBottleCreator` creates the bottle programmatically via `cxbottle
/// --create`, then this class watches the bottle's contents to drive the
/// next step (install launcher, install game, done).
@MainActor
public final class BottleInstaller {
    public static let shared = BottleInstaller()

    public enum Frontend: String, CaseIterable, Identifiable, Sendable {
        case steam, ea, maxima, epic
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .steam:  return "Steam"
            case .ea:     return "EA app"
            case .maxima: return "Maxima (direct download)"
            case .epic:   return "Epic Games"
            }
        }

        /// True when this path is fully implemented end-to-end. Epic is
        /// off until someone with an Epic copy of TF2 tests the flow.
        public var available: Bool {
            switch self {
            case .steam, .ea, .maxima: return true
            case .epic:                return false
            }
        }

        /// One-line summary shown next to the option in the picker.
        public var summary: String {
            switch self {
            case .steam:
                return "Steam delivers the game. EA Desktop installs automatically on first launch and handles auth. Steam-installed binaries are CEG-signed — apply the Maxima fix afterward if you hit \"File corruption\" on macOS/CrossOver."
            case .ea:
                return "EA app delivers the game and handles auth natively. Simplest path on macOS/CrossOver."
            case .maxima:
                return "Maxima downloads the game directly from EA's servers without Steam or EA Desktop. Requires the game to be in your EA library (purchased on EA, or Steam/Epic linked + synced at least once)."
            case .epic:
                return "Coming soon — Epic's TF2 install hasn't been validated through this wizard yet."
            }
        }
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
    ///   2. A bottle that has any launcher (Steam, EA App, or Epic Games) → `.waitingForTitanfall`
    ///   3. Nothing matching → `.waitingForBottle`
    private func detectStage() async -> Stage {
        let bottles = await CrossOverDetector.shared.bottles()
        if let withGame = bottles.first(where: \.hasTitanfall2) {
            return .done(bottleID: withGame.id)
        }
        if let withLauncher = bottles.first(where: \.hasLauncher) {
            return .waitingForTitanfall(bottleID: withLauncher.id)
        }
        return .waitingForBottle
    }
}
