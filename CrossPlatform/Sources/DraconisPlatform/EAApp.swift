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

/// Is the game running? (Draconis doesn't own the game process: Steam or
/// Proton spawns it.)
public enum GameProcess {
    public static func isRunning() -> Bool {
        #if os(Linux)
        let fm = FileManager.default
        for pid in (try? fm.contentsOfDirectory(atPath: "/proc")) ?? [] where pid.allSatisfy(\.isNumber) {
            guard let data = fm.contents(atPath: "/proc/\(pid)/cmdline") else { continue }
            if String(decoding: data, as: UTF8.self).contains("Titanfall2.exe") { return true }
        }
        return false
        #elseif os(Windows)
        let out = (try? Spawner.capture(#"C:\Windows\System32\tasklist.exe"#, ["/FI", "IMAGENAME eq Titanfall2.exe", "/NH"])) ?? ""
        return out.contains("Titanfall2.exe")
        #else
        return false
        #endif
    }
}
