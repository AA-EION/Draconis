import Foundation

/// Which Wine runs a bottle: CrossOver, or Draconis's own open-source Wine
/// (`WineEngine`) for players without CrossOver.
public enum WineBackend: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case crossover
    case draconis

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .crossover: return "CrossOver"
        case .draconis:  return "Draconis Wine"
        }
    }
    public var symbolName: String {
        switch self {
        case .crossover: return "wineglass.fill"
        case .draconis:  return "flame.fill"
        }
    }

    /// Unknown values from older settings (GPTK / Whisky / Sikarugir) decode
    /// to CrossOver instead of failing the whole settings load.
    public init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(WineBackend.init(rawValue:)) ?? .crossover
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A bottle (CrossOver) or prefix (Draconis Wine) Draconis can launch Titanfall 2 from.
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

    /// Path Draconis's Maxima route installs TF2 to (`maxima.exe --install-path`).
    public var maximaInstallRoot: URL {
        PathResolver.driveC(in: prefixURL)
            .appendingPathComponent("Program Files (x86)/Origin Games/Titanfall2")
    }

    /// Whether TF2 is fully installed. Maxima's `FInstall.txt` marker is
    /// only required for a copy Maxima downloaded itself (its exe shows up
    /// mid-download). A Steam / EA copy in a bottle that merely has Maxima
    /// for auth or the CEG fix never gets a marker, and requiring one would
    /// send onboarding back into a full re-download.
    public var isTitanfallInstallComplete: Bool {
        guard hasTitanfall2, let root = titanfall2InstallPath else { return false }
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        guard hasMaxima, rootURL.path == maximaInstallRoot.standardizedFileURL.path else {
            return true
        }
        return FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("FInstall.txt").path
        )
    }

    /// User's stated role for Maxima in this bottle. Read-only computed
    /// from `UserDefaults`; the launch path reads this to pick the
    /// right command. Independent from `hasMaxima` — the user can have
    /// Maxima physically installed but choose `.none` (use a different
    /// launcher for this bottle).
    ///
    /// **Backward-compat fallback:** when no role is persisted yet and
    /// Maxima IS physically installed in the bottle, default to
    /// `.authOnly` so pre-wizard users keep launching through
    /// maxima-cli (their previous behavior). Without this fallback,
    /// existing Maxima-installed bottles would suddenly route to the
    /// `.none` path and fail without EA Desktop.
    public var maximaRole: MaximaRole {
        MaximaRole.load(forBottle: id, fallback: hasMaxima ? .authOnly : .none)
    }

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
