import Foundation

/// Describes the state of a Northstar installation inside a given bottle.
public struct NorthstarInstall: Hashable, Codable, Sendable {
    public var bottleID: String
    public var installedVersion: String?
    public var titanfall2Root: URL?            // mapped POSIX path inside the prefix
    public var northstarLauncherURL: URL?      // NorthstarLauncher.exe
    public var modsDirectoryURL: URL?          // R2Northstar/mods

    public var isInstalled: Bool {
        installedVersion != nil && northstarLauncherURL != nil
    }

    public init(
        bottleID: String,
        installedVersion: String? = nil,
        titanfall2Root: URL? = nil,
        northstarLauncherURL: URL? = nil,
        modsDirectoryURL: URL? = nil
    ) {
        self.bottleID = bottleID
        self.installedVersion = installedVersion
        self.titanfall2Root = titanfall2Root
        self.northstarLauncherURL = northstarLauncherURL
        self.modsDirectoryURL = modsDirectoryURL
    }
}

/// A release of NorthstarLauncher available on GitHub.
public struct NorthstarRelease: Identifiable, Hashable, Codable, Sendable {
    public var id: String { tagName }
    public var tagName: String
    public var name: String
    public var body: String
    public var publishedAt: Date
    public var prerelease: Bool
    public var zipURL: URL

    public init(
        tagName: String, name: String, body: String,
        publishedAt: Date, prerelease: Bool, zipURL: URL
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.zipURL = zipURL
    }
}
