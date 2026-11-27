#if os(Linux)
import Foundation
import Testing
@testable import DraconisPlatform

@Suite struct HostProcessesTests {
    // Steam's browser processes have command lines far longer than a page;
    // Foundation returned corrupt data for those and decoding it crashed.
    @Test func longCommandLine() throws {
        let marker = "draconis-marker-\(UUID().uuidString)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 30; true", "sh", String(repeating: "x", count: 70_000), marker]
        try process.run()
        defer { process.terminate() }
        Thread.sleep(forTimeInterval: 0.2)
        #expect(HostProcesses.anyCommandLine(containing: [marker]))
        let bytes = try #require(HostProcesses.procFile(String(process.processIdentifier), "cmdline"))
        #expect(bytes.count > 70_000)
        #expect(!HostProcesses.anyCommandLine(containing: ["draconis-absent-\(UUID().uuidString)"]))
    }
}
#endif
