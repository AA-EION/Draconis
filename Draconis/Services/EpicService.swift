import Foundation

/// Titanfall 2 bought on the Epic Games Store is an EA-app-managed title: Epic
/// never ships the files. The EA app downloads and runs the game; Epic only
/// vouches for ownership through a one-time exchange code passed in a
/// `link2ea://` URL. legendary (GPL-3, the same CLI Heroic uses) signs in to
/// Epic and produces that URL, so no Epic Games Launcher is needed.
public actor EpicService {
    public static let shared = EpicService()

    /// Epic's internal name for Titanfall 2.
    public static let titanfallAppName = "creamhorn"
    public static let loginURL = URL(string: "https://legendary.gl/epiclogin")!

    struct Binary: Sendable {
        let url: URL
        let sha256: String
    }

    static let binary: Binary = WineEngine.isAppleSilicon
        ? Binary(url: URL(string: "https://github.com/legendary-gl/legendary/releases/download/0.21.1/legendary_macOS_arm64")!,
                 sha256: "d87978321dba9cb731fab40c72f0a30bed55baca8b5341ab21024c5733cd837e")
        : Binary(url: URL(string: "https://github.com/legendary-gl/legendary/releases/download/0.21.1/legendary_macOS_x64")!,
                 sha256: "3dfab50277284b5bb0104f8710e4ff1d9ff00c992e44f5843fd0c977c5cc99c4")

    public enum EpicError: Error, LocalizedError {
        case download
        case failed(String)
        case notSignedIn

        public var errorDescription: String? {
            switch self {
            case .download:          return "Couldn't download legendary (the Epic sign-in tool)."
            case .failed(let s):     return "Epic: \(s)"
            case .notSignedIn:       return "Sign in to Epic Games first."
            }
        }
    }

    static var toolURL: URL {
        PathResolver.draconisSupport.appendingPathComponent("Tools/legendary")
    }

    /// legendary's own data (Epic tokens, metadata) stays inside Draconis's folder.
    static var configURL: URL {
        PathResolver.draconisSupport.appendingPathComponent("Epic", isDirectory: true)
    }

    private func ensureTool() async throws -> URL {
        let tool = Self.toolURL
        if FileManager.default.isExecutableFile(atPath: tool.path),
           (try? WineEngine.sha256(of: tool)) == Self.binary.sha256 {
            return tool
        }
        try FileManager.default.createDirectory(
            at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let (tmp, response) = try? await URLSession.shared.download(from: Self.binary.url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { throw EpicError.download }
        try? FileManager.default.removeItem(at: tool)
        try FileManager.default.moveItem(at: tmp, to: tool)
        guard try WineEngine.sha256(of: tool) == Self.binary.sha256 else {
            try? FileManager.default.removeItem(at: tool)
            throw EpicError.download
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        // Apple Silicon only runs signed code; an ad-hoc signature is enough.
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", tool.path]
        _ = try? await ProcessRunner.runUntilExit(sign)
        return tool
    }

    private func legendary(_ arguments: [String]) async throws -> ProcessRunner.Result {
        let tool = try await ensureTool()
        try FileManager.default.createDirectory(at: Self.configURL, withIntermediateDirectories: true)
        Log.run("epic", "legendary \(arguments.first ?? "")")
        return try await ProcessRunner.shared.capture(
            tool, arguments: arguments, environment: ["LEGENDARY_CONFIG_PATH": Self.configURL.path])
    }

    /// The signed-in Epic account name, or nil.
    public func account() async -> String? {
        guard let result = try? await legendary(["status", "--json", "--offline"]), result.ok,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["account"] as? String, name != "<not logged in>"
        else { return nil }
        return name
    }

    /// Finish the browser sign-in: the user pastes the `authorizationCode` (or
    /// the whole JSON) shown after logging in at `loginURL`.
    public func signIn(code raw: String) async throws -> String {
        var code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.hasPrefix("{"), let data = code.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = json["authorizationCode"] as? String {
            code = value
        }
        code = code.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let result = try await legendary(["auth", "--code", code])
        guard result.ok, let name = await account() else {
            throw EpicError.failed(Self.lastLine(result.stderr) ?? "sign-in failed")
        }
        return name
    }

    public func signOut() async {
        _ = try? await legendary(["auth", "--delete"])
    }

    /// Hand Titanfall 2 to the bottle's EA app with a fresh Epic exchange code.
    /// The EA app links the accounts, installs the game if needed, and runs it.
    public func openInEAApp(bottle: WineBottle) async throws {
        guard await account() != nil else { throw EpicError.notSignedIn }
        // Third-party titles' metadata is only fetched by this listing.
        _ = try? await legendary(["list", "--third-party", "--json"])
        let result = try await legendary(["launch", Self.titanfallAppName, "--origin", "--json"])
        guard result.ok, let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uri = json["uri"] as? String, uri.hasPrefix("link2ea://")
        else {
            throw EpicError.failed(Self.lastLine(result.stderr) ?? "couldn't get a launch link from Epic")
        }
        try await WineBackendManager.shared.open(url: uri, in: bottle)
    }

    private static func lastLine(_ text: String) -> String? {
        text.split(separator: "\n").last.map(String.init)
    }
}
