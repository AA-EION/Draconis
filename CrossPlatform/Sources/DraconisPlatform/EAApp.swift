import DraconisCore
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The EA app inside a Wine prefix: Titanfall 2's sign-in.
public enum EAApp {
    public static let lsxPort: UInt16 = 3216
    public static let installerURL = URL(string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe")!

    public static func executable(inPrefix prefix: URL) -> URL? {
        let driveC = prefix.appendingPathComponent("drive_c")
        for rel in ["Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe",
                    "Program Files (x86)/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe",
                    "Program Files/Electronic Arts/EA Desktop/EA Desktop.exe",
                    "Program Files (x86)/Electronic Arts/EA Desktop/EA Desktop.exe"] {
            let url = driveC.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// EA's local service that Titanfall 2 and Northstar authenticate through.
    public static func isLSXListening() -> Bool {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = lsxPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        #else
        return false
        #endif
    }
}

/// Processes on this machine, also from inside the Flatpak sandbox
/// (Draconis doesn't own the game: Steam or Proton spawns it).
public enum HostProcesses {
    /// Does any process's command line contain one of these names?
    public static func anyCommandLine(containing names: [String]) -> Bool {
        #if os(Linux)
        if Spawner.inFlatpak {
            let out = (try? Spawner.capture("/usr/bin/flatpak-spawn", ["--host", "ps", "-eo", "args"])) ?? ""
            return names.contains { out.contains($0) }
        }
        for pid in pids() {
            guard let bytes = procFile(pid, "cmdline") else { continue }
            let line = String(decoding: bytes, as: UTF8.self)
            if names.contains(where: line.contains) { return true }
        }
        return false
        #else
        return false
        #endif
    }

    /// Is a process with exactly this name (`comm`) running?
    public static func named(_ name: String) -> Bool {
        #if os(Linux)
        if Spawner.inFlatpak {
            let out = (try? Spawner.capture("/usr/bin/flatpak-spawn", ["--host", "ps", "-eo", "comm"])) ?? ""
            return out.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == name }
        }
        for pid in pids() {
            guard let bytes = procFile(pid, "comm") else { continue }
            if String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == name { return true }
        }
        return false
        #else
        return false
        #endif
    }

    #if os(Linux)
    static func pids() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/proc")) ?? []).filter { $0.allSatisfy(\.isNumber) }
    }

    /// Foundation's file reading returns corrupt Data for long /proc files
    /// (size 0 in stat), and decoding it crashes; read them with read(2).
    static func procFile(_ pid: String, _ name: String) -> [UInt8]? {
        let fd = open("/proc/\(pid)/\(name)", O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 16384)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return n == 0 ? bytes : nil }
            bytes.append(contentsOf: chunk[0..<n])
        }
    }
    #endif
}

/// Is the game running? Steam starts `Titanfall2.exe`; prefix launches run
/// `NorthstarLauncher.exe`, which loads the game in its own process.
public enum GameProcess {
    public static func isRunning() -> Bool {
        #if os(Windows)
        for exe in ["Titanfall2.exe", "NorthstarLauncher.exe", "Titanfall2VRLauncher.exe"] {
            let out = (try? Spawner.capture(#"C:\Windows\System32\tasklist.exe"#, ["/FI", "IMAGENAME eq \(exe)", "/NH"])) ?? ""
            if out.contains(exe) { return true }
        }
        return false
        #else
        return HostProcesses.anyCommandLine(containing: ["Titanfall2.exe", "NorthstarLauncher.exe", "Titanfall2VRLauncher.exe"])
        #endif
    }
}

/// The Steam client, so its config can be edited while it's closed.
public enum SteamClient {
    public static func isRunning() -> Bool { HostProcesses.named("steam") }

    /// Ask Steam to quit and wait for it; false if it's still running.
    public static func shutdown(kind: String) async -> Bool {
        guard isRunning() else { return true }
        guard let steam = LaunchPlanner.steamCommand(kind: kind) else { return false }
        try? Spawner.launch(steam[0], Array(steam.dropFirst()) + ["-shutdown"], environment: [:])
        for _ in 0..<45 {
            try? await Task.sleep(for: .seconds(1))
            if !isRunning() { return true }
        }
        return !isRunning()
    }
}
