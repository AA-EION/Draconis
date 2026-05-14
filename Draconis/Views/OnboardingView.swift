import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("DRACONIS")
                .font(TF.hero(34))
                .tracking(8)
            Text("Native macOS launcher for Titanfall 2 + Northstar via CrossOver.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(TF.body(13))

            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Setup", systemImage: "list.number")
                        .stencilLabel()

                    StepRow(
                        number: 1,
                        title: "Install CrossOver",
                        body: "Required — Draconis runs the game inside a CrossOver bottle. Use the link below if you don't have it yet.",
                        done: env.crossOverInstalled,
                        link: env.crossOverInstalled ? nil : URL(string: "https://www.codeweavers.com/crossover")
                    )
                    StepRow(
                        number: 2,
                        title: "Create a Titanfall 2 bottle in CrossOver",
                        body: "Open CrossOver and use its built-in Titanfall 2 install profile — it picks the right win10_64 template and installs Steam for you.",
                        done: env.bottles.contains(where: \.hasTitanfall2)
                    )
                    StepRow(
                        number: 3,
                        title: "Install Titanfall 2 from your Steam library",
                        body: "Inside the bottle, sign in to Steam and install Titanfall 2. Draconis will pick it up automatically.",
                        done: env.bottles.contains(where: \.hasTitanfall2)
                    )
                    StepRow(
                        number: 4,
                        title: "Set up Maxima",
                        body: "Once Titanfall 2 is installed, click Set up Maxima from the EA card on the Play tab — it bypasses the EA Desktop requirement.",
                        done: env.maximaInstalled && env.maximaHelperRegistered
                    )
                }
                .padding(18)
            }
            .glassEffect(.regular.tint(.white.opacity(0.04)),
                         in: .rect(cornerRadius: 18))

            if env.crossOverInstalled {
                Button {
                    env.openCrossOver()
                } label: {
                    Label("Open CrossOver", systemImage: "wineglass.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Text("CrossOver not detected. Install it and click Rescan.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Rescan") {
                    Task {
                        await env.refreshCrossOverState()
                        await env.refreshBottles()
                    }
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

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    var link: URL? = nil

    init(number: Int, title: String, body: String, done: Bool, link: URL? = nil) {
        self.number = number
        self.title = title
        self.detail = body
        self.done = done
        self.link = link
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.25) : Color.white.opacity(0.08))
                    .frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TF.title(13))
                Text(detail)
                    .font(TF.body(11))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Link("codeweavers.com →", destination: link)
                        .font(TF.body(11))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
