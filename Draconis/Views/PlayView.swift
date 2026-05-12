import SwiftUI

struct PlayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var mode: NorthstarLauncher.LaunchMode = .northstar

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroCard
                bottleStatusCard
                if env.lastLaunchError != nil { errorCard }
                actionsCard
                Spacer(minLength: 60)
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private var heroCard: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("DRACONIS")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(.white)
                Text("Titanfall 2 + Northstar launcher for macOS Tahoe.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                if let bottle = env.selectedBottle {
                    Label("Active bottle: \(bottle.name) — \(bottle.backend.displayName)",
                          systemImage: bottle.backend.symbolName)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .glassEffect(
            .regular.tint(.accentColor.opacity(0.35)).interactive(),
            in: .rect(cornerRadius: 28)
        )
    }

    private var bottleStatusCard: some View {
        GlassEffectContainer {
            HStack(spacing: 24) {
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
            .padding(24)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var actionsCard: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(NorthstarLauncher.LaunchMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                HStack(spacing: 14) {
                    Button {
                        Task { await env.launch(mode: mode) }
                    } label: {
                        Label(
                            env.launchInFlight ? "Launching…" : "Launch",
                            systemImage: "play.fill"
                        )
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
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
                            env.updating ? "Updating…" : "Install / Update Northstar",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.glass)
                    .disabled(env.selectedBottle == nil || env.updating)
                }
                .padding([.horizontal, .bottom], 24)
            }
            .padding(.top, 20)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var errorCard: some View {
        HStack {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
            Text(env.lastLaunchError ?? "")
                .foregroundStyle(.white)
                .font(.callout)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.red.opacity(0.45)), in: .capsule)
    }
}

#Preview {
    PlayView().environmentObject(AppEnvironment())
}
