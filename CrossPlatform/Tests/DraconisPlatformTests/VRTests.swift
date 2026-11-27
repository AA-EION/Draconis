import DraconisCore
import Foundation
import Testing
@testable import DraconisPlatform

@Suite(.serialized) struct VRTests {
    @Test func runtimePlan() {
        #expect(VRRuntimeStatus(steamVRRunning: true, steamVRInstalled: true).plan == .ready)
        #expect(VRRuntimeStatus(steamVRRunning: false, steamVRInstalled: true, otherRunning: "WiVRn").plan == .ready)
        #expect(VRRuntimeStatus(steamVRRunning: false, steamVRInstalled: true).plan == .startSteamVR)
        #expect(VRRuntimeStatus(steamVRRunning: false, steamVRInstalled: true, activeOpenXR: "SteamVR").plan == .startSteamVR)
        #expect(VRRuntimeStatus(steamVRRunning: false, steamVRInstalled: false).plan == .noRuntime)
        #if !os(Windows)
        #expect(VRRuntimeStatus(steamVRRunning: false, steamVRInstalled: true, activeOpenXR: "Monado").plan == .startActive("Monado"))
        #endif
    }

    @Test func launchSteps() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let saved = CorePaths.dataDirectory
        CorePaths.dataDirectory = data
        defer { CorePaths.dataDirectory = saved; try? FileManager.default.removeItem(at: data) }
        let log = LinuxSteamVR.launchLog
        try "[10:00:00] ---- old run\n[10:00:01] EA app signed in.\n".write(to: log, atomically: true, encoding: .utf8)
        let start = LinuxSteamVR.launchLogSize()
        #expect(LinuxSteamVR.launchStep(since: start) == nil)
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("[10:01:00] Starting the EA app...\n".utf8))
        #expect(LinuxSteamVR.launchStep(since: start) == .startingEA)
        try handle.write(contentsOf: Data("[10:01:30] EA app signed in.\n[10:01:32] Launching Titanfall 2 VR from /g\n".utf8))
        #expect(LinuxSteamVR.launchStep(since: start) == .starting)
        try handle.write(contentsOf: Data("[10:01:33] ERROR: Steam didn't run Titanfall 2 with Proton (x)\n".utf8))
        try handle.close()
        #expect(LinuxSteamVR.launchStep(since: start) == .failed("Steam didn't run Titanfall 2 with Proton (x)"))
    }
}
