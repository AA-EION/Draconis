import Foundation

/// A single mod installed locally under R2Northstar/mods.
public struct InstalledMod: Identifiable, Hashable, Codable, Sendable {
    public var id: String          // <namespace>-<name>
    public var name: String
    public var version: String
    public var enabled: Bool
    public var folderURL: URL
    public var thunderstoreID: String?

    public init(
        id: String, name: String, version: String,
        enabled: Bool, folderURL: URL, thunderstoreID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.enabled = enabled
        self.folderURL = folderURL
        self.thunderstoreID = thunderstoreID
    }
}

// MARK: - Thunderstore (northstar.thunderstore.io)

public struct ThunderstorePackage: Identifiable, Hashable, Codable, Sendable {
    public var name: String
    public var fullName: String      // <owner>-<name>
    public var owner: String
    public var packageURL: URL?
    public var donationLink: URL?
    public var dateCreated: Date
    public var dateUpdated: Date
    public var ratingScore: Int
    public var isPinned: Bool
    public var isDeprecated: Bool
    public var hasNsfwContent: Bool
    public var categories: [String]
    public var versions: [ThunderstoreVersion]

    public var id: String { fullName }
    public var latest: ThunderstoreVersion? { versions.first }

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case owner
        case packageURL = "package_url"
        case donationLink = "donation_link"
        case dateCreated = "date_created"
        case dateUpdated = "date_updated"
        case ratingScore = "rating_score"
        case isPinned = "is_pinned"
        case isDeprecated = "is_deprecated"
        case hasNsfwContent = "has_nsfw_content"
        case categories
        case versions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name             = try c.decode(String.self, forKey: .name)
        fullName         = try c.decode(String.self, forKey: .fullName)
        owner            = try c.decode(String.self, forKey: .owner)
        packageURL       = try c.lenientURL(forKey: .packageURL)
        donationLink     = try c.lenientURL(forKey: .donationLink)
        dateCreated      = try c.decode(Date.self, forKey: .dateCreated)
        dateUpdated      = try c.decode(Date.self, forKey: .dateUpdated)
        ratingScore      = (try? c.decode(Int.self, forKey: .ratingScore)) ?? 0
        isPinned         = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        isDeprecated     = (try? c.decode(Bool.self, forKey: .isDeprecated)) ?? false
        hasNsfwContent   = (try? c.decode(Bool.self, forKey: .hasNsfwContent)) ?? false
        categories       = (try? c.decode([String].self, forKey: .categories)) ?? []
        versions         = try c.decode([ThunderstoreVersion].self, forKey: .versions)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(fullName, forKey: .fullName)
        try c.encode(owner, forKey: .owner)
        try c.encodeIfPresent(packageURL, forKey: .packageURL)
        try c.encodeIfPresent(donationLink, forKey: .donationLink)
        try c.encode(dateCreated, forKey: .dateCreated)
        try c.encode(dateUpdated, forKey: .dateUpdated)
        try c.encode(ratingScore, forKey: .ratingScore)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(isDeprecated, forKey: .isDeprecated)
        try c.encode(hasNsfwContent, forKey: .hasNsfwContent)
        try c.encode(categories, forKey: .categories)
        try c.encode(versions, forKey: .versions)
    }
}

public struct ThunderstoreVersion: Hashable, Codable, Sendable {
    public var name: String
    public var fullName: String
    public var description: String
    public var icon: URL?
    public var versionNumber: String
    public var dependencies: [String]
    public var downloadURL: URL
    public var downloads: Int
    public var dateCreated: Date
    public var websiteURL: URL?
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case description
        case icon
        case versionNumber = "version_number"
        case dependencies
        case downloadURL = "download_url"
        case downloads
        case dateCreated = "date_created"
        case websiteURL = "website_url"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name           = try c.decode(String.self, forKey: .name)
        fullName       = try c.decode(String.self, forKey: .fullName)
        description    = (try? c.decode(String.self, forKey: .description)) ?? ""
        icon           = try c.lenientURL(forKey: .icon)
        versionNumber  = try c.decode(String.self, forKey: .versionNumber)
        dependencies   = (try? c.decode([String].self, forKey: .dependencies)) ?? []
        downloadURL    = try c.decode(URL.self, forKey: .downloadURL)
        downloads      = (try? c.decode(Int.self, forKey: .downloads)) ?? 0
        dateCreated    = try c.decode(Date.self, forKey: .dateCreated)
        websiteURL     = try c.lenientURL(forKey: .websiteURL)   // <- empty string → nil
        isActive       = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(fullName, forKey: .fullName)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(versionNumber, forKey: .versionNumber)
        try c.encode(dependencies, forKey: .dependencies)
        try c.encode(downloadURL, forKey: .downloadURL)
        try c.encode(downloads, forKey: .downloads)
        try c.encode(dateCreated, forKey: .dateCreated)
        try c.encodeIfPresent(websiteURL, forKey: .websiteURL)
        try c.encode(isActive, forKey: .isActive)
    }
}

// MARK: - Lenient URL decoding helper
//
// Thunderstore returns `""` for unset URL fields (`website_url`, sometimes
// `donation_link`). Swift's stock URL decoder rejects empty strings as
// `dataCorrupted`. This helper falls back to nil whenever the value is
// missing, null, an empty string, or otherwise unparseable.

extension KeyedDecodingContainer {
    func lenientURL(forKey key: Key) throws -> URL? {
        // Try direct URL decode first (handles well-formed inputs fast).
        if let direct = try? decodeIfPresent(URL.self, forKey: key) {
            return direct
        }
        // Fall back to string → URL? conversion. `try?` over a function that
        // returns Optional flattens to a single Optional (SE-0230), so `raw`
        // is `String`, not `String?`.
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}
