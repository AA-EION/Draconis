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
        // Declaration order is the order the picker renders. Maxima is
        // experimental and goes last.
        case ea, steam, epic, maxima
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .steam:  return "Steam"
            case .ea:     return "EA app"
            case .maxima: return "Maxima (experimental)"
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
                return "Steam delivers the game. Draconis starts it once through Steam so Steam installs the EA app, which handles sign-in."
            case .ea:
                return "EA app delivers the game and handles auth natively. Simplest path on macOS/CrossOver."
            case .maxima:
                return "Experimental — expect breakage. Maxima downloads the game directly from EA's servers without Steam or the EA app. Requires the game to be in your EA library."
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
    ///   1. A bottle that already has Titanfall 2 **AND** the install
    ///      looks truly complete → `.done`
    ///   2. A bottle that has any launcher (Steam, EA App, Epic Games) OR
    ///      has Maxima installed → `.waitingForTitanfall` (the user is past
    ///      the bottle/launcher step and now needs to drive the game install
    ///      from whichever frontend landed)
    ///   3. Nothing matching → `.waitingForBottle`
    ///
    /// Maxima is treated as a launcher for stage purposes even though it
    /// isn't part of `WineBottle.hasLauncher` — the Maxima route in the
    /// wizard installs Maxima as its frontend equivalent, and from the
    /// progress page's POV step 1 is complete once Maxima is in place.
    ///
    /// **Why the FInstall.txt check matters:** Maxima writes the game's
    /// .exe early in the manifest sequence (Titanfall2.exe lands within
    /// the first few hundred MB of a ~25 GB download). Advancing to
    /// `.done` on exe-presence alone causes the wizard to flip to
    /// "Ready to launch" while the actual download is still running.
    /// The marker (written by `ContentManager` only after `is_done()`)
    /// is the truth source. For non-Maxima paths (Steam, EA, Epic),
    /// the marker doesn't exist, so we fall back to exe-presence.
    private func detectStage() async -> Stage {
        let bottles = await CrossOverDetector.shared.bottles()
        if let withGame = bottles.first(where: { $0.isTitanfallInstallComplete }) {
            return .done(bottleID: withGame.id)
        }
        if let withFrontend = bottles.first(where: { $0.hasLauncher || $0.hasMaxima }) {
            return .waitingForTitanfall(bottleID: withFrontend.id)
        }
        return .waitingForBottle
    }
}
