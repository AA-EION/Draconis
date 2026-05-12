import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape.fill") }
            backendsTab
                .tabItem { Label("Backends", systemImage: "wineglass.fill") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle.fill") }
        }
        .frame(width: 540, height: 420)
    }

    private var generalTab: some View {
        Form {
            if let bottle = env.selectedBottle {
                LabeledContent("Active bottle", value: bottle.name)
                LabeledContent("Backend", value: bottle.backend.displayName)
                LabeledContent("Prefix", value: bottle.prefixURL.path)
                if let tf2 = bottle.titanfall2InstallPath {
                    LabeledContent("Titanfall 2", value: tf2)
                }
            } else {
                Text("No bottle selected.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Open Draconis Support Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [PathResolver.draconisSupport]
                    )
                }
            }
        }
        .padding()
    }

    private var backendsTab: some View {
        Form {
            ForEach(WineBackend.allCases) { backend in
                HStack {
                    Label(backend.displayName, systemImage: backend.symbolName)
                    Spacer()
                    if env.availableBackends.contains(backend) {
                        Text("Detected")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not installed")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Preferred for new installs") {
                Text(env.preferredBackend?.displayName ?? "None available")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Text("Draconis").font(.largeTitle.bold())
            Text("Open-source Titanfall 2 + Northstar launcher for macOS.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Licensed under GPL-3.0-or-later.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
    }
}
