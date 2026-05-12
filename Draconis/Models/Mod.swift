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
}
