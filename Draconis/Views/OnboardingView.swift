import SwiftUI

private enum AutoStep { case creatingBottle, installingGame, done }
fileprivate enum StepState { case pending, active, done }

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private enum Page {
        case modeChoice
        case manual
        case frontendChoice
        case autoProgress
    }

    @State private var page: Page = .modeChoice
    @State private var frontend: BottleInstaller.Frontend = .steam

    var body: some View {
        VStack(spacing: 18) {
            Text("DRACONIS")
                .font(TF.hero(34))
                .tracking(8)
            Text("Native macOS launcher for Titanfall 2 + Northstar via CrossOver.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(TF.body(13))

            content
                .frame(maxWidth: .infinity)

            HStack {
                if page != .modeChoice {
                    Button("Back") {
                        if page == .autoProgress { env.cancelAutoBottleInstall() }
                        page = (page == .frontendChoice || page == .manual) ? .modeChoice : .frontendChoice
                    }
                    .buttonStyle(.glass)
                }

                Button("Rescan") {
                    Task {
                        await env.refreshCrossOverState()
                        await env.refreshBottles()
                    }
                }
                .buttonStyle(.glass)

                Button(continueLabel) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .keyboardShortcut(.return)
            }
        }
        .padding(28)
        .frame(minWidth: 520)
        .onDisappear { env.cancelAutoBottleInstall() }
    }

    private var continueLabel: String {
        switch page {
        case .autoProgress:
            if case .done = env.autoInstallStage { return "Finish" }
            return "Skip"
        default: return "Continue"
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .modeChoice:     modeChoicePage
        case .manual:         manualPage
        case .frontendChoice: frontendChoicePage
        case .autoProgress:   autoProgressPage
        }
    }

    private var modeChoicePage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Create the Titanfall 2 bottle", systemImage: "wineglass.fill")
                    .stencilLabel()

                if env.crossOverInstalled {
                    Text("Pick how you'd like to set up the CrossOver bottle. Both routes end with Titanfall 2 installed inside a win10_64 bottle that Draconis can launch.")
                        .font(TF.body(11))
                        .foregroundStyle(.white.opacity(0.65))

                    ChoiceCard(
                        icon: "sparkles",
                        title: "Automatic",
                        detail: "Draconis hands CrossOver the signed Titanfall 2 crosstie and watches every 5 s until the bottle is ready.",
                        action: { page = .frontendChoice }
                    )
                    ChoiceCard(
                        icon: "hand.point.up.left.fill",
                        title: "Manual",
                        detail: "Open CrossOver yourself and follow the install profile. Useful if you're using EA app instead of Steam.",
                        action: { page = .manual }
                    )
                } else {
                    Text("CrossOver not detected at /Applications/CrossOver.app.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Link("Download CrossOver →",
                         destination: URL(string: "https://www.codeweavers.com/crossover")!)
                        .font(TF.body(12))
                }
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
    }

    private var manualPage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Label("Manual setup", systemImage: "list.number")
                    .stencilLabel()

                StepRow(
                    number: 1,
                    title: "Open CrossOver",
                    body: "Use CrossOver's built-in Titanfall 2 install profile — it picks the right win10_64 template automatically.",
                    done: env.bottles.contains(where: \.hasTitanfall2)
                )
                StepRow(
                    number: 2,
                    title: "Pick a frontend inside the bottle",
                    body: "Steam: sign in and install Titanfall 2 from your library.\nEA app: install the EA app inside the bottle, sign in, and install Titanfall 2 from there.\nEither way Draconis picks it up.",
                    done: env.bottles.contains(where: \.hasTitanfall2)
                )
                StepRow(
                    number: 3,
                    title: "Set up Maxima",
                    body: "Once Titanfall 2 is installed, click Set up Maxima from the EA card on the Play tab.",
                    done: env.maximaInstalled && env.maximaHelperRegistered
                )

                Button {
                    env.openCrossOver()
                } label: {
                    Label("Open CrossOver", systemImage: "wineglass.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .padding(.top, 4)
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
    }

    private var frontendChoicePage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Choose installer frontend", systemImage: "shippingbox.fill")
                    .stencilLabel()

                Text("Where do you own Titanfall 2? Draconis will start the CrossOver install for that store.")
                    .font(TF.body(11))
                    .foregroundStyle(.white.opacity(0.65))

                ForEach(BottleInstaller.Frontend.allCases) { f in
                    FrontendRow(
                        frontend: f,
                        selected: frontend == f,
                        onTap: { frontend = f }
                    )
                }

                Button {
                    env.startAutoBottleInstall(frontend: frontend)
                    page = .autoProgress
                } label: {
                    Label("Start install", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(!frontend.available)
                .padding(.top, 4)
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
    }

    private var autoProgressPage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Installing", systemImage: "gearshape.2.fill")
                    .stencilLabel()

                ProgressStepRow(
                    title: "CrossOver creates the bottle and installs Steam",
                    detail: "Draconis polls CrossOver's bottles every 5 seconds, waiting for steam.exe to appear.",
                    state: stageState(.creatingBottle)
                )
                ProgressStepRow(
                    title: "You install Titanfall 2 from Steam",
                    detail: "When Steam opens inside the bottle, log in and install Titanfall 2. Wait for it to reach 100% before continuing.",
                    state: stageState(.installingGame)
                )
                ProgressStepRow(
                    title: "Ready to launch",
                    detail: "Draconis has found Titanfall2.exe inside the bottle.",
                    state: stageState(.done)
                )

                if let bottle = env.bottles.first(where: { $0.hasSteam }) {
                    Text("Detected bottle: \(bottle.name)")
                        .font(TF.body(11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
    }

    // MARK: - Stage helpers

    private func stageState(_ step: AutoStep) -> StepState {
        switch (env.autoInstallStage, step) {
        case (.waitingForBottle, .creatingBottle):     return .active
        case (.waitingForBottle, _):                   return .pending
        case (.waitingForTitanfall, .creatingBottle):  return .done
        case (.waitingForTitanfall, .installingGame):  return .active
        case (.waitingForTitanfall, .done):            return .pending
        case (.done, .done):                           return .done
        case (.done, _):                               return .done
        case (nil, _):                                 return .pending
        }
    }
}

// MARK: - Subviews

private struct ChoiceCard: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(TF.title(13))
                    Text(detail)
                        .font(TF.body(11))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
            }
            .padding(12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FrontendRow: View {
    let frontend: BottleInstaller.Frontend
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: { if frontend.available { onTap() } }) {
            HStack(spacing: 12) {
                Image(systemName: selected && frontend.available
                      ? "largecircle.fill.circle"
                      : "circle")
                    .foregroundStyle(frontend.available ? Color.accentColor : Color.white.opacity(0.25))
                Text(frontend.displayName)
                    .font(TF.title(13))
                    .foregroundStyle(frontend.available ? .white : .white.opacity(0.35))
                if !frontend.available {
                    Text("— coming soon")
                        .font(TF.body(11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!frontend.available)
    }
}

private struct ProgressStepRow: View {
    let title: String
    let detail: String
    let state: StepState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 26, height: 26)
                icon
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TF.title(13))
                Text(detail)
                    .font(TF.body(11))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var circleFill: Color {
        switch state {
        case .done:   return .green.opacity(0.25)
        case .active: return .accentColor.opacity(0.25)
        case .pending: return .white.opacity(0.08)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
        case .active:
            ProgressView().controlSize(.small)
        case .pending:
            Image(systemName: "circle.dotted")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool

    init(number: Int, title: String, body: String, done: Bool) {
        self.number = number
        self.title = title
        self.detail = body
        self.done = done
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
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
