import Foundation
import AppKit

/// Watches a bottle (CrossOver) or prefix (Draconis Wine) through the
/// Titanfall 2 setup stages: launcher installed, then game installed.
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

        /// Maxima drives `cxstart`, so it only works in CrossOver bottles.
        public func available(on backend: WineBackend) -> Bool {
            self != .maxima || backend == .crossover
        }

        /// One-line summary shown next to the option in the picker.
        public var summary: String {
            switch self {
            case .steam:
                return "Steam delivers the game. Draconis starts it once through Steam so Steam installs the EA app, which handles sign-in."
            case .ea:
                return "EA app delivers the game and handles sign-in natively. Simplest path."
            case .maxima:
                return "Experimental — expect breakage. Maxima downloads the game directly from EA's servers without Steam or the EA app. Requires the game to be in your EA library."
            case .epic:
                return "Sign in to Epic in your browser; the EA app then downloads your Epic copy. No Epic launcher needed."
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

    /// Poll `bottleID` every `interval` seconds; `onStage` fires on the main
    /// actor whenever the detected stage changes.
    public func startWatching(
        bottleID: String,
        interval: TimeInterval = 5,
        onStage: @escaping @MainActor (Stage) -> Void
    ) {
        stopWatching()
        var lastStage: Stage? = nil
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let stage = await self.detectStage(bottleID: bottleID)
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

    /// `.done` once the game is fully installed (Maxima installs need the
    /// `FInstall.txt` marker, since the exe lands early in the download).
    private func detectStage(bottleID: String) async -> Stage {
        guard let bottle = await WineBackendManager.shared.allBottles().first(where: { $0.id == bottleID }) else {
            return .waitingForBottle
        }
        if bottle.isTitanfallInstallComplete { return .done(bottleID: bottle.id) }
        if bottle.hasLauncher || bottle.hasMaxima { return .waitingForTitanfall(bottleID: bottle.id) }
        return .waitingForBottle
    }
}
