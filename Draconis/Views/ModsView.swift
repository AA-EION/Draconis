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
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.22)), in: .capsule)

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
                    .glassEffect(.regular.tint(Color.black.opacity(0.05)), in: .rect(cornerRadius: 16))
                } else if env.modsLoading && filtered.isEmpty {
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
        .scrollContentBackground(.hidden)
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
                        .font(TF.title(16))
                    Text("by \(package.owner)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if package.isDeprecated {
                        Text("DEPRECATED")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .glassEffect(.regular.tint(Color.accentColor.opacity(0.45)), in: .capsule)
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
                            .glassEffect(.regular.tint(Color.accentColor.opacity(0.22)), in: .capsule)
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
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.18)), in: .rect(cornerRadius: 18))
    }
}

private struct InstalledModRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let mod: InstalledMod

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name).font(TF.title(15))
                Text(mod.version).font(TF.body(11)).foregroundStyle(.secondary)
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
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.18)), in: .rect(cornerRadius: 14))
    }
}
