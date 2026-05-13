import Foundation

/// Identifies which Wine/translation layer a given bottle/prefix belongs to.
///
/// Each backend has its **own runtime** — Draconis never tries to be a "wine
/// front-end" of its own. We always hand off to the backend's own launcher
/// (CrossOver's `cxbottle`/`cxstart`, Whisky's bundled wine64,
/// Sikarugir wrapper apps, etc.) so the user gets exactly the same
/// behaviour as if they had double-clicked from inside that backend.
public enum WineBackend: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case crossover
    case gptk
    case sikarugir
    case whisky      // legacy, read-only support
    case custom      // user-pointed prefix

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .crossover: return "CrossOver"
        case .gptk:      return "Apple GPTK"
        case .sikarugir: return "Sikarugir"
        case .whisky:    return "Whisky (legacy)"
        case .custom:    return "Custom prefix"
        }
    }

    /// True for backends a user has to *pay* for. Draconis will never try to
    /// auto-install these.
    public var isPaid: Bool {
        switch self {
        case .crossover: return true
        default:         return false
        }
    }

    /// SF Symbol used in the UI to badge a backend.
    public var symbolName: String {
        switch self {
        case .crossover: return "wineglass.fill"
        case .gptk:      return "applelogo"
        case .sikarugir: return "tortoise.fill"
        case .whisky:    return "drop.fill"
        case .custom:    return "questionmark.folder.fill"
        }
    }

    /// True when Draconis can *create* new bottles with this backend itself.
    public var canCreateBottles: Bool {
        switch self {
        case .crossover, .gptk: return true
        case .sikarugir, .whisky, .custom: return false
        }
    }

    // MARK: - Codable (legacy migration)

    /// Custom decoder that silently migrates the legacy `"kegworks"` raw value
    /// (used in persisted data before the app was renamed Sikarugir) to
    /// `.sikarugir`. Without this, any saved bottle list or selected-bottle
    /// preference that contains `"kegworks"` would fail to decode on upgrade.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let value = WineBackend(rawValue: rawValue) {
            self = value
        } else if rawValue == "kegworks" {
            self = .sikarugir
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown WineBackend: \(rawValue)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A concrete bottle/prefix that Draconis can launch Northstar from.
public struct WineBottle: Identifiable, Hashable, Codable, Sendable {
    public var id: String           // stable, derived from backend + prefixURL
    public var name: String
    public var backend: WineBackend
    public var prefixURL: URL       // the WINEPREFIX (the .wine / Bottles/<name>)
    public var wineBinaryURL: URL?  // optional explicit wine64 / wine to use
    public var hasNorthstar: Bool
    public var hasTitanfall2: Bool
    public var titanfall2InstallPath: String?  // POSIX path to TF2 root inside drive_c

    public init(
        id: String,
        name: String,
        backend: WineBackend,
        prefixURL: URL,
        wineBinaryURL: URL? = nil,
        hasNorthstar: Bool = false,
        hasTitanfall2: Bool = false,
        titanfall2InstallPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.prefixURL = prefixURL
        self.wineBinaryURL = wineBinaryURL
        self.hasNorthstar = hasNorthstar
        self.hasTitanfall2 = hasTitanfall2
        self.titanfall2InstallPath = titanfall2InstallPath
    }
}
