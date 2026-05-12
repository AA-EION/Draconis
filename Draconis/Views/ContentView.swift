import SwiftUI

enum DraconisSection: String, Hashable, Identifiable, CaseIterable {
    case play, mods, servers, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .play:     return "Play"
        case .mods:     return "Mods"
        case .servers:  return "Servers"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .play:     return "play.fill"
        case .mods:     return "puzzlepiece.extension.fill"
        case .servers:  return "server.rack"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var section: DraconisSection? = .play

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BackgroundLayer())
        }
        .sheet(isPresented: $env.showOnboarding) {
            OnboardingView()
                .environmentObject(env)
                .frame(minWidth: 560, minHeight: 460)
        }
        .navigationTitle("Draconis")
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section("Launcher") {
                ForEach(DraconisSection.allCases.filter { $0 != .settings }) { item in
                    NavigationLink(value: item) {
                        Label(item.label, systemImage: item.symbol)
                    }
                }
            }

            Section("Bottle") {
                if env.bottles.isEmpty {
                    Text("No bottles detected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Picker("Active bottle", selection: $env.selectedBottleID) {
                        ForEach(env.bottles) { bottle in
                            Label(bottle.name, systemImage: bottle.backend.symbolName)
                                .tag(Optional(bottle.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Button {
                    Task { await env.refreshBottles() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            }

            Section("Backends") {
                ForEach(WineBackend.allCases) { backend in
                    HStack {
                        Label(backend.displayName, systemImage: backend.symbolName)
                        Spacer()
                        if env.availableBackends.contains(backend) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "circle.dashed")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.callout)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch section ?? .play {
        case .play:     PlayView()
        case .mods:     ModsView()
        case .servers:  ServersView()
        case .settings: SettingsView()
        }
    }
}

/// Soft gradient + subtle vignette behind the detail pane. Liquid Glass surfaces
/// on top draw their tint from this layer, so it sets the overall mood.
private struct BackgroundLayer: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.04, blue: 0.13),
                    Color(red: 0.13, green: 0.05, blue: 0.20),
                    Color(red: 0.03, green: 0.06, blue: 0.16)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.accentColor.opacity(0.25), .clear],
                center: .topTrailing, startRadius: 30, endRadius: 600
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView().environmentObject(AppEnvironment())
}
