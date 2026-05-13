import SwiftUI

struct PlayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var mode: NorthstarLauncher.LaunchMode = .northstar

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                heroCard
                bottleStatusCard
                if let p = env.updateProgress { progressCard(p) }
                if let err = env.lastUpdateError ?? env.lastLaunchError {
                    errorCard(err)
                }
                actionsCard
                Spacer(minLength: 60)
            }
            .padding(28)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Cards

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

    @ViewBuilder
    private func progressCard(_ p: NorthstarUpdater.Progress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phaseLabel(p.phase)).stencilLabel()
                Spacer()
                Text(p.detail)
                    .font(TF.body(12))
                    .foregroundStyle(.white.opacity(0.75))
            }
            if p.fraction < 0 {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: p.fraction)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(.accentColor.opacity(0.10)),
                     in: .rect(cornerRadius: 18))
    }

    private func phaseLabel(_ phase: NorthstarUpdater.Progress.Phase) -> String {
        switch phase {
        case .fetchingReleases:  return "FETCHING"
        case .downloading:       return "DOWNLOADING"
        case .extracting:        return "EXTRACTING"
        case .done:              return "DONE"
        }
    }

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
                    || (mode == .northstar
                        && env.selectedBottle?.hasNorthstar != true)
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
        .glassEffect(.regular.tint(.white.opacity(0.04)),
                     in: .rect(cornerRadius: 22))
    }

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
        .glassEffect(.regular.tint(.red.opacity(0.18)),
                     in: .rect(cornerRadius: 14))
    }
}

#Preview {
    PlayView().environmentObject(AppEnvironment())
}
