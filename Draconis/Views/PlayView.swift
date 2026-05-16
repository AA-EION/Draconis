import SwiftUI

struct PlayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var mode: NorthstarLauncher.LaunchMode = .northstar
    @State private var showMaximaInfo: Bool = false
    @State private var confirmNorthstarUninstall: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                heroCard
                if env.selectedBottle == nil {
                    noBottleCard
                } else if env.selectedBottle?.hasTitanfall2 != true {
                    noTitanfallCard
                } else {
                    bottleStatusCard
                    if let p = env.updateProgress  { northstarProgressCard(p) }
                    if let p = env.maximaProgress  { maximaProgressCard(p) }
                    if let err = env.lastUpdateError ?? env.lastLaunchError ?? env.maximaError {
                        errorCard(err)
                    }
                    actionsCard
                    maximaToggleCard
                    if env.maximaEnabled {
                        maximaCard
                    }
                }
                Spacer(minLength: 60)
            }
            .padding(28)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty / setup states

    private var noBottleCard: some View {
        instructionsCard(
            title: "Set up a Titanfall 2 bottle in CrossOver",
            body: [
                "1. Open CrossOver.",
                "2. Click Install a Windows Application.",
                "3. Search for \"Titanfall 2\" — the profile picks the win10_64 template and installs Steam automatically.",
                "   Note: the CrossTie may appear untrusted in CrossOver — it is genuine and safe.",
                "4. Once the bottle exists, sign in and install Titanfall 2.",
                "5. Come back to Draconis and hit Rescan.",
            ].joined(separator: "\n"),
            primaryActionTitle: env.crossOverInstalled ? "Open CrossOver" : "Get CrossOver…",
            primaryActionDisabled: false,
            primaryAction: {
                if env.crossOverInstalled {
                    env.openCrossOver()
                } else {
                    NSWorkspace.shared.open(
                        URL(string: "https://www.codeweavers.com/crossover")!
                    )
                }
            }
        )
    }

    private var noTitanfallCard: some View {
        instructionsCard(
            title: "Titanfall 2 isn't installed in this bottle yet",
            body: [
                "Draconis sees the bottle but no Titanfall2.exe inside it.",
                "",
                "Open CrossOver, pick the Titanfall 2 install profile, and either:",
                "• Let CrossOver install Steam and then install Titanfall 2 from your Steam library, or",
                "• Point CrossOver's installer at the EA app or Epic Games launcher when prompted.",
                "",
                "Then come back here and hit Rescan.",
            ].joined(separator: "\n"),
            primaryActionTitle: "Open CrossOver",
            primaryActionDisabled: !env.crossOverInstalled,
            primaryAction: { env.openCrossOver() }
        )
    }

    private func instructionsCard(
        title: String,
        body: String,
        primaryActionTitle: String,
        primaryActionDisabled: Bool,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(TF.title(16)).foregroundStyle(.primary)
            Text(body)
                .font(TF.body(13))
                .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action: primaryAction) {
                    Label(primaryActionTitle, systemImage: "wineglass.fill")
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(primaryActionDisabled)

                Button {
                    Task {
                        await env.refreshCrossOverState()
                        await env.refreshBottles()
                    }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accentStrong)), in: .rect(cornerRadius: 22))
    }

    // MARK: - Hero

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 18) {
            Image("DraconisLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .accessibilityLabel("Draconis logo")

            VStack(alignment: .leading, spacing: 6) {
                Text("DRACONIS")
                    .font(TF.hero(48))
                    .tracking(8)
                    .foregroundStyle(.primary)
                Text("Titanfall 2 + Northstar launcher for macOS Tahoe.")
                    .font(TF.title(16))
                    .foregroundStyle(.primary.opacity(0.78))
                if let bottle = env.selectedBottle {
                    Label(
                        "\(bottle.name) — \(bottle.backend.displayName)",
                        systemImage: bottle.backend.symbolName
                    )
                    .font(TF.body(12))
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accentSubtle)).interactive(),
            in: .rect(cornerRadius: 26)
        )
    }

    // MARK: - Status pills

    private var bottleStatusCard: some View {
        HStack(spacing: 14) {
            StatusPill(
                label: "Titanfall 2",
                value: env.selectedBottle?.hasTitanfall2 == true ? "Detected" : "Missing",
                symbol: env.selectedBottle?.hasTitanfall2 == true
                    ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                active: env.selectedBottle?.hasTitanfall2 == true
            )
            StatusPill(
                label: "Launcher",
                value: launcherStatusValue,
                symbol: env.selectedBottle?.hasLauncher == true
                    ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                active: env.selectedBottle?.hasLauncher == true
            )
            StatusPill(
                label: "Northstar",
                value: northstarStatusValue,
                symbol: env.selectedBottle?.hasNorthstar == true
                    ? "bolt.shield.fill" : "questionmark.diamond.fill",
                active: env.selectedBottle?.hasNorthstar == true
            )
        }
    }

    private var launcherStatusValue: String {
        guard let bottle = env.selectedBottle else { return "Missing" }
        if bottle.hasSteam { return "Steam" }
        if bottle.hasEAApp { return "EA App" }
        if bottle.hasEpicGames { return "Epic" }
        return "Missing"
    }

    private var northstarStatusValue: String {
        guard let bottle = env.selectedBottle else { return "Not installed" }
        if bottle.hasNorthstar {
            return bottle.northstarVersion ?? "Ready"
        }
        return "Not installed"
    }

    // MARK: - Progress cards

    @ViewBuilder
    private func northstarProgressCard(_ p: NorthstarUpdater.Progress) -> some View {
        progressCard(
            phase: northstarPhaseLabel(p.phase),
            fraction: p.fraction,
            detail: p.detail,
            tint: .accentColor
        )
    }

    @ViewBuilder
    private func maximaProgressCard(_ p: MaximaService.Progress) -> some View {
        progressCard(
            phase: p.phase.label,
            fraction: p.fraction,
            detail: p.detail,
            tint: .accentColor
        )
    }

    @ViewBuilder
    private func progressCard(
        phase: String,
        fraction: Double,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase).stencilLabel()
                Spacer()
                Text(detail)
                    .font(TF.body(12))
                    .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
            }
            if fraction < 0 {
                ProgressView().progressViewStyle(.linear)
            } else {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(tint)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: .rect(cornerRadius: 18))
    }

    private func northstarPhaseLabel(_ phase: NorthstarUpdater.Progress.Phase) -> String {
        switch phase {
        case .fetchingReleases: return "FETCHING"
        case .downloading:      return "DOWNLOADING"
        case .extracting:       return "EXTRACTING"
        case .done:             return "DONE"
        }
    }

    // MARK: - Northstar / Vanilla actions

    private var actionsCard: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
                ForEach(NorthstarLauncher.LaunchMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)

            HStack(spacing: 12) {
                Button {
                    Task { await env.launch(mode: mode) }
                } label: {
                    Label(
                        env.launchInFlight ? "Launching…" : "Launch",
                        systemImage: "play.fill"
                    )
                    .font(TF.title(16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(
                    env.selectedBottle == nil
                    || env.launchInFlight
                    || env.selectedBottle?.hasTitanfall2 != true
                    || (mode == .northstar && env.selectedBottle?.hasNorthstar != true)
                    || (mode == .northstar && env.selectedBottle?.hasSteam != true)
                    || env.updating
                )

                // Install button: only when Northstar is absent.
                // Auto-update runs on each launch when it is already installed.
                if env.selectedBottle?.hasNorthstar != true {
                    Button {
                        Task { await env.installLatestNorthstar() }
                    } label: {
                        Label(
                            env.updating ? "Installing…" : "Install Northstar",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(TF.title(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .disabled(env.selectedBottle == nil || env.updating || env.launchInFlight)
                }

                // Uninstall button: only when Northstar is installed.
                if env.selectedBottle?.hasNorthstar == true {
                    Button {
                        confirmNorthstarUninstall = true
                    } label: {
                        Label(
                            env.updating ? "Removing…" : "Uninstall NS",
                            systemImage: env.updating ? "hourglass" : "trash"
                        )
                        .font(TF.title(14))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .disabled(env.selectedBottle == nil || env.updating || env.launchInFlight)
                    .confirmationDialog(
                        "Uninstall Northstar?",
                        isPresented: $confirmNorthstarUninstall,
                        titleVisibility: .visible
                    ) {
                        Button("Uninstall", role: .destructive) {
                            Task { await env.uninstallNorthstar() }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This removes NorthstarLauncher.exe, mods, and plugins from the bottle. Titanfall 2 itself is left intact and can be re-modded at any time.")
                    }
                }
            }
            .padding([.horizontal, .bottom], 18)
        }
        .padding(.top, 18)
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), in: .rect(cornerRadius: 22))
    }

    // MARK: - Maxima toggle card

    private var maximaToggleCard: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $env.maximaEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text("EA LAUNCHER (MAXIMA)")
                        .stencilLabel(color: Color.white.opacity(0.85))
                }
            }
            .toggleStyle(.switch)

            Button {
                showMaximaInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.primary.opacity(0.70))
            }
            .buttonStyle(.plain)
            .help("About Maxima")
            .popover(isPresented: $showMaximaInfo, arrowEdge: .top) {
                maximaInfoPopover
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accentSubtle)), in: .rect(cornerRadius: 18))
    }

    private var maximaInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("About Maxima", systemImage: "gamecontroller.fill")
                .font(TF.title(14))
                .foregroundStyle(.primary)

            Text("Maxima is an open-source replacement for the EA Desktop launcher. It runs inside your CrossOver bottle and handles EA authentication so Titanfall 2 can sign in without the full EA app.")
                .font(TF.body(12))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Text("This feature is currently in beta. Enable it only if you need EA account authentication — for example, if Titanfall 2 refuses to start without an EA login.")
                .font(TF.body(12))
                .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                .fixedSize(horizontal: false, vertical: true)

            Link("Learn more about Maxima →",
                 destination: URL(string: "https://github.com/AA-EION/Maxima-Draconis")!)
                .font(TF.body(12))
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Maxima card

    private var maximaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status pills
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
            .padding(.horizontal, 18)
            .padding(.top, 16)

            HStack(spacing: 12) {
                if env.maximaInstalled && env.maximaHelperRegistered {
                    Text("Maxima is ready. Use the Launch button above to start the game.")
                        .font(TF.body(12))
                        .foregroundStyle(.primary.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if env.maximaUpdateAvailable {
                        Button {
                            Task { await env.updateMaxima() }
                        } label: {
                            Label(
                                env.maximaSettingUp ? "Updating…" : "Update Maxima",
                                systemImage: env.maximaSettingUp ? "hourglass" : "arrow.up.circle.fill"
                            )
                            .font(TF.title(14))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.accentColor)
                        .disabled(env.selectedBottle == nil || env.maximaSettingUp)
                    }

                    Button {
                        Task { await env.uninstallMaxima() }
                    } label: {
                        Label(
                            env.maximaSettingUp ? "Uninstalling…" : "Uninstall",
                            systemImage: env.maximaSettingUp ? "hourglass" : "trash"
                        )
                        .font(TF.title(14))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 6)
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
                        .font(TF.title(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .disabled(
                        env.selectedBottle == nil
                        || env.maximaSettingUp
                        || env.selectedBottle?.hasTitanfall2 != true
                    )

                    if env.maximaHelperRegistered {
                        Button {
                            Task { await env.uninstallMaxima() }
                        } label: {
                            Label("Unregister", systemImage: "trash")
                                .font(TF.title(14))
                                .padding(.vertical, 12)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glass)
                        .disabled(env.maximaSettingUp)
                    }
                }
            }
            .padding([.horizontal, .bottom], 18)

            if !env.maximaInstalled || !env.maximaHelperRegistered {
                Text(maximaSetupNote)
                    .font(TF.body(11))
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accentMedium)), in: .rect(cornerRadius: 22))
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

    // MARK: - Error card

    @ViewBuilder
    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
            Text(msg)
                .foregroundStyle(.primary)
                .font(TF.body(13))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.red.opacity(DraconisTheme.Card.error)), in: .rect(cornerRadius: 14))
    }
}

#Preview {
    PlayView().environmentObject(AppEnvironment())
}
