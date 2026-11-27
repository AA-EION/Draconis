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

    // Viper only checks common/Titanfall2, so copies without a manifest must count too.
    @Test(.enabled(if: !isWindows)) func findsTitanfallWithoutManifestInFlatpakSteam() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = home.appendingPathComponent(".var/app/com.valvesoftware.Steam/.steam/steam")
        let game = root.appendingPathComponent("steamapps/common/Titanfall2")
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        fm.createFile(atPath: game.appendingPathComponent("Titanfall2.exe").path, contents: Data())

        let installs = SteamLocator.installs(home: home, environment: [:])
        #expect(installs.map(\.kind) == [.flatpak])
        let found = try #require(SteamLocator.titanfall(in: installs))
        #expect(found.1.resolvingSymlinksInPath().path == game.resolvingSymlinksInPath().path)
    }
}


@Suite struct SteamLaunchOptionsTests {
    @Test func addsOverrideOnce() {
        let o = SteamLaunchOptions.override
        #expect(SteamLaunchOptions.withNorthstarOverride("") == "\(o) %command%")
        #expect(SteamLaunchOptions.withNorthstarOverride("-novid") == "\(o) %command% -novid")
        #expect(SteamLaunchOptions.withNorthstarOverride("gamemoderun %command% -novid") == "\(o) gamemoderun %command% -novid")
        #expect(SteamLaunchOptions.withNorthstarOverride("\(o) %command%") == nil)
    }

    @Test func writesLocalConfigKeepingEverythingElse() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent("userdata/12345/config")
        try fm.createDirectory(at: config, withIntermediateDirectories: true)
        let file = config.appendingPathComponent("localconfig.vdf")
        try """
        "UserLocalConfigStore"
        {
        \t"friends" { "PersonaName" "a \\"quoted\\" name" }
        \t"Software" { "Valve" { "Steam" { "apps" {
        \t\t"1237970" { "LastPlayed" "1700000000" "LaunchOptions" "-novid" }
        \t\t"440" { "LaunchOptions" "-x" }
        \t} } } }
        }
        """.write(to: file, atomically: true, encoding: .utf8)
        let install = SteamInstall(root: root, kind: .native)
        #expect(install.configsNeedingNorthstarOverride(appID: "1237970").count == 1)
        #expect(try install.addNorthstarOverride(appID: "1237970") == 1)
        let vdf = try #require(VDF.load(file))
        let apps = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"]
        #expect(vdf[apps + ["1237970", "LaunchOptions"]]?.string == "\(SteamLaunchOptions.override) %command% -novid")
        #expect(vdf[apps + ["1237970", "LastPlayed"]]?.string == "1700000000")
        #expect(vdf[apps + ["440", "LaunchOptions"]]?.string == "-x")
        #expect(vdf[["UserLocalConfigStore", "friends", "PersonaName"]]?.string == "a \"quoted\" name")
        #expect(install.configsNeedingNorthstarOverride(appID: "1237970").isEmpty)
        #expect(fm.fileExists(atPath: file.path + ".draconis-backup"))
    }

    @Test func createsMissingAppEntry() throws {
        var vdf = try #require(VDF.parse(#""UserLocalConfigStore" { "Software" { } }"#))
        vdf.set(["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", "1237970", "LaunchOptions"], "x")
        let again = try #require(VDF.parse(vdf.serialized()))
        #expect(again[["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", "1237970", "LaunchOptions"]]?.string == "x")
    }
}

#if os(Windows)
let isWindows = true
#else
let isWindows = false
#endif
