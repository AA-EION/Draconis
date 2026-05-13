import SwiftUI

struct PlayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var mode: NorthstarLauncher.LaunchMode = .northstar

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                heroCard
                bottleStatusCard
                if let p = env.updateProgress  { northstarProgressCard(p) }
                if let p = env.maximaProgress  { maximaProgressCard(p) }
                if let err = env.lastUpdateError ?? env.lastLaunchError ?? env.maximaError {
                    errorCard(err)
                }
                actionsCard
                maximaCard
                Spacer(minLength: 60)
            }
            .padding(28)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DRACONIS")
                .font(TF.hero(48))
                .tracking(8)
                .foregroundStyle(.white)
            Text("Titanfall 2 + Northstar launcher for macOS Tahoe.")
                .font(TF.title(16))
                .foregroundStyle(.white.opacity(0.78))
            if let bottle = env.selectedBottle {
                Label(
                    "\(bottle.name) — \(bottle.backend.displayName)",
                    systemImage: bottle.backend.symbolName
                )
                .font(TF.body(12))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(0.10)).interactive(),
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
                tone: env.selectedBottle?.hasTitanfall2 == true ? .green : .orange
            )
            StatusPill(
                label: "Northstar",
                value: env.selectedBottle?.hasNorthstar == true ? "Ready" : "Not installed",
                symbol: env.selectedBottle?.hasNorthstar == true
                    ? "bolt.shield.fill" : "questionmark.diamond.fill",
                tone: env.selectedBottle?.hasNorthstar == true ? .green : .orange
            )
            StatusPill(
                label: "Backend",
                value: env.selectedBottle?.backend.displayName ?? "—",
                symbol: env.selectedBottle?.backend.symbolName ?? "questionmark.folder",
                tone: .accent
            )
        }
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
            tint: .orange
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
                    .foregroundStyle(.white.opacity(0.75))
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
                    || (mode == .northstar && env.selectedBottle?.hasNorthstar != true)
                )

                Button {
                    Task { await env.installLatestNorthstar() }
                } label: {
                    Label(
                        env.updating ? "Installing…" : "Install / Update Northstar",
                        systemImage: "arrow.down.circle.fill"
                    )
                    .font(TF.title(14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .disabled(env.selectedBottle == nil || env.updating)
            }
            .padding([.horizontal, .bottom], 18)
        }
        .padding(.top, 18)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 22))
    }

    // MARK: - Maxima card

    private var maximaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.orange.opacity(0.85))
                Text("EA (MAXIMA)")
                    .stencilLabel(color: .orange.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Status pills
            HStack(spacing: 10) {
                StatusPill(
                    label: "MaximaHelper",
                    value: env.maximaHelperRegistered ? "Registered" : "Not registered",
                    symbol: env.maximaHelperRegistered
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    tone: env.maximaHelperRegistered ? .green : .orange
                )
                StatusPill(
                    label: "Maxima",
                    value: env.maximaInstalled ? "Installed" : "Not installed",
                    symbol: env.maximaInstalled
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    tone: env.maximaInstalled ? .green : .orange
                )
            }
            .padding(.horizontal, 18)

            // Action row
            HStack(spacing: 12) {
                if env.maximaInstalled && env.maximaHelperRegistered {
                    // Ready — show launch button
                    Button {
                        Task { await env.launchMaxima() }
                    } label: {
                        Label(
                            env.maximaInFlight ? "Launching…" : "Launch with EA",
                            systemImage: env.maximaInFlight ? "hourglass" : "play.fill"
                        )
                        .font(TF.title(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .disabled(
                        env.selectedBottle == nil
                        || env.maximaInFlight
                        || env.selectedBottle?.hasTitanfall2 != true
                    )
                } else {
                    // Not ready — show setup button
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
                    .tint(.orange)
                    .disabled(
                        env.selectedBottle == nil
                        || env.maximaSettingUp
                        || env.selectedBottle?.hasTitanfall2 != true
                    )
                }
            }
            .padding([.horizontal, .bottom], 18)

            // Info note when not set up
            if !env.maximaInstalled || !env.maximaHelperRegistered {
                Text(maximaSetupNote)
                    .font(TF.body(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .glassEffect(.regular.tint(.orange.opacity(0.06)), in: .rect(cornerRadius: 22))
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
                .foregroundStyle(.white)
                .font(TF.body(13))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.red.opacity(0.18)), in: .rect(cornerRadius: 14))
    }
}

#Preview {
    PlayView().environmentObject(AppEnvironment())
}
