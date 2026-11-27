import DraconisCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Which VR runtime is up, so Draconis can tell the player what to start.
public struct VRRuntimeStatus: Equatable, Sendable {
    public var steamVRRunning: Bool
    public var steamVRInstalled: Bool
    /// Another OpenXR runtime that's running: WiVRn or Monado (Linux).
    public var otherRunning: String?
    /// The system's active OpenXR runtime, by name.
    public var activeOpenXR: String?

    public var anyRunning: Bool { steamVRRunning || otherRunning != nil }

    public static let steamVRAppID = "250820"

    public static func detect(steam: SteamInstall?) -> VRRuntimeStatus {
        let installed = steam.map { install in
            install.libraries().contains {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent("steamapps/appmanifest_\(steamVRAppID).acf").path)
            }
        } ?? false
        #if os(Windows)
        let running = isRunningOnWindows("vrserver.exe")
        let json = WindowsRegistry.string(.localMachine, #"SOFTWARE\Khronos\OpenXR\1"#, "ActiveRuntime")
        return VRRuntimeStatus(steamVRRunning: running, steamVRInstalled: installed, otherRunning: nil,
                               activeOpenXR: json.flatMap { runtimeName(URL(fileURLWithPath: $0)) })
        #else
        let other = HostProcesses.named("wivrn-server") ? "WiVRn" : HostProcesses.named("monado-service") ? "Monado" : nil
        let home = CorePaths.home
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        let active = [config.appendingPathComponent("openxr/1/active_runtime.json"),
                      URL(fileURLWithPath: "/etc/xdg/openxr/1/active_runtime.json")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
        return VRRuntimeStatus(steamVRRunning: HostProcesses.anyCommandLine(containing: ["vrserver", "vrcompositor"]),
                               steamVRInstalled: installed, otherRunning: other,
                               activeOpenXR: active.flatMap(runtimeName))
        #endif
    }

    static func runtimeName(_ json: URL) -> String? {
        guard let data = try? Data(contentsOf: json),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtime = object["runtime"] as? [String: Any] else { return nil }
        if let name = runtime["name"] as? String, !name.isEmpty { return name }
        let library = (runtime["library_path"] as? String ?? "").lowercased()
        if library.contains("steamvr") || library.contains("vrclient") { return "SteamVR" }
        if library.contains("wivrn") { return "WiVRn" }
        if library.contains("monado") { return "Monado" }
        if library.contains("oculus") { return "Meta Quest Link" }
        if library.contains("virtualdesktop") { return "Virtual Desktop" }
        return json.deletingPathExtension().lastPathComponent
    }

    #if os(Windows)
    static func isRunningOnWindows(_ exe: String) -> Bool {
        let out = (try? Spawner.capture(#"C:\Windows\System32\tasklist.exe"#, ["/FI", "IMAGENAME eq \(exe)", "/NH"])) ?? ""
        return out.localizedCaseInsensitiveContains(exe)
    }
    #endif
}

/// The VR mod needs Microsoft's VC++ runtime 14.40+; Proton prefixes often
/// hold an older copy from the EA app or Wine's builtin one. The DLLs are
/// unpacked from vc_redist.x64.exe (no Windows program runs), the way
/// TF2SteamFrame and winetricks do it.
public enum VCRuntime {
    public static let redistURL = URL(string: "https://aka.ms/vs/17/release/vc_redist.x64.exe")!
    public static let dlls = ["concrt140", "msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait",
                              "msvcp140_codecvt_ids", "vcruntime140", "vcruntime140_1"]
    static var cache: URL { CorePaths.directory("VR").appendingPathComponent("vcrt", isDirectory: true) }

    /// File version of Microsoft's msvcp140.dll; nil for Wine's builtin copy.
    public static func version(of dll: URL) -> [Int]? {
        guard let data = try? Data(contentsOf: dll) else { return nil }
        let bytes = [UInt8](data)
        if let head = String(data: data.prefix(0x100), encoding: .isoLatin1), head.contains("Wine builtin DLL") { return nil }
        let key = Array("VS_VERSION_INFO".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        guard let i = LoopbackPatch.find(bytes, key, from: 0),
              let j = LoopbackPatch.find(bytes, [0xBD, 0x04, 0xEF, 0xFE], from: i), j + 16 <= bytes.count else { return nil }
        let ms = LoopbackPatch.u32(bytes, j + 8), ls = LoopbackPatch.u32(bytes, j + 12)
        return [Int(ms >> 16), Int(ms & 0xFFFF), Int(ls >> 16), Int(ls & 0xFFFF)]
    }

    static func newEnough(_ version: [Int]?) -> Bool {
        guard let version else { return false }
        return version.lexicographicallyPrecedes([14, 40]) == false
    }

    /// Make sure the prefix's system32 has a new enough runtime.
    public static func ensure(prefix: URL) async throws {
        let system32 = prefix.appendingPathComponent("drive_c/windows/system32")
        if newEnough(version(of: system32.appendingPathComponent("msvcp140.dll"))) { return }
        if !newEnough(version(of: cache.appendingPathComponent("msvcp140.dll"))) { try await unpack() }
        for dll in dlls {
            let source = cache.appendingPathComponent("\(dll).dll")
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let target = system32.appendingPathComponent("\(dll).dll")
            try? FileManager.default.removeItem(at: target) // may be a link to Proton's own copy
            try FileManager.default.copyItem(at: source, to: target)
        }
        Log.ok("vr", "VC++ runtime \(version(of: cache.appendingPathComponent("msvcp140.dll"))?.map(String.init).joined(separator: ".") ?? "") copied into the prefix")
    }

    static func unpack() async throws {
        let fm = FileManager.default
        let exe = CorePaths.downloads.appendingPathComponent("vc_redist.x64.exe")
        try? fm.removeItem(at: exe)
        try fm.moveItem(at: try await DownloadCoordinator.download(from: redistURL), to: exe)
        let work = CorePaths.directory("VR").appendingPathComponent("vcredist-work", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let payload = work.appendingPathComponent("a12")
        if let cab = Executables.find("cabextract") {
            _ = try? await Spawner.status(cab.path, ["-q", "-d", work.path, "-F", "a12", exe.path])
        } else if let tar = Executables.find("bsdtar") {
            // bsdtar only reads the first cabinet of the bundle, so cut each one out first.
            let bytes = [UInt8](try Data(contentsOf: exe))
            var start = 0, n = 0
            while let i = LoopbackPatch.find(bytes, Array("MSCF".utf8) + [0, 0, 0, 0], from: start), i + 12 <= bytes.count {
                let size = Int(LoopbackPatch.u32(bytes, i + 8))
                if size > 0, i + size <= bytes.count {
                    let cab = work.appendingPathComponent("bundle\(n).cab")
                    try Data(bytes[i..<i + size]).write(to: cab)
                    n += 1
                    _ = try? await Spawner.status(tar.path, ["-xf", cab.path, "-C", work.path, "a12"])
                    if fm.fileExists(atPath: payload.path) { break }
                }
                start = i + 4
            }
        } else {
            throw LaunchFailureMessage("Titanfall 2 VR needs a newer VC++ runtime in the game's prefix. Install cabextract (or bsdtar) with your package manager and try again.")
        }
        guard fm.fileExists(atPath: payload.path) else { throw LaunchFailureMessage("Couldn't unpack vc_redist.x64.exe.") }
        if let cab = Executables.find("cabextract") {
            _ = try? await Spawner.status(cab.path, ["-q", "-d", work.path, payload.path])
        } else if let tar = Executables.find("bsdtar") {
            _ = try? await Spawner.status(tar.path, ["-xf", payload.path, "-C", work.path])
        }
        try? fm.removeItem(at: cache)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        for dll in dlls where fm.fileExists(atPath: work.appendingPathComponent("\(dll).dll_amd64").path) {
            try fm.copyItem(at: work.appendingPathComponent("\(dll).dll_amd64"), to: cache.appendingPathComponent("\(dll).dll"))
        }
        guard newEnough(version(of: cache.appendingPathComponent("msvcp140.dll"))) else {
            throw LaunchFailureMessage("The VC++ runtime from Microsoft is older than 14.40; Titanfall 2 VR needs 14.40 or newer.")
        }
    }
}

public struct LaunchFailureMessage: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The Linux side of Titanfall 2 VR for Steam copies: the launch wrapper and
/// the Steam-driven asset build.
public enum LinuxSteamVR {
    public static var state: URL { CorePaths.directory("VR") }
    public static var wrapper: URL { CorePaths.directory("bin").appendingPathComponent("draconis-steam-launch") }
    public static let launchFlag = "-draconis-vr", setupFlag = "-draconis-vr-setup"

    /// Copy the wrapper out of the app bundle (it moves with each update).
    public static func installWrapper(from bundled: URL) throws {
        let fm = FileManager.default
        if let current = try? Data(contentsOf: wrapper), current == (try? Data(contentsOf: bundled)) { return }
        try? fm.removeItem(at: wrapper)
        try fm.copyItem(at: bundled, to: wrapper)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    }

    static var doneMarker: URL { state.appendingPathComponent("asset_patcher.done") }
    static var patcherLog: URL { state.appendingPathComponent("asset_patcher.log") }

    public static func clearAssetBuild() { try? FileManager.default.removeItem(at: doneMarker) }

    /// Exit code once the Steam-run asset build has finished.
    public static func assetBuildResult() -> Int32? {
        guard let text = try? String(contentsOf: doneMarker, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Last "progress <done> <total>" line asset_patcher.exe printed.
    public static func assetBuildProgress() -> Double? {
        guard let text = try? String(contentsOf: patcherLog, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let parts = line.split(separator: " ")
            if parts.count == 3, parts[0] == "progress", let done = Double(parts[1]), let total = Double(parts[2]), total > 0 {
                return done / total
            }
        }
        return nil
    }

    public static func assetBuildLogTail() -> String {
        let text = (try? String(contentsOf: patcherLog, encoding: .utf8)) ?? ""
        return text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("progress ") }.suffix(3).joined(separator: " ")
    }

    /// The wrapper reads the VR launcher's arguments from here.
    public static func writeLaunchArguments(gameRoot: URL) throws {
        let args = try TitanfallVR.launchArguments(gameRoot: gameRoot)
        try (args.joined(separator: "\n") + "\n")
            .write(to: gameRoot.appendingPathComponent("\(TitanfallVR.profile)/tools/draconis-launch-args.txt"), atomically: true, encoding: .utf8)
    }
}

/// Windows: the asset build and the VR launch run directly.
public enum WindowsVR {
    /// Run asset_patcher.exe, reporting its "progress <done> <total>" lines.
    public static func buildAssets(gameRoot: URL, stage: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let process = Process()
        process.executableURL = stage.appendingPathComponent("mod/asset_patcher.exe")
        process.arguments = TitanfallVR.assetPatcherArguments(gameRoot: gameRoot, stage: stage)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let handle = out.fileHandleForReading
        var buffer = Data()
        while case let chunk = handle.availableData, !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<newline], as: UTF8.self)
                buffer.removeSubrange(...newline)
                let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
                if parts.count == 3, parts[0] == "progress", let done = Double(parts[1]), let total = Double(parts[2]), total > 0 {
                    progress(done / total)
                }
            }
        }
        let error = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        await ProcessRunnerShim.wait(process)
        guard process.terminationStatus == 0 else { throw TitanfallVR.VRError.assets(error.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    public static func launch(gameRoot: URL) throws {
        let args = [gameRoot.appendingPathComponent(TitanfallVR.profile).path,
                    gameRoot.appendingPathComponent(TitanfallVR.launcher).path] + (try TitanfallVR.launchArguments(gameRoot: gameRoot))
        let process = Process()
        process.executableURL = gameRoot.appendingPathComponent("\(TitanfallVR.profile)/tools/crash_monitor.exe")
        process.arguments = args
        process.currentDirectoryURL = gameRoot
        process.environment = TitanfallVR.environment(ProcessInfo.processInfo.environment)
        try process.run()
    }
}

enum ProcessRunnerShim {
    /// Wait for a process without blocking the caller's thread.
    static func wait(_ process: Process) async {
        while process.isRunning { try? await Task.sleep(for: .milliseconds(200)) }
    }
}
