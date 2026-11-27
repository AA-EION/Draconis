import Foundation
import Testing
@testable import DraconisCore

@Suite struct SteamTests {
    @Test func parsesLibraryFolders() throws {
        let text = """
        // comment
        "libraryfolders"
        {
            "0" { "path" "/home/u/.local/share/Steam" "apps" { "228980" "1" } }
            "1" { "path" "/mnt/games/SteamLibrary" "mounted" "0" }
        }
        """
        let vdf = try #require(VDF.parse(text))
        #expect(vdf[["libraryfolders", "0", "path"]]?.string == "/home/u/.local/share/Steam")
        #expect(vdf[["LibraryFolders", "1", "Mounted"]]?.string == "0")
        #expect(VDF.parse("\"a\" { \"b\" ") == nil)
    }

    // Steam roots on Windows come from the registry, not the home folder.
    @Test(.enabled(if: !isWindows)) func findsTitanfallAndCompatTool() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = home.appendingPathComponent(".local/share/Steam")
        let lib2 = home.appendingPathComponent("Games/SteamLibrary")
        try fm.createDirectory(at: root.appendingPathComponent("steamapps"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        let game = lib2.appendingPathComponent("steamapps/common/Titanfall2")
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        fm.createFile(atPath: game.appendingPathComponent("Titanfall2.exe").path, contents: Data())
        try """
        "libraryfolders" { "0" { "path" "\(root.path)" } "1" { "path" "\(lib2.path)" } }
        """.write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"), atomically: true, encoding: .utf8)
        try """
        "AppState" { "appid" "1237970" "installdir" "Titanfall2" "StateFlags" "4" }
        """.write(to: lib2.appendingPathComponent("steamapps/appmanifest_1237970.acf"), atomically: true, encoding: .utf8)
        try """
        "InstallConfigStore" { "Software" { "Valve" { "Steam" { "CompatToolMapping" {
            "0" { "name" "proton_experimental" }
            "1237970" { "name" "GE-Proton11-14" "config" "" "priority" "250" }
        } } } } }
        """.write(to: root.appendingPathComponent("config/config.vdf"), atomically: true, encoding: .utf8)

        let installs = SteamLocator.installs(home: home, environment: [:])
        #expect(installs.count == 1)
        let found = try #require(SteamLocator.titanfall(in: installs))
        #expect(found.1.resolvingSymlinksInPath().path == game.resolvingSymlinksInPath().path)
        #expect(found.0.compatTool(appID: "1237970") == "GE-Proton11-14")
    }
}

#if os(Windows)
let isWindows = true
#else
let isWindows = false
#endif
