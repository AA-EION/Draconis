import Foundation

/// How Maxima participates in a given bottle's launch chain.
///
/// Bottles can be set up in multiple shapes — installed via Maxima
/// directly (no Steam/EA in the bottle), installed via EA app, or
/// installed via Steam — and Maxima can layer on top of any of them
/// with different scopes. `MaximaRole` captures that decision per
/// bottle so launch logic can pick the right command without re-asking
/// the user every time.
///
/// Persisted in `UserDefaults` keyed by `WineBottle.id`, since the
/// choice is per-bottle and survives across Draconis launches.
public enum MaximaRole: String, Codable, Hashable, Sendable, CaseIterable {
    /// Maxima is NOT installed in the bottle. The launcher (EA Desktop
    /// bundled with the game install, or Steam) handles auth. Simplest
    /// path when the user's Wine handles Steam CEG correctly — or when
    /// the game was installed via EA Desktop directly (no CEG).
    case none

    /// Maxima is installed alongside the launcher. It registers as the
    /// `link2ea://` handler and runs as the EA auth backbone, but the
    /// game's binaries are left untouched. Useful when:
    ///   * You want offline play (Maxima caches the OOA license).
    ///   * You want auth that doesn't depend on EA Desktop being open.
    ///   * Your Wine builds tolerate Steam CEG so no fix is needed.
    case authOnly

    /// Maxima is installed AND the CEG-signed Steam launcher binaries
    /// (`Titanfall2.exe`, `Titanfall2_trial.exe`) are replaced with the
    /// EA originals via `maxima-cli install --replace-files
    /// --only-listed-files`. Recommended for macOS/CrossOver with a
    /// Steam install. Save games, Northstar files, and the rest of the
    /// install are preserved.
    ///
    /// For Maxima-installed games this is the implicit role — Maxima
    /// downloaded the EA originals directly, no replacement needed.
    case fullReplace

    public var displayName: String {
        switch self {
        case .none:        return "Don't install Maxima"
        case .authOnly:    return "Install Maxima as auth handler"
        case .fullReplace: return "Install Maxima + apply CEG fix"
        }
    }

    /// Per-source detail copy. Steam shows the CEG-fix option as
    /// recommended; EA only sees `.authOnly` / `.none`.
    public func detail(for source: BottleInstaller.Frontend) -> String {
        switch (self, source) {
        case (.none, .steam):
            return "Use Steam's bundled EA Desktop for auth. May trigger \"File corruption detected\" on macOS/CrossOver because Steam-signed binaries fail Steam CEG validation under Wine."
        case (.none, .ea):
            return "Use EA Desktop as the auth backbone. Simplest path on macOS — no CEG involved."
        case (.authOnly, .steam):
            return "Install Maxima as the link2ea handler. Binaries stay Steam-signed; if you hit \"File corruption\" you can switch to the full fix later."
        case (.authOnly, .ea):
            return "Install Maxima as an alternative auth backbone. EA Desktop doesn't need to stay open while you play."
        case (.fullReplace, .steam):
            return "Install Maxima and replace Titanfall2.exe + Titanfall2_trial.exe with the EA originals (~3 MB download). Save games and Northstar files preserved. Most reliable path on macOS/CrossOver."
        case (.fullReplace, .ea):
            return "EA installs don't carry CEG, so this option is the same as Auth-only here."
        case (.fullReplace, .maxima):
            return "Maxima downloaded the game directly — the binaries are already EA originals. This is the default role for Maxima installs."
        case (_, .maxima):
            // Maxima-installed games skip the role picker; this branch
            // is unreachable from the wizard. Defensive copy in case
            // some future call site reaches it.
            return "Maxima already owns this install end-to-end."
        case (.fullReplace, .epic), (.authOnly, .epic), (.none, .epic):
            return "Epic path not validated yet."
        }
    }

    // MARK: - Persistence

    /// UserDefaults key for a given bottle ID. We namespace under
    /// `draconis.maximaRole.` so multiple bottles can coexist without
    /// colliding with other persisted state.
    private static func defaultsKey(forBottle id: String) -> String {
        "draconis.maximaRole." + id
    }

    /// Read the persisted role for a bottle. Defaults to `.none` for
    /// bottles we've never seen. Caller should use `BottleInstaller`
    /// detection + `MaximaService.isInstalled` for the truth about
    /// what's physically in the bottle; this is the user's stated
    /// intent.
    public static func load(forBottle id: String) -> MaximaRole {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey(forBottle: id)),
              let role = MaximaRole(rawValue: raw)
        else { return .none }
        return role
    }

    /// Persist a role choice for a bottle.
    public static func save(_ role: MaximaRole, forBottle id: String) {
        UserDefaults.standard.set(role.rawValue, forKey: defaultsKey(forBottle: id))
    }
}
