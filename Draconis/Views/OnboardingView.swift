import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("DRACONIS")
                .font(TF.hero(34))
                .tracking(8)
            Text("Pick a Wine runtime to launch Titanfall 2 + Northstar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(TF.body(13))

            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Runtimes", systemImage: "magnifyingglass.circle.fill")
                        .stencilLabel()
                    ForEach(WineBackend.allCases) { backend in
                        OnboardingBackendRow(backend: backend)
                    }
                }
                .padding(18)
            }
            .glassEffect(.regular.tint(.white.opacity(0.04)),
                         in: .rect(cornerRadius: 18))

            if env.availableBackends.contains(.crossover) {
                Button {
                    Task { await env.createCrossOverTitanfallBottle() }
                } label: {
                    Label(
                        env.creatingBottle
                            ? "Creating Titanfall 2 bottle in CrossOver…"
                            : "Create Titanfall 2 bottle in CrossOver",
                        systemImage: "wineglass.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(env.creatingBottle)
                if let err = env.bottleCreationError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } else if env.availableBackends.isEmpty {
                Text("No runtimes detected. Install one above or click Rescan.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text("Detected \(env.availableBackends.count) runtime(s) and \(env.bottles.count) bottle(s).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Rescan") {
                    Task { await env.refreshBackends(); await env.refreshBottles() }
                }
                .buttonStyle(.glass)

                Button("Continue") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .keyboardShortcut(.return)
            }
        }
        .padding(28)
    }
}

private struct OnboardingBackendRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let backend: WineBackend

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: backend.symbolName)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(backend.displayName).font(TF.title(13))
                Text(backend.isPaid ? "Paid" : "Free / open source")
                    .font(TF.body(10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if env.availableBackends.contains(backend) {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(TF.body(11))
            } else if backend.isPaid {
                Link("Get CrossOver",
                     destination: URL(string: "https://www.codeweavers.com/crossover")!)
                    .font(TF.body(11))
            } else {
                Button {
                    Task { await env.installBackend(backend) }
                } label: {
                    if env.installingBackend == backend {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Install", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(env.installingBackend != nil)
            }
        }
        .padding(.vertical, 4)
    }
}
