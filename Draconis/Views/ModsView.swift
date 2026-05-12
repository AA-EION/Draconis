import SwiftUI

struct ModsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var query: String = ""
    @State private var tab: Tab = .browse

    enum Tab: String, CaseIterable, Identifiable {
        case browse, installed
        var id: String { rawValue }
        var label: String {
            self == .browse ? "Thunderstore" : "Installed"
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
    }

    private var header: some View {
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            Button {
                Task { await env.refreshThunderstore() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
        }
        .padding(20)
    }

    private var browseList: some View {
        let filtered = filteredPackages
        return ScrollView {
            LazyVStack(spacing: 12) {
                if env.modsLoading && filtered.isEmpty {
                    ProgressView("Fetching Thunderstore…")
                        .padding(40)
                } else if filtered.isEmpty {
                    Text("No mods found.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    ForEach(filtered) { pkg in
                        ThunderstoreRow(package: pkg) {
                            guard let v = pkg.latest else { return }
                            Task { try? await env.installMod(v) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var installedList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if env.installedMods.isEmpty {
                    Text("No mods installed in \(env.selectedBottle?.name ?? "this bottle").")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    ForEach(env.installedMods) { mod in
                        InstalledModRow(mod: mod)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var filteredPackages: [ThunderstorePackage] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { return env.thunderstorePackages }
        return env.thunderstorePackages.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
            || $0.owner.localizedCaseInsensitiveContains(needle)
            || ($0.latest?.description.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }
}

private struct ThunderstoreRow: View {
    let package: ThunderstorePackage
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
                        .font(.headline)
                    Text("by \(package.owner)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if package.isDeprecated {
                        Text("DEPRECATED")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .glassEffect(.regular.tint(.orange.opacity(0.5)), in: .capsule)
                    }
                }
                Text(package.latest?.description ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(package.categories, id: \.self) { cat in
                        Text(cat)
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            Button(action: install) {
                Label("Install", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.glass)
            .disabled(package.latest == nil)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct InstalledModRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let mod: InstalledMod

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name).font(.headline)
                Text(mod.version).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { mod.enabled },
                set: { newVal in
                    try? ThunderstoreClient.shared.setEnabled(newVal, mod: mod)
                    Task { await env.refreshThunderstore() }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            Button(role: .destructive) {
                try? ThunderstoreClient.shared.uninstall(mod)
                Task { await env.refreshThunderstore() }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
