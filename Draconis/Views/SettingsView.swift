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
            maximaTab
                .tabItem { Label("Maxima", systemImage: "gamecontroller.fill") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "terminal") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle.fill") }
        }
        .frame(width: 580, height: 540)
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
                                    .foregroundStyle(.white)
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

    // MARK: - Maxima
    //
    // Maxima admin lives here (not in PlayView) — install / update /
    // uninstall, MaximaHelper registration, and the per-bottle
    // `MaximaRole` are all infrequent setup concerns rather than
    // active gameplay. PlayView only surfaces the gameplay-facing
    // launcher pill and progress/error during install.
    private var maximaTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status pills — install + helper-registration health.
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            StatusPill(
                                label: "MaximaHelper",
                                value: env.maximaHelperRegistered ? "Registered" : "Not registered",
                                symbol: env.maximaHelperRegistered
                                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                active: env.maximaHelperRegistered
                            )
                            StatusPill(
                                label: "Maxima",
                                value: maximaVersionLabel,
                                symbol: env.maximaInstalled
                                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                active: env.maximaInstalled
                            )
                        }
                        if let bottle = env.selectedBottle, env.maximaInstalled {
                            Divider().overlay(.primary.opacity(0.10))
                            HStack {
                                Text("Role for this bottle")
                                    .font(.callout)
                                    .foregroundStyle(.primary.opacity(0.6))
                                Spacer()
                                Text(bottle.maximaRole.displayName)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(20)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                // Action buttons — install / update / uninstall.
                GlassEffectContainer {
                    VStack(spacing: 0) {
                        if env.maximaInstalled && env.maximaHelperRegistered {
                            if env.maximaUpdateAvailable {
                                Button {
                                    Task { await env.updateMaxima() }
                                } label: {
                                    Label(
                                        env.maximaSettingUp ? "Updating…" : "Update Maxima",
                                        systemImage: env.maximaSettingUp ? "hourglass" : "arrow.up.circle.fill"
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.glass)
                                .disabled(env.selectedBottle == nil || env.maximaSettingUp)

                                Divider().overlay(.primary.opacity(0.10))
                            }

                            Button {
                                Task { await env.uninstallMaxima() }
                            } label: {
                                Label(
                                    env.maximaSettingUp ? "Uninstalling…" : "Uninstall Maxima",
                                    systemImage: env.maximaSettingUp ? "hourglass" : "trash"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.glass)
                            .disabled(env.selectedBottle == nil || env.maximaSettingUp)
                        } else {
                            Button {
                                Task { await env.setupMaxima() }
                            } label: {
                                Label(
                                    env.maximaSettingUp ? "Setting up…" : "Set up Maxima",
                                    systemImage: env.maximaSettingUp
                                        ? "hourglass" : "arrow.down.circle.fill"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.glass)
                            .disabled(
                                env.selectedBottle == nil
                                || env.maximaSettingUp
                                || env.selectedBottle?.hasTitanfall2 != true
                            )

                            if env.maximaHelperRegistered {
                                Divider().overlay(.primary.opacity(0.10))
                                Button {
                                    Task { await env.uninstallMaxima() }
                                } label: {
                                    Label("Unregister Helper", systemImage: "trash")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.glass)
                                .disabled(env.maximaSettingUp)
                            }
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                // Setup hint, when something's missing.
                if !env.maximaInstalled || !env.maximaHelperRegistered {
                    GlassEffectContainer {
                        Text(maximaSetupNote)
                            .font(.callout)
                            .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }

                // Reset Onboarding — long-pressed for in the wizard
                // flow, useful when a user installs in a new bottle
                // or wants to re-run the picker. (D4.)
                GlassEffectContainer {
                    Button {
                        env.showOnboarding = true
                    } label: {
                        Label("Open Onboarding wizard…", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.glass)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                // About + learn-more link.
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About Maxima")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Maxima is an open-source replacement for the EA Desktop launcher. It runs inside your CrossOver bottle and handles EA authentication so Titanfall 2 can sign in without the full EA app.")
                            .font(.callout)
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Learn more about Maxima →",
                             destination: URL(string: "https://github.com/AA-EION/Maxima-Draconis")!)
                            .font(.callout)
                    }
                    .padding(20)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .padding(20)
        }
    }

    private var maximaVersionLabel: String {
        guard env.maximaInstalled else { return "Not installed" }
        if let ver = env.maximaInstalledVersion {
            return env.maximaUpdateAvailable ? "\(ver) (update)" : ver
        }
        return "Installed"
    }

    private var maximaSetupNote: String {
        if env.selectedBottle?.hasTitanfall2 != true {
            return "Titanfall 2 must be installed in the bottle before setting up Maxima."
        }
        if !env.maximaInstalled && !env.maximaHelperRegistered {
            return "Maxima installs the EA launcher replacement inside your CrossOver bottle " +
                   "and registers a background helper on your Mac to handle EA's login redirect."
        }
        if !env.maximaInstalled {
            return "Maxima is not yet installed in this bottle."
        }
        return "MaximaHelper is not registered. Re-run setup to fix this."
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
                    .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
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
