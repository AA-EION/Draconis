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
                Text("INSTALLED MODS").stencil()
                Spacer()
                Button("Install from zip…") {
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
                    Button("Remove") { model.uninstall(mod) }.fixedSize()
                }
            }
        }
        .glassCard()
    }

    var browseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("THUNDERSTORE").stencil()
                Spacer()
                TextField("Search mods…", text: $model.modFilter).frame(width: 260)
                Button(model.modsLoading ? "Loading…" : "Refresh") { Task { await model.refreshMods() } }.fixedSize()
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
                        Text("INSTALLED").stencil()
                    } else {
                        Button("Install") { Task { await model.install(package) } }.fixedSize()
                            .disabled(model.selectedGame == nil)
                    }
                }
            }
        }
        .glassCard()
    }
}
