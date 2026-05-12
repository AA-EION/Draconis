import Foundation

/// Identifies which Wine/translation layer a given bottle/prefix belongs to.
///
/// Draconis prefers a backend in this order:
///   1. CrossOver    (paid, most polished; honour it if the user already has it)
///   2. GPTK         (free; Apple Game Porting Toolkit 2 + wine-crossover)
///   3. Kegworks     (free; community successor to Wineskin, self-contained .app)
///
/// `whisky` is included so we can detect legacy installs and offer to migrate
/// them, but Draconis won't create new Whisky bottles.
public enum WineBackend: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case crossover
    case gptk
    case kegworks
    case whisky      // legacy, read-only support
    case custom      // user-pointed prefix

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .crossover: return "CrossOver"
        case .gptk:      return "Apple GPTK"
        case .kegworks:  return "Kegworks"
        case .whisky:    return "Whisky (legacy)"
        case .custom:    return "Custom prefix"
        }
    }

    /// SF Symbol used in the UI to badge a backend.
    public var symbolName: String {
        switch self {
        case .crossover: return "wineglass.fill"
        case .gptk:      return "applelogo"
        case .kegworks:  return "shippingbox.fill"
        case .whisky:    return "drop.fill"
        case .custom:    return "questionmark.folder.fill"
        }
    }

    /// True when Draconis can *create* new bottles with this backend.
    public var isManagedByDraconis: Bool {
        switch self {
        case .crossover, .whisky: return false
        case .gptk, .kegworks, .custom: return true
        }
    }
}

/// A concrete bottle/prefix that Draconis can launch Northstar from.
public struct WineBottle: Identifiable, Hashable, Codable, Sendable {
    public var id: String           // stable, derived from prefixURL
    public var name: String
    public var backend: WineBackend
    public var prefixURL: URL       // the WINEPREFIX (the .wine / Bottles/<name>)
    public var wineBinaryURL: URL?  // optional explicit wine64 / wine to use
    public var hasNorthstar: Bool
    public var hasTitanfall2: Bool
    public var titanfall2InstallPath: String?  // C:\... drive_c path inside prefix

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
