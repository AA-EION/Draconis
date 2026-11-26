import Foundation

/// A server entry from the Northstar masterserver
/// (https://northstar.tf/client/servers).
public struct NorthstarServer: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var map: String
    public var playlist: String
    public var playerCount: Int
    public var maxPlayers: Int
    public var hasPassword: Bool
    public var region: String?
    public var requiredMods: [RequiredMod]

    public struct RequiredMod: Hashable, Codable, Sendable {
        public var name: String
        public var version: String
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case map
        case playlist
        case playerCount  = "playerCount"
        case maxPlayers   = "maxPlayers"
        case hasPassword  = "hasPassword"
        case region
        case requiredMods = "modInfo"
    }

    // The masterserver wraps required mods in a `{ Mods: [...] }` object.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        name          = try c.decode(String.self, forKey: .name)
        description   = (try? c.decode(String.self, forKey: .description)) ?? ""
        map           = try c.decode(String.self, forKey: .map)
        playlist      = try c.decode(String.self, forKey: .playlist)
        playerCount   = try c.decode(Int.self, forKey: .playerCount)
        maxPlayers    = try c.decode(Int.self, forKey: .maxPlayers)
        hasPassword   = (try? c.decode(Bool.self, forKey: .hasPassword)) ?? false
        region        = try? c.decode(String.self, forKey: .region)

        if let wrapped = try? c.decode(ModInfoWrapper.self, forKey: .requiredMods) {
            requiredMods = wrapped.Mods
        } else {
            requiredMods = []
        }
    }

    public init(
        id: String, name: String, description: String,
        map: String, playlist: String,
        playerCount: Int, maxPlayers: Int,
        hasPassword: Bool, region: String?,
        requiredMods: [RequiredMod]
    ) {
        self.id = id; self.name = name; self.description = description
        self.map = map; self.playlist = playlist
        self.playerCount = playerCount; self.maxPlayers = maxPlayers
        self.hasPassword = hasPassword; self.region = region
        self.requiredMods = requiredMods
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(map, forKey: .map)
        try c.encode(playlist, forKey: .playlist)
        try c.encode(playerCount, forKey: .playerCount)
        try c.encode(maxPlayers, forKey: .maxPlayers)
        try c.encode(hasPassword, forKey: .hasPassword)
        try c.encodeIfPresent(region, forKey: .region)
        try c.encode(ModInfoWrapper(Mods: requiredMods), forKey: .requiredMods)
    }

    private struct ModInfoWrapper: Codable {
        var Mods: [RequiredMod]
    }
}
