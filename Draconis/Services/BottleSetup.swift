import Foundation

/// Installs the dependencies CrossOver's "Game Launcher Dependencies" set puts
/// into a Titanfall 2 bottle (the Steam / EA app profiles depend on it): the
/// latest Visual C++ runtime and d3dcompiler_47. Works on CrossOver bottles
/// and Draconis prefixes alike.
public actor BottleSetup {
    public static let shared = BottleSetup()

    struct Redist: Sendable {
        let url: URL
        let file: String
    }

    static let vcRedists = [
        Redist(url: URL(string: "https://aka.ms/vc14/vc_redist.x64.exe")!, file: "vc_redist.x64.exe"),
        Redist(url: URL(string: "https://aka.ms/vc14/vc_redist.x86.exe")!, file: "vc_redist.x86.exe"),
    ]

    struct PinnedFile: Sendable {
        let url: URL
        let sha256: String
        let destination: String // relative to drive_c/windows
    }

    // mozilla/fxc2, the same source CrossOver's profile downloads from, pinned to a commit.
    static let d3dcompiler = [
        PinnedFile(
            url: URL(string: "https://raw.githubusercontent.com/mozilla/fxc2/807d26f4e4e9e9d0d0d6c1e05493b28eafb20e91/dll/d3dcompiler_47.dll")!,
            sha256: "4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3",
            destination: "system32/d3dcompiler_47.dll"),
        PinnedFile(
            url: URL(string: "https://raw.githubusercontent.com/mozilla/fxc2/807d26f4e4e9e9d0d0d6c1e05493b28eafb20e91/dll/d3dcompiler_47_32.dll")!,
            sha256: "2ad0d4987fc4624566b190e747c9d95038443956ed816abfd1e2d389b5ec0851",
            destination: "syswow64/d3dcompiler_47.dll"),
    ]

    public enum SetupError: Error, LocalizedError {
        case download(String)
        case installer(String, Int32)

        public var errorDescription: String? {
            switch self {
            case .download(let f):        return "Couldn't download \(f)."
            case .installer(let f, let c): return "\(f) failed (exit \(c))."
            }
        }
    }

    /// Marker so a bottle is only prepared once.
    private static func markerURL(for bottle: WineBottle) -> URL {
        PathResolver.driveC(in: bottle.prefixURL).appendingPathComponent(".draconis-deps")
    }

    public nonisolated static func isPrepared(_ bottle: WineBottle) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(for: bottle).path)
    }

    public func prepare(_ bottle: WineBottle) async throws {
        if Self.isPrepared(bottle) { return }

        for redist in Self.vcRedists {
            let exe = try await download(redist.url, as: redist.file)
            Log.info("bottle.setup", "Installing \(redist.file)…")
            let status = try await WineBackendManager.shared.launchAndWait(
                executable: exe.path,
                arguments: ["/install", "/quiet", "/norestart"],
                in: bottle
            )
            // 1638: a newer version is already installed; 3010: reboot requested.
            guard [0, 1638, 3010].contains(status) else {
                throw SetupError.installer(redist.file, status)
            }
        }

        let windows = PathResolver.driveC(in: bottle.prefixURL).appendingPathComponent("windows")
        for file in Self.d3dcompiler {
            let dll = try await download(file.url, as: file.url.lastPathComponent, sha256: file.sha256)
            let dest = windows.appendingPathComponent(file.destination)
            guard FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path) else { continue }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: dll, to: dest)
        }

        FileManager.default.createFile(atPath: Self.markerURL(for: bottle).path, contents: Data())
        Log.ok("bottle.setup", "Dependencies installed in “\(bottle.name)”")
    }

    private func download(_ url: URL, as name: String, sha256: String? = nil) async throws -> URL {
        let dest = PathResolver.downloadsCache.appendingPathComponent(name)
        if let sha256, FileManager.default.fileExists(atPath: dest.path),
           (try? WineEngine.sha256(of: dest)) == sha256 {
            return dest
        }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SetupError.download(name) }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch let error as SetupError {
            throw error
        } catch {
            throw SetupError.download(name)
        }
        if let sha256, try WineEngine.sha256(of: dest) != sha256 {
            try? FileManager.default.removeItem(at: dest)
            throw SetupError.download(name)
        }
        return dest
    }
}
