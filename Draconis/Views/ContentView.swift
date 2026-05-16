import SwiftUI

enum DraconisSection: String, Hashable, Identifiable, CaseIterable {
    case play, mods, servers, console, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .play:     return "Play"
        case .mods:     return "Mods"
        case .servers:  return "Servers"
        case .console:  return "Console"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .play:     return "play.fill"
        case .mods:     return "puzzlepiece.extension.fill"
        case .servers:  return "server.rack"
        case .console:  return "terminal"
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
                .scrollContentBackground(.hidden)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $env.showOnboarding) {
            OnboardingView()
                .environmentObject(env)
                .frame(minWidth: 580, minHeight: 480)
        }
        .navigationTitle("Draconis")
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach(visibleSections) { item in
                    NavigationLink(value: item) {
                        Label(item.label, systemImage: item.symbol)
                            .font(TF.title(14))
                    }
                }
            } header: {
                Text("Launcher").stencilLabel()
            }

            Section {
                if env.bottles.isEmpty {
                    Text("No bottles detected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Picker("Active bottle", selection: $env.selectedBottleID) {
                        ForEach(env.bottles) { bottle in
                            Label(bottle.name, systemImage: "wineglass.fill")
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
            } header: {
                Text("Bottle").stencilLabel()
            }

            Section {
                HStack {
                    Label("CrossOver", systemImage: "wineglass.fill")
                        .font(TF.body(12))
                    Spacer()
                    Image(
                        systemName: env.crossOverInstalled
                            ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(env.crossOverInstalled ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                }
                if !env.crossOverInstalled {
                    Link(
                        "Get CrossOver…",
                        destination: URL(string: "https://www.codeweavers.com/crossover")!
                    )
                    .font(TF.body(11))
                }
            } header: {
                Text("Backend").stencilLabel()
            }
        }
        .listStyle(.sidebar)
    }

    private var visibleSections: [DraconisSection] {
        var all: [DraconisSection] = [.play, .mods, .servers]
        if env.showConsole { all.append(.console) }
        return all
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch section ?? .play {
        case .play:     PlayView()
        case .mods:     ModsView()
        case .servers:  ServersView()
        case .console:  ConsoleView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    ContentView().environmentObject(AppEnvironment())
}
