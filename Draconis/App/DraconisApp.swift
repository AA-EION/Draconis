import SwiftUI

@main
struct DraconisApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .frame(minWidth: 980, minHeight: 620)
                .task { await environment.bootstrap() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Bottle") {
                Button("Rescan…") {
                    Task { await environment.refreshBottles() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(environment)
        }
    }
}
