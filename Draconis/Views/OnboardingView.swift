import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Text("Welcome to Draconis")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Draconis launches Titanfall 2 + Northstar on macOS using the best available Wine backend.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Backend detection", systemImage: "magnifyingglass.circle.fill")
                        .font(.headline)
                    ForEach(WineBackend.allCases) { backend in
                        HStack {
                            Label(backend.displayName, systemImage: backend.symbolName)
                            Spacer()
                            if env.availableBackends.contains(backend) {
                                Text("ready").foregroundStyle(.green)
                            } else {
                                Text("not found").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 18))

            if env.availableBackends.isEmpty {
                Text("Install CrossOver, GPTK, or Kegworks, then click Rescan.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text("Detected \(env.availableBackends.count) backend(s) and \(env.bottles.count) bottle(s).")
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
        .padding(36)
    }
}
