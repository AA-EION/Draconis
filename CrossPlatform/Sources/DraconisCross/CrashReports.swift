import DraconisCore
import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Turns on Swift's backtracer when the packages ship it next to the binary,
/// so a crash leaves a report in Logs/crashes. The runtime reads
/// SWIFT_BACKTRACE only at startup, hence the re-exec.
enum CrashReports {
    static var folder: URL { CorePaths.logs.appendingPathComponent("crashes", isDirectory: true) }

    static func enable() {
        #if os(Linux)
        guard ProcessInfo.processInfo.environment["SWIFT_BACKTRACE"] == nil,
              let exe = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")
        else { return }
        let backtracer = URL(fileURLWithPath: exe).deletingLastPathComponent().appendingPathComponent("swift-backtrace-static")
        guard FileManager.default.isExecutableFile(atPath: backtracer.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        setenv("SWIFT_BACKTRACE", "enable=yes,interactive=no,swift-backtrace=\(backtracer.path),output-to=\(folder.path)", 1)
        execv("/proc/self/exe", CommandLine.unsafeArgv)
        #endif
    }

    /// Reports from earlier runs, newest first.
    static func previous() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }
}
