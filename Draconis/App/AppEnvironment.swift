import Foundation
import SwiftUI
import Combine

/// Single source of truth for app-wide state. Held as a `@StateObject` at the
/// root of the scene and injected via `.environmentObject`.
@MainActor
public final class AppEnvironment: ObservableObject {

    // Discovered bottles across every backend
    @Published public private(set) var bottles: [WineBottle] = []
    @Published public var selectedBottleID: String?

    // Backend availability
    @Published public private(set) var availableBackends: [WineBackend] = []
    @Published public private(set) var preferredBackend: WineBackend?

    // Launch status
    @Published public var launchInFlight: Bool = false
    @Published public var lastLaunchError: String?

    // Mods
    @Published public private(set) var thunderstorePackages: [ThunderstorePackage] = []
    @Published public private(set) var installedMods: [InstalledMod] = []
    @Published public var modsLoading: Bool = false

    // Server browser
    @Published public private(set) var servers: [NorthstarServer] = []
    @Published public var serversLoading: Bool = false
    @Published public var serverFilter: String = ""

    // Northstar releases
    @Published public private(set) var northstarReleases: [NorthstarRelease] = []
    @Published public var updating: Bool = false

    // Onboarding
    @Published public var showOnboarding: Bool = false

    public var selectedBottle: WineBottle? {
        bottles.first { $0.id == selectedBottleID }
    }

    public func bootstrap() async {
        await refreshBottles()
        await refreshBackends()
        if bottles.isEmpty {
            showOnboarding = true
        } else if selectedBottleID == nil {
            // Prefer a bottle with Northstar
            selectedBottleID = bottles.first(where: \.hasNorthstar)?.id ?? bottles.first?.id
        }
        // Best-effort refresh of Northstar releases; ignore errors here.
        try? await refreshNorthstarReleases()
    }

    public func refreshBottles() async {
        bottles = await WineBackendManager.shared.allBottles()
        // Keep the current selection if still valid; otherwise reset.
        if let id = selectedBottleID, !bottles.contains(where: { $0.id == id }) {
            selectedBottleID = bottles.first?.id
        }
    }

    public func refreshBackends() async {
        availableBackends = await WineBackendManager.shared.availableBackends()
        preferredBackend  = await WineBackendManager.shared.preferredBackend()
    }

    // MARK: - Launch

    public func launch(mode: NorthstarLauncher.LaunchMode) async {
        guard let bottle = selectedBottle else { return }
        launchInFlight = true
        defer { launchInFlight = false }
        do {
            _ = try await NorthstarLauncher.shared.launch(bottle: bottle, mode: mode)
            lastLaunchError = nil
        } catch {
            lastLaunchError = error.localizedDescription
        }
    }

    // MARK: - Mods

    public func refreshThunderstore() async {
        modsLoading = true
        defer { modsLoading = false }
        do {
            thunderstorePackages = try await ThunderstoreClient.shared.listPackages()
        } catch {
            // Silently fail; the UI shows an empty state.
            thunderstorePackages = []
        }
        if let bottle = selectedBottle {
            installedMods = ThunderstoreClient.shared.installedMods(in: bottle)
        }
    }

    public func installMod(_ version: ThunderstoreVersion) async throws {
        guard let bottle = selectedBottle else { return }
        try await ThunderstoreClient.shared.install(version, into: bottle)
        installedMods = ThunderstoreClient.shared.installedMods(in: bottle)
    }

    // MARK: - Servers

    public func refreshServers() async {
        serversLoading = true
        defer { serversLoading = false }
        do {
            servers = try await ServerBrowserClient.shared.servers()
        } catch {
            servers = []
        }
    }

    public var filteredServers: [NorthstarServer] {
        let needle = serverFilter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return servers }
        return servers.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
            || $0.map.localizedCaseInsensitiveContains(needle)
            || $0.playlist.localizedCaseInsensitiveContains(needle)
        }
    }

    // MARK: - Northstar updates

    public func refreshNorthstarReleases() async throws {
        northstarReleases = try await NorthstarUpdater.shared
            .availableReleases(includePrerelease: false)
    }

    public func installLatestNorthstar() async {
        guard let bottle = selectedBottle else { return }
        updating = true
        defer { updating = false }
        do {
            let latest = try await NorthstarUpdater.shared.latestRelease()
            let zip    = try await NorthstarUpdater.shared.downloadRelease(latest)
            try await NorthstarUpdater.shared.install(zipURL: zip, into: bottle)
            await refreshBottles()
        } catch {
            lastLaunchError = error.localizedDescription
        }
    }
}
