import SwiftUI
import AppKit

@main
struct DraconisApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .frame(minWidth: 980, minHeight: 620)
                .task { await environment.bootstrap() }
                .background(WindowConfigurator())
                .background(TransparentBackdrop())
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
                || env.selectedBottle?.hasNorthstar != true
            )

            Button("Launch Titanfall 2 (Vanilla)") {
                Task { await env.launch(mode: .vanilla) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(env.selectedBottle == nil || env.launchInFlight)

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

            Button(env.creatingBottle ? "Creating bottle…" : "Create Titanfall 2 Bottle") {
                Task { await env.createCrossOverTitanfallBottle() }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(
                env.creatingBottle
                || !env.availableBackends.contains(.crossover)
            )
        }

        // ── Bottle ────────────────────────────────────────────────────────────
        CommandMenu("Bottle") {
            Button("Rescan Bottles") {
                Task { await env.refreshBottles() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Rescan Backends") {
                Task {
                    await env.refreshBackends()
                    await env.refreshBottles()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

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

        // ── Backends ──────────────────────────────────────────────────────────
        CommandMenu("Backends") {
            Button("Get CrossOver…") {
                NSWorkspace.shared.open(URL(string: "https://www.codeweavers.com/crossover")!)
            }
            Button("Get Game Porting Toolkit…") {
                NSWorkspace.shared.open(URL(string: "https://developer.apple.com/games/")!)
            }
            Button("Get Sikarugir…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/Sikarugir-App/sikarugir")!)
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

// MARK: - NSWindow transparency
//
// We want the user to *see through* Draconis onto whatever's behind it, while
// still keeping Liquid Glass surfaces inside the window legible.
//   • backgroundColor = .clear, isOpaque = false → window itself is transparent
//   • Behind everything, an NSVisualEffectView with .hudWindow material gives a
//     very soft tint so the Liquid Glass on top has something to refract.

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

/// Faint blurred backdrop sitting behind the SwiftUI content. NSVisualEffectView
/// with `.behindWindow` blending lets the desktop / other windows show through.
private struct TransparentBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = false
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}
