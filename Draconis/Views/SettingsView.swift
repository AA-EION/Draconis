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
                            Divider().overlay(.white.opacity(0.07))
                            infoRow(label: "Backend", value: bottle.backend.displayName)
                            Divider().overlay(.white.opacity(0.07))
                            infoRow(label: "Prefix", value: bottle.prefixURL.lastPathComponent)
                            if let tf2 = bottle.titanfall2InstallPath {
                                Divider().overlay(.white.opacity(0.07))
                                infoRow(label: "Titanfall 2", value: URL(fileURLWithPath: tf2).lastPathComponent)
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
                            NSWorkspace.shared.activateFileViewerSelecting([PathResolver.draconisSupport])
                        } label: {
                            Label("Open Support Folder in Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.glass)

                        Divider().overlay(.white.opacity(0.07))

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([PathResolver.downloadsCache])
                        } label: {
                            Label("Open Downloads Cache in Finder", systemImage: "arrow.down.circle")
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

    // MARK: - Backends

    private var backendsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(WineBackend.allCases.enumerated()), id: \.element) { idx, backend in
                            if idx > 0 { Divider().overlay(.white.opacity(0.07)) }
                            BackendRow(backend: backend)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                        }

                        if let preferred = env.preferredBackend {
                            Divider().overlay(.white.opacity(0.1))
                            HStack {
                                Text("Preferred for new installs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(preferred.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            Task { await env.createCrossOverTitanfallBottle() }
                        } label: {
                            Label(
                                env.creatingBottle ? "Creating…" : "Create Titanfall 2 Bottle (CrossOver)",
                                systemImage: "wineglass"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.glass)
                        .disabled(env.creatingBottle || !env.availableBackends.contains(.crossover))

                        if let err = env.bottleCreationError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }
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
                        Divider().overlay(.white.opacity(0.07))
                        toggleRow(label: "Verbose logging", isOn: $env.verboseLogging)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                GlassEffectContainer {
                    Text("""
                    Draconis launches Titanfall 2 through each backend's own runtime — \
                    CrossOver's wine --bottle --cx-app, Whisky's bundled wine64, \
                    Sikarugir wrappers' bundled wine, or Apple's gameportingtoolkit. \
                    It never invokes a system wine.
                    """)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
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
                .foregroundStyle(.white.opacity(0.9))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Draconis").font(TF.hero(28))
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
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
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
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Backend row with auto-install button

private struct BackendRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let backend: WineBackend

    var body: some View {
        HStack(spacing: 12) {
            Label(backend.displayName, systemImage: backend.symbolName)
                .font(.callout)
                .foregroundStyle(.white)
            Spacer()
            if env.availableBackends.contains(backend) {
                Label("Detected", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else if backend.isPaid {
                Link("Buy / install",
                     destination: URL(string: "https://www.codeweavers.com/crossover")!)
                    .font(.caption.weight(.medium))
            } else {
                Button {
                    Task { await env.installBackend(backend) }
                } label: {
                    if env.installingBackend == backend {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Install via Homebrew", systemImage: "arrow.down.circle")
                            .font(.caption.weight(.medium))
                    }
                }
                .buttonStyle(.glass)
                .disabled(env.installingBackend != nil)
                .controlSize(.small)
            }
        }
    }
}
