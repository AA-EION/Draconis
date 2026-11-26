import Foundation
import Testing
import ZIPFoundation
@testable import DraconisCore

@Suite struct CoreTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeZip(_ files: [String: String], at url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, body) in files {
            let data = Data(body.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { pos, size in
                data.subdata(in: Int(pos)..<Int(pos) + size)
            }
        }
    }

    @Test func extractOverwritesExistingFiles() throws {
        let dir = try tempDir()
        let zip = dir.appendingPathComponent("ns.zip")
        try makeZip(["ns_version.txt": "1.30.0", "R2Northstar/mods/A/mod.json": "{}"], at: zip)
        let game = dir.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try "1.29.0".write(to: game.appendingPathComponent("ns_version.txt"), atomically: true, encoding: .utf8)

        try ZipExtractor.extract(zip, to: game)
        #expect(GameFiles.northstarVersion(in: game) == "1.30.0")
        #expect(FileManager.default.fileExists(atPath: game.appendingPathComponent("R2Northstar/mods/A/mod.json").path))
    }

    @Test func extractRejectsPathTraversal() throws {
        let dir = try tempDir()
        let zip = dir.appendingPathComponent("evil.zip")
        try makeZip(["../escape.txt": "x"], at: zip)
        #expect(throws: ZipExtractor.ExtractError.self) {
            try ZipExtractor.extract(zip, to: dir.appendingPathComponent("out"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escape.txt").path))
    }

    @Test func manifestFolderName() throws {
        let dir = try tempDir()
        let zip = dir.appendingPathComponent("mod.zip")
        try makeZip(["manifest.json": #"{"name":"Mod","version_number":"1.2.3"}"#], at: zip)
        #expect(ThunderstoreClient.manifestFolderName(in: zip) == "Mod-1.2.3")
    }

    @Test func versionMatching() {
        #expect(GameFiles.versionsMatch(installed: "1.30.0", releaseTag: "v1.30.0"))
        #expect(!GameFiles.versionsMatch(installed: nil, releaseTag: "v1.30.0"))
        #expect(!GameFiles.versionsMatch(installed: "1.29.0", releaseTag: "v1.30.0"))
    }

    @Test func thunderstoreDatesWithFractions() throws {
        struct D: Decodable { let d: Date }
        let json = Data(#"{"d":"2020-08-08T15:25:35.555000Z"}"#.utf8)
        _ = try ThunderstoreClient.makeDecoder().decode(D.self, from: json)
    }

    @Test func installedModsReadsBothLayouts() throws {
        let game = try tempDir()
        FileManager.default.createFile(atPath: game.appendingPathComponent("Titanfall2.exe").path, contents: Data())
        let legacy = game.appendingPathComponent("R2Northstar/mods/Legacy")
        let pkg = game.appendingPathComponent("R2Northstar/packages/Author-Pkg-1.0.0/mods/Modern")
        for dir in [legacy, pkg] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try #"{"Name":"Legacy.Mod","Version":"1.0"}"#.write(to: legacy.appendingPathComponent("mod.json"), atomically: true, encoding: .utf8)
        try #"{"Name":"Modern.Mod","Version":"2.0"}"#.write(to: pkg.appendingPathComponent("mod.json"), atomically: true, encoding: .utf8)
        try #"{"Legacy.Mod": false}"#.write(to: game.appendingPathComponent("R2Northstar/enabledmods.json"), atomically: true, encoding: .utf8)

        let mods = ThunderstoreClient.shared.installedMods(in: game)
        #expect(mods.map(\.name) == ["Legacy.Mod", "Modern.Mod"])
        #expect(mods.first?.enabled == false)
        #expect(mods.last?.thunderstoreID == "Author-Pkg-1.0.0")
    }

    @Test func serverDecoding() throws {
        let json = Data(#"[{"id":"a","name":"S","map":"mp_glitch","playlist":"aitdm","playerCount":3,"maxPlayers":16,"hasPassword":false,"modInfo":{"Mods":[{"name":"M","version":"1.0"}]}}]"#.utf8)
        let servers = try JSONDecoder().decode([NorthstarServer].self, from: json)
        #expect(servers.first?.requiredMods.first?.name == "M")
    }
}
