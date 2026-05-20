import Foundation

/// Identifies which Wine/translation layer a given bottle/prefix belongs to.
///
/// **Draconis currently only supports CrossOver.** Other backends (GPTK,
/// Whisky, Sikarugir, custom prefixes) were prototyped earlier but none
/// were stable enough to keep around — running Titanfall 2 + Northstar +
/// Maxima end-to-end has only been validated on CrossOver. The enum still
/// exists as a single-case enum so call sites can keep their `bottle.backend`
/// reads, and to leave room for adding more later without a wider refactor.
public enum WineBackend: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case crossover

    public var id: String { rawValue }
    public var displayName: String { "CrossOver" }
    public var symbolName: String { "wineglass.fill" }

    /// Custom decoder so any persisted value other than "crossover" (e.g. an
    /// old setting from when Draconis tried to support GPTK / Whisky /
    /// Sikarugir / Kegworks) decodes to crossover instead of failing the
    /// whole settings load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        _ = try? container.decode(String.self)
        self = .crossover
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A concrete CrossOver bottle Draconis can launch Titanfall 2 from.
public struct WineBottle: Identifiable, Hashable, Codable, Sendable {
    public var id: String           // stable, derived from backend + prefixURL
    public var name: String
    public var backend: WineBackend
    public var prefixURL: URL       // the WINEPREFIX (drive_c lives here)
    public var hasNorthstar: Bool
    public var hasTitanfall2: Bool
    public var hasSteam: Bool
    public var hasEAApp: Bool
    public var hasEpicGames: Bool
    public var hasMaxima: Bool                 // C:\Program Files\Maxima\maxima-cli.exe present
    public var northstarVersion: String?       // e.g. "v1.28.0", from ns_version.txt
    public var titanfall2InstallPath: String?  // POSIX path to TF2 root inside drive_c

    /// True when any game-store launcher (Steam, EA App, or Epic Games) is present.
    public var hasLauncher: Bool { hasSteam || hasEAApp || hasEpicGames }

    /// User's stated role for Maxima in this bottle. Read-only computed
    /// from `UserDefaults`; the launch path reads this to pick the
    /// right command. Independent from `hasMaxima` — the user can have
    /// Maxima physically installed but choose `.none` (use a different
    /// launcher for this bottle).
    public var maximaRole: MaximaRole { MaximaRole.load(forBottle: id) }

    public init(
        id: String,
        name: String,
        backend: WineBackend = .crossover,
        prefixURL: URL,
        hasNorthstar: Bool = false,
        hasTitanfall2: Bool = false,
        hasSteam: Bool = false,
        hasEAApp: Bool = false,
        hasEpicGames: Bool = false,
        hasMaxima: Bool = false,
        northstarVersion: String? = nil,
        titanfall2InstallPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.prefixURL = prefixURL
        self.hasNorthstar = hasNorthstar
        self.hasTitanfall2 = hasTitanfall2
        self.hasSteam = hasSteam
        self.hasEAApp = hasEAApp
        self.hasEpicGames = hasEpicGames
        self.hasMaxima = hasMaxima
        self.northstarVersion = northstarVersion
        self.titanfall2InstallPath = titanfall2InstallPath
    }
}
