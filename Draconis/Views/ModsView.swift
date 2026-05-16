import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ModsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var query: String = ""
    @State private var tab: Tab = .browse
    @State private var sort: SortMode = .rating
    @State private var selectedCategory: String = "All"
    @State private var hideDeprecated: Bool = UserDefaults.standard.bool(forKey: "mods.hideDeprecated")
    @State private var hideNSFW: Bool = UserDefaults.standard.bool(forKey: "mods.hideNSFW")
    @State private var dropTargeted: Bool = false
    @State private var installingPackages: Set<String> = []

    enum Tab: String, CaseIterable, Identifiable {
        case browse, installed
        var id: String { rawValue }
        var label: String {
            self == .browse ? "Thunderstore" : "Installed"
        }
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case rating, downloads, updated, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .rating:    return "Top rated"
            case .downloads: return "Most downloaded"
            case .updated:   return "Recently updated"
            case .name:      return "Name (A–Z)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            switch tab {
            case .browse:    browseList
            case .installed: installedList
            }
        }
        .task { await env.refreshThunderstore() }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if dropTargeted {
                dropOverlay
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search mods…", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accentMedium)), in: .capsule)

                Button {
                    Task { await env.refreshThunderstore() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(env.modsLoading)
            }

            if tab == .browse {
                browseFilterBar
            } else {
                installedSummaryBar
            }
        }
        .padding(20)
    }

    private var browseFilterBar: some View {
        HStack(spacing: 10) {
            Picker("Sort", selection: $sort) {
                ForEach(SortMode.allCases) { Text($0.label).tag($0) }
            }
            .frame(maxWidth: 200)

            Picker("Category", selection: $selectedCategory) {
                ForEach(allCategories, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 220)

            Spacer()

            Toggle("Hide deprecated", isOn: $hideDeprecated)
                .toggleStyle(.checkbox)
                .onChange(of: hideDeprecated) { _, new in
                    UserDefaults.standard.set(new, forKey: "mods.hideDeprecated")
                }

            Toggle("Hide NSFW", isOn: $hideNSFW)
                .toggleStyle(.checkbox)
                .onChange(of: hideNSFW) { _, new in
                    UserDefaults.standard.set(new, forKey: "mods.hideNSFW")
                }

            Text("\(filteredPackages.count) mods").stencilLabel()
        }
        .font(TF.body(11))
    }

    private var installedSummaryBar: some View {
        HStack(spacing: 10) {
            let updates = env.modUpdatesAvailable.count
            Text("\(env.installedMods.count) installed").stencilLabel()
            if updates > 0 {
                Text("\(updates) update\(updates == 1 ? "" : "s") available")
                    .font(TF.body(11))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.5)), in: .capsule)
            }
            Spacer()
            Text("Drop a .zip here to install a local mod")
                .font(TF.body(11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Browse list

    private var browseList: some View {
        let filtered = filteredPackages
        return ScrollView {
            LazyVStack(spacing: 12) {
                if let err = env.modsLoadError, filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.title2).foregroundStyle(.red)
                        Text("Couldn't load Thunderstore").font(TF.title(15))
                        Text(err)
                            .font(TF.body(12))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)
                        Button("Retry") { Task { await env.refreshThunderstore() } }
                            .buttonStyle(.glass)
                    }
                    .padding(40)
                    .glassEffect(.regular.tint(.red.opacity(DraconisTheme.Card.error)), in: .rect(cornerRadius: 16))
                } else if env.modsLoading && filtered.isEmpty {
                    ProgressView("Fetching Thunderstore…")
                        .padding(40)
                } else if filtered.isEmpty {
                    Text("No mods found.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    ForEach(filtered) { pkg in
                        ThunderstoreRow(
                            package: pkg,
                            isInstalling: installingPackages.contains(pkg.fullName),
                            isInstalled: isInstalled(pkg),
                            install: { install(pkg) }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Installed list

    private var installedList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if env.installedMods.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No mods installed in \(env.selectedBottle?.name ?? "this bottle").")
                            .foregroundStyle(.secondary)
                        Text("Browse Thunderstore above, or drop a .zip anywhere on this view.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(40)
                } else {
                    ForEach(env.installedMods) { mod in
                        InstalledModRow(
                            mod: mod,
                            update: env.modUpdatesAvailable[mod.name]
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Drop overlay

    private var dropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.15)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                Text("Drop .zip to install")
                    .font(TF.title(16))
            }
            .padding(40)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.6)), in: .rect(cornerRadius: 22))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Filtering / sorting

    private var allCategories: [String] {
        var seen = Set<String>()
        var ordered: [String] = ["All"]
        for pkg in env.thunderstorePackages {
            for cat in pkg.categories where !seen.contains(cat) {
                seen.insert(cat)
                ordered.append(cat)
            }
        }
        return ordered
    }

    private var filteredPackages: [ThunderstorePackage] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        var pkgs = env.thunderstorePackages

        if hideDeprecated { pkgs = pkgs.filter { !$0.isDeprecated } }
        if hideNSFW { pkgs = pkgs.filter { !$0.hasNsfwContent } }
        if selectedCategory != "All" {
            pkgs = pkgs.filter { $0.categories.contains(selectedCategory) }
        }
        if !needle.isEmpty {
            pkgs = pkgs.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                || $0.owner.localizedCaseInsensitiveContains(needle)
                || ($0.latest?.description.localizedCaseInsensitiveContains(needle) ?? false)
            }
        }

        switch sort {
        case .rating:
            pkgs.sort { $0.ratingScore > $1.ratingScore }
        case .downloads:
            pkgs.sort {
                ($0.latest?.downloads ?? 0) > ($1.latest?.downloads ?? 0)
            }
        case .updated:
            pkgs.sort { $0.dateUpdated > $1.dateUpdated }
        case .name:
            pkgs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return pkgs
    }

    private func isInstalled(_ pkg: ThunderstorePackage) -> Bool {
        env.installedMods.contains { $0.name == pkg.name }
    }

    // MARK: - Actions

    private func install(_ pkg: ThunderstorePackage) {
        guard let v = pkg.latest else { return }
        installingPackages.insert(pkg.fullName)
        Task {
            defer {
                Task { @MainActor in installingPackages.remove(pkg.fullName) }
            }
            try? await env.installMod(v)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "zip" else { return }
                Task { @MainActor in
                    await env.installLocalMod(at: url)
                }
            }
        }
        return true
    }
}

// MARK: - Rows

private struct ThunderstoreRow: View {
    let package: ThunderstorePackage
    let isInstalling: Bool
    let isInstalled: Bool
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let icon = package.latest?.icon {
                AsyncImage(url: icon) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(package.name)
                        .font(TF.title(16))
                    Text("by \(package.owner)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    badges
                }
                Text(package.latest?.description ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(package.categories.prefix(4), id: \.self) { cat in
                        Text(cat)
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accentMedium)), in: .capsule)
                    }
                    Spacer()
                    if let downloads = package.latest?.downloads {
                        Label(formatCount(downloads), systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("\(package.ratingScore)", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 6) {
                Button(action: install) {
                    Label(
                        isInstalling ? "Installing…" : (isInstalled ? "Reinstall" : "Install"),
                        systemImage: isInstalling ? "hourglass" : (isInstalled ? "arrow.clockwise" : "arrow.down.circle.fill")
                    )
                }
                .buttonStyle(.glass)
                .disabled(package.latest == nil || isInstalling)

                if let url = package.packageURL {
                    Link(destination: url) {
                        Label("Page", systemImage: "safari")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if package.isPinned {
                Text("PINNED")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.55)), in: .capsule)
            }
            if isInstalled {
                Text("INSTALLED")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassEffect(.regular.tint(.green.opacity(0.55)), in: .capsule)
            }
            if package.hasNsfwContent {
                Text("NSFW")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassEffect(.regular.tint(.pink.opacity(0.55)), in: .capsule)
            }
            if package.isDeprecated {
                Text("DEPRECATED")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassEffect(.regular.tint(.orange.opacity(0.55)), in: .capsule)
            }
        }
    }

    private func formatCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...:
            return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", Double(n) / 1_000)
        default:
            return "\(n)"
        }
    }
}

private struct InstalledModRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let mod: InstalledMod
    let update: ThunderstoreVersion?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mod.name).font(TF.title(15))
                    if update != nil {
                        Text("UPDATE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .glassEffect(.regular.tint(Color.accentColor.opacity(0.55)), in: .capsule)
                    }
                    if mod.thunderstoreID != nil {
                        Text("PACKAGE")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .glassEffect(.regular.tint(.gray.opacity(0.45)), in: .capsule)
                    }
                }
                HStack(spacing: 6) {
                    Text(mod.version)
                    if let u = update {
                        Text("→ \(u.versionNumber)")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(TF.body(11))
                .foregroundStyle(.secondary)
            }
            Spacer()

            if let u = update {
                Button {
                    Task { try? await env.installMod(u) }
                } label: {
                    Label("Update", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.glass)
            }

            Toggle("", isOn: Binding(
                get: { mod.enabled },
                set: { env.setMod(mod, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Menu {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([mod.folderURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button(role: .destructive) {
                    env.uninstallMod(mod)
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
        }
        .padding(14)
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), in: .rect(cornerRadius: 14))
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([mod.folderURL])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            if let u = update {
                Button {
                    Task { try? await env.installMod(u) }
                } label: {
                    Label("Update to \(u.versionNumber)", systemImage: "arrow.up.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                env.uninstallMod(mod)
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
        }
    }
}
