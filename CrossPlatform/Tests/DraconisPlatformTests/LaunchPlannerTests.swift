import DraconisCore
import Foundation
import Testing
@testable import DraconisPlatform

@Suite struct LaunchPlannerTests {
    func game(northstar: Bool, source: GameInstall.Source) throws -> GameInstall {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("Titanfall2.exe").path, contents: Data())
        if northstar {
            FileManager.default.createFile(atPath: root.appendingPathComponent("NorthstarLauncher.exe").path, contents: Data())
        }
        return GameInstall(root: root, source: source)
    }

    @Test func steamNorthstarPutsFlagLast() throws {
        let g = try game(northstar: true, source: .steam(root: URL(fileURLWithPath: "/s"), kind: "native", compatTool: "GE-Proton11-14"))
        let cmd = try LaunchPlanner.plan(game: g, mode: .northstar, steamCommand: ["/usr/bin/steam"])
        #expect(cmd.executable == "/usr/bin/steam")
        #expect(cmd.arguments == ["-applaunch", "1237970", "-northstar"])
        let vanilla = try LaunchPlanner.plan(game: g, mode: .vanilla, steamCommand: ["/usr/bin/flatpak", "run", "com.valvesoftware.Steam"])
        #expect(vanilla.arguments == ["run", "com.valvesoftware.Steam", "-applaunch", "1237970", "-vanilla", "-northstar"])
    }

    @Test func steamWithoutNorthstar() throws {
        let g = try game(northstar: false, source: .steam(root: URL(fileURLWithPath: "/s"), kind: "native", compatTool: nil))
        #expect(throws: LaunchPlanner.PlanError.northstarMissing) {
            try LaunchPlanner.plan(game: g, mode: .northstar, steamCommand: ["steam"])
        }
        #expect(try LaunchPlanner.plan(game: g, mode: .vanilla, steamCommand: ["steam"]).arguments == ["-applaunch", "1237970"])
    }

    @Test func prefixWithProtonUsesUmu() throws {
        let prefix = URL(fileURLWithPath: "/data/Prefixes/TF2")
        let g = try game(northstar: true, source: .prefix(prefix, origin: "Draconis"))
        let runner = Runner(kind: .proton, name: "GE-Proton11-14", path: URL(fileURLWithPath: "/p/GE-Proton11-14"), source: "Steam")
        let cmd = try LaunchPlanner.plan(game: g, mode: .northstar, runner: runner, umuRun: URL(fileURLWithPath: "/usr/bin/umu-run"))
        #expect(cmd.executable == "/usr/bin/umu-run")
        #expect(cmd.arguments == [g.root.appendingPathComponent("NorthstarLauncher.exe").path, "-noOriginStartup"])
        #expect(cmd.environment["GAMEID"] == "umu-1237970")
        #expect(cmd.environment["WINEPREFIX"] == prefix.path)
        #expect(cmd.environment["PROTONPATH"] == "/p/GE-Proton11-14")
        #expect(cmd.environment["WINEDLLOVERRIDES"] == "wsock32=n,b")
        #expect(cmd.workingDirectory == g.root)
    }

    @Test func prefixWithWine() throws {
        let g = try game(northstar: true, source: .prefix(URL(fileURLWithPath: "/pfx"), origin: "Custom"))
        let runner = Runner(kind: .wine, name: "wine", path: URL(fileURLWithPath: "/opt/wine"), source: "System")
        let cmd = try LaunchPlanner.plan(game: g, mode: .vanilla, runner: runner)
        #expect(cmd.executable == "/opt/wine/bin/wine")
        #expect(cmd.arguments.suffix(2) == ["-noOriginStartup", "-vanilla"])
        #expect(cmd.environment["WINEDLLOVERRIDES"] == "winemenubuilder.exe=d;wsock32=n,b")
    }

    @Test func prefixNeedsRunnerAndUmu() throws {
        let g = try game(northstar: true, source: .prefix(URL(fileURLWithPath: "/pfx"), origin: "Custom"))
        #expect(throws: LaunchPlanner.PlanError.noRunner) { try LaunchPlanner.plan(game: g, mode: .northstar) }
        let proton = Runner(kind: .proton, name: "Proton", path: URL(fileURLWithPath: "/p"), source: "Steam")
        #expect(throws: LaunchPlanner.PlanError.noUmu) { try LaunchPlanner.plan(game: g, mode: .northstar, runner: proton) }
    }

    @Test func northstarOptOutIsCleared() throws {
        let g = try game(northstar: true, source: .native(origin: "Custom"))
        let file = g.root.appendingPathComponent("run_northstar.txt")
        try "0".write(to: file, atomically: true, encoding: .utf8)
        LaunchPlanner.prepareFiles(game: g, mode: .northstar)
        #expect(try String(contentsOf: file, encoding: .utf8) == "1")
    }


    @Test func prefixDetection() {
        let folder = URL(fileURLWithPath: "/home/u/Games/pfx/drive_c/Program Files/EA Games/Titanfall2")
        #expect(GameInstall.prefix(containing: folder)?.path == "/home/u/Games/pfx")
        #expect(GameInstall.prefix(containing: URL(fileURLWithPath: "/mnt/Titanfall2")) == nil)
    }

    @Test func prefixStoreRefusesOutsidePaths() {
        #expect(throws: PrefixStore.InvalidPrefix.self) {
            try PrefixStore.validatedForCreation(URL(fileURLWithPath: "/home/u/.wine"))
        }
        #expect((try? PrefixStore.validatedForCreation(PrefixStore.url(named: "TF2"))) != nil)
    }
}
