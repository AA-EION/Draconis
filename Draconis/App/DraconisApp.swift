import SwiftUI
import AppKit

@main
struct DraconisApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .preferredColorScheme(.light)
                .frame(minWidth: 980, minHeight: 620)
                .task { await environment.bootstrap() }
                .background(WindowConfigurator())
                .background(TransparentBackdrop().ignoresSafeArea())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            DraconisCommands(env: environment)
        }

        Settings {
            SettingsView()
                .environmentObject(environment)
        }
    }
}

// MARK: - Menu Commands

struct DraconisCommands: Commands {
    @ObservedObject var env: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        // ── Launcher ──────────────────────────────────────────────────────────
        CommandMenu("Launcher") {
            Button("Launch with Northstar") {
                Task { await env.launch(mode: .northstar) }
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(
                env.selectedBottle == nil
                || env.launchInFlight
                || env.selectedBottle?.hasTitanfall2 != true
                || env.selectedBottle?.hasNorthstar != true
                || env.selectedBottle?.hasSteam != true
            )

            Button("Launch Titanfall 2 (Vanilla)") {
                Task { await env.launch(mode: .vanilla) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(
                env.selectedBottle == nil
                || env.launchInFlight
                || env.selectedBottle?.hasTitanfall2 != true
            )

            Divider()

            Button(env.updating ? "Updating Northstar…" : "Install / Update Northstar") {
                Task { await env.installLatestNorthstar() }
            }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(env.selectedBottle == nil || env.updating)

            Button(env.steamInstalling ? "Installing Steam…" : "Install Steam in Bottle") {
                Task { await env.installSteam() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(env.selectedBottle == nil || env.steamInstalling)

            Divider()

            Button("Open CrossOver") {
                env.openCrossOver()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!env.crossOverInstalled)
        }

        // ── Bottle ────────────────────────────────────────────────────────────
        CommandMenu("Bottle") {
            Button("Rescan Bottles") {
                Task {
                    await env.refreshCrossOverState()
                    await env.refreshBottles()
                }
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Refresh Mod List") {
                Task { await env.refreshThunderstore() }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Refresh Server Browser") {
                Task { await env.refreshServers() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Show Setup Wizard…") {
                env.showOnboarding = true
            }
        }

        // ── Backend ───────────────────────────────────────────────────────────
        CommandMenu("Backend") {
            Button("Get CrossOver…") {
                NSWorkspace.shared.open(URL(string: "https://www.codeweavers.com/crossover")!)
            }
        }

        // ── Debug ─────────────────────────────────────────────────────────────
        CommandMenu("Debug") {
            Toggle("Show Console", isOn: $env.showConsole)
                .keyboardShortcut("`", modifiers: [.command, .option])
            Toggle("Verbose Logging", isOn: $env.verboseLogging)
        }

        // ── Help extras ───────────────────────────────────────────────────────
        CommandGroup(after: .help) {
            Button("Open Support Folder in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([PathResolver.draconisSupport])
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

// MARK: - NSWindow chrome + backdrop
//
// A near-opaque white backdrop with a light frosted blur beneath, so the
// Liquid Glass cards have a clean canvas to refract while keeping legibility
// high (the user explicitly preferred legibility over translucency).
//   • titlebarAppearsTransparent + fullSizeContentView blend the title bar
//     into the content area.
//   • NSVisualEffectView (popover material) provides a subtle frosted blur.
//   • A white overlay above the visual effect mutes the desktop bleed-through.

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.hasShadow = true
            window.styleMask.insert(.fullSizeContentView)
            window.appearance = NSAppearance(named: .aqua)
        }
    }
}

private struct TransparentBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffect(material: .popover, blending: .behindWindow)
            // Enough white to keep text legible on the frosted canvas
            // without fully killing the Liquid Glass translucency.
            Color.white.opacity(0.55)
        }
    }
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = false
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
