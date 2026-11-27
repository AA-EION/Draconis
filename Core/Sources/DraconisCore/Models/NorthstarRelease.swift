import Foundation

/// A Northstar release on GitHub.
public struct NorthstarRelease: Identifiable, Hashable, Codable, Sendable {
    public var id: String { tagName }
    public var tagName: String
    public var name: String
    public var body: String
    public var publishedAt: Date
    public var prerelease: Bool
    public var zipURL: URL
    /// Top-level folder inside the zip (Thunderstore packages wrap Northstar).
    public var zipRoot: String? = nil

    public init(
        tagName: String, name: String, body: String,
        publishedAt: Date, prerelease: Bool, zipURL: URL, zipRoot: String? = nil
    ) {
        self.zipRoot = zipRoot
        self.tagName = tagName
        self.name = name
        self.body = body
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.zipURL = zipURL
    }
}
