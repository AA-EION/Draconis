import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape.fill") }
            backendTab
                .tabItem { Label("CrossOver", systemImage: "wineglass.fill") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "terminal") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle.fill") }
        }
        .frame(width: 580, height: 460)
    }

    // MARK: - General

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 0) {
                        if let bottle = env.selectedBottle {
                            infoRow(label: "Active bottle", value: bottle.name)
                            Divider().overlay(.primary.opacity(0.10))
                            infoRow(label: "Prefix", value: bottle.prefixURL.lastPathComponent)
                            if let tf2 = bottle.titanfall2InstallPath {
                                Divider().overlay(.primary.opacity(0.10))
                                infoRow(
                                    label: "Titanfall 2",
                                    value: URL(fileURLWithPath: tf2).lastPathComponent
                                )
                            }
                        } else {
                            Text("No bottle selected.")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                GlassEffectContainer {
                    VStack(spacing: 0) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [PathResolver.draconisSupport]
                            )
                        } label: {
                            Label("Open Support Folder in Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.glass)

                        Divider().overlay(.primary.opacity(0.10))

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [PathResolver.launchLogs]
                            )
                        } label: {
                            Label("Open Launch Logs in Finder", systemImage: "doc.text")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .padding(20)
        }
    }

    // MARK: - CrossOver

    private var backendTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Label("CrossOver", systemImage: "wineglass.fill")
                                .font(.callout)
                                .foregroundStyle(.primary)
                            Spacer()
                            if env.crossOverInstalled {
                                Label("Detected", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            } else {
                                Link(
                                    "Buy / install",
                                    destination: URL(
                                        string: "https://www.codeweavers.com/crossover"
                                    )!
                                )
                                .font(.caption.weight(.medium))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            env.openCrossOver()
                        } label: {
                            Label("Open CrossOver", systemImage: "wineglass")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.glass)
                        .disabled(!env.crossOverInstalled)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .padding(20)
        }
    }

    // MARK: - Advanced

    private var advancedTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassEffectContainer {
                    VStack(spacing: 0) {
                        toggleRow(label: "Show console pane in sidebar", isOn: $env.showConsole)
                        Divider().overlay(.primary.opacity(0.10))
                        toggleRow(label: "Verbose logging", isOn: $env.verboseLogging)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                GlassEffectContainer {
                    Text("""
                    Draconis runs Titanfall 2 inside a CrossOver bottle via \
                    `cxstart --bottle <name>`. Game launches go fire-and-forget \
                    so macOS App Nap can't throttle the wine tree; their \
                    stdout/stderr land in ~/Library/Application Support/Draconis/Logs.
                    """)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.75))
                    .padding(20)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .padding(20)
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "dragonhead")
                .font(.system(size: 48))
                .foregroundStyle(.primary.opacity(0.9))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Draconis").font(TF.hero(28))
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Open-source Titanfall 2 + Northstar launcher for macOS Tahoe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Licensed under GPL-3.0-or-later.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.6))
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func toggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
