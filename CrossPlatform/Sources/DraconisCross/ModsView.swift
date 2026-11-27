import DraconisCore
import Foundation
import SwiftCrossUI

struct ModsView: View {
    @Bindable var model: AppModel
    @Environment(\.chooseFile) var chooseFile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            installedCard
            browseCard
        }
        .task {
            if model.packages.isEmpty { await model.refreshMods() }
        }
    }

    var installedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Stencil("Installed Mods")
                Spacer()
                GlassButton(title: "Install from zip…", icon: "folder-plus", size: 13) {
                    Task {
                        if let url = await chooseFile(title: "Install a mod zip", defaultButtonLabel: "Install") {
                            await model.installLocalZip(url)
                        }
                    }
                }
            }
            if model.installedMods.isEmpty {
                Text(model.selectedGame == nil ? "Pick a Titanfall 2 install first." : "No mods installed yet.")
                    .foregroundColor(Theme.faint)
            }
            ForEach(model.installedMods) { mod in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mod.name).font(.system(size: 14, weight: .semibold))
                        Text(mod.version).foregroundColor(Theme.faint)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(get: { mod.enabled }, set: { model.setEnabled(mod, $0) }))
                .toggleStyle(.switch)
                    GlassButton(title: "Remove", icon: "trash", size: 13) { model.uninstall(mod) }
                }
            }
        }
        .glassCard()
    }

    var browseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Stencil("Thunderstore")
                Spacer()
                TextField("Search mods…", text: $model.modFilter).frame(width: 260)
                GlassButton(title: model.modsLoading ? "Loading…" : "Refresh", icon: "refresh-cw", size: 13) { Task { await model.refreshMods() } }
            }
            if model.modsLoading && model.packages.isEmpty {
                ProgressView("Loading the mod list…")
            }
            ForEach(model.filteredPackages) { package in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.name).font(.system(size: 14, weight: .semibold))
                        Text("\(package.owner) · \(package.latest?.versionNumber ?? "")")
                            .foregroundColor(Theme.faint)
                        if let summary = package.latest?.description, !summary.isEmpty {
                            Text(summary).foregroundColor(Theme.secondary)
                        }
                    }
                    Spacer()
                    if model.modBusy == package.fullName {
                        ProgressView()
                    } else if model.isInstalled(package) {
                        Stencil("Installed")
                    } else {
                        GlassButton(title: "Install", icon: "download", size: 13) { Task { await model.install(package) } }
                            .disabled(model.selectedGame == nil)
                    }
                }
            }
        }
        .glassCard()
    }
}
