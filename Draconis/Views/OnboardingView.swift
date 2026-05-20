import SwiftUI

private enum AutoStep { case creatingBottle, installingGame, done }
fileprivate enum StepState { case pending, active, done }

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private enum Page {
        case preflight     // CrossOver check / intro
        case sourceChoice  // pick install source (Maxima / EA / Steam / Epic)
        case progress      // installing bottle + launcher + game
        case maximaRole    // optional sub-step for Steam / EA → MaximaRole picker
    }

    @State private var page: Page = .preflight
    @State private var selectedSource: BottleInstaller.Frontend = .maxima
    @State private var selectedRole: MaximaRole = .fullReplace

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
                if page != .preflight {
                    Button("Back") {
                        stopWatching()
                        page = previousPage(from: page)
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
        .onDisappear {
            stopWatching()
        }
    }

    private func stopWatching() {
        env.cancelAutoBottleInstall()
    }

    private func previousPage(from p: Page) -> Page {
        switch p {
        case .preflight:    return .preflight
        case .sourceChoice: return .preflight
        case .progress:     return .sourceChoice
        case .maximaRole:   return .progress
        }
    }

    private var continueLabel: String {
        switch page {
        case .progress, .maximaRole:
            if case .done = env.autoInstallStage { return "Finish" }
            return "Skip"
        default: return "Continue"
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .preflight:    preflightPage
        case .sourceChoice: sourceChoicePage
        case .progress:     progressPage
        case .maximaRole:   maximaRolePage
        }
    }

    private var preflightPage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Set up Titanfall 2 in a CrossOver bottle", systemImage: "wineglass.fill")
                    .stencilLabel()

                if env.crossOverInstalled {
                    Text("Draconis creates a fresh win10_64 bottle, installs the launcher you pick, and walks you through getting Titanfall 2 installed inside it.")
                        .font(TF.body(11))
                        .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        page = .sourceChoice
                    } label: {
                        Label("Choose install source", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .padding(.top, 4)
                } else {
                    Text("CrossOver not detected. Install it and click Rescan.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                    Link("Download CrossOver →",
                         destination: URL(string: "https://www.codeweavers.com/crossover")!)
                        .font(TF.body(12))
                }
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), in: .rect(cornerRadius: 18))
    }

    private var sourceChoicePage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Where should the game come from?", systemImage: "shippingbox.fill")
                    .stencilLabel()

                Text("Each option drives a different chain of installers. Steam-installed Titanfall 2 binaries are signed with Steam CEG DRM that doesn't always run cleanly under Wine; pick Maxima or EA app if you want the smoothest path on macOS.")
                    .font(TF.body(11))
                    .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(BottleInstaller.Frontend.allCases) { f in
                    FrontendRow(
                        frontend: f,
                        selected: selectedSource == f,
                        onTap: { selectedSource = f }
                    )
                }

                if !selectedSource.summary.isEmpty {
                    Text(selectedSource.summary)
                        .font(TF.body(11))
                        .foregroundStyle(.primary.opacity(0.75))
                        .padding(10)
                        .background(Color.accentColor.opacity(DraconisTheme.Card.accent), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    env.startAutoBottleInstall(frontend: selectedSource)
                    page = .progress
                } label: {
                    Label("Start install", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(!selectedSource.available)
                .padding(.top, 4)
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), in: .rect(cornerRadius: 18))
    }

    private var progressPage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Installing", systemImage: "gearshape.2.fill")
                    .stencilLabel()

                ProgressStepRow(
                    title: "Create the bottle",
                    detail: "Draconis runs `cxbottle --create --template win10_64 --bottle \"Titanfall 2\"` to seed a fresh Wine prefix.",
                    state: stageState(.creatingBottle)
                )
                ProgressStepRow(
                    title: stepTwoTitle,
                    detail: stepTwoDetail,
                    state: stageState(.installingGame)
                )
                ProgressStepRow(
                    title: "Ready to launch",
                    detail: "Draconis has detected Titanfall 2 inside the bottle.",
                    state: stageState(.done)
                )

                if let bottle = env.bottles.first(where: { $0.hasLauncher || $0.hasTitanfall2 }) {
                    Text("Detected bottle: \(bottle.name)")
                        .font(TF.body(11))
                        .foregroundStyle(.primary.opacity(0.70))
                }

                if shouldOfferMaximaRoleStep, case .done = env.autoInstallStage {
                    Button {
                        page = .maximaRole
                    } label: {
                        Label("Next: choose Maxima role", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .padding(.top, 4)
                }
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), in: .rect(cornerRadius: 18))
    }

    /// Sub-picker shown only when the user installed via EA app or Steam.
    /// Lets them decide whether to layer Maxima on top of that install:
    /// none (use the launcher's native auth), authOnly (replace the
    /// link2ea handler with Maxima but leave binaries alone), or
    /// fullReplace (also overwrite the CEG-signed launcher binaries with
    /// the EA originals — Steam only).
    private var maximaRolePage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("How should Maxima help?", systemImage: "key.fill")
                    .stencilLabel()

                Text("You installed Titanfall 2 via \(selectedSource.displayName). Maxima can sit alongside it as the EA-auth handler, or stay out of the picture entirely.")
                    .font(TF.body(11))
                    .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(availableRoles, id: \.self) { role in
                    RoleRow(
                        role: role,
                        source: selectedSource,
                        selected: selectedRole == role,
                        onTap: { selectedRole = role }
                    )
                }

                Button {
                    let role = selectedRole
                    Task {
                        if let bottle = env.selectedBottle ?? env.bottles.first(where: { $0.hasTitanfall2 }) {
                            await env.applyMaximaRole(role, in: bottle)
                        }
                    }
                } label: {
                    Label(env.applyingMaximaRole ? "Applying…" : "Apply",
                          systemImage: env.applyingMaximaRole ? "hourglass" : "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(env.applyingMaximaRole)
                .padding(.top, 4)

                if let err = env.maximaRoleError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(18)
        }
        .glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), in: .rect(cornerRadius: 18))
    }

    // MARK: - Helpers

    /// Steam can have the CEG fix applied; EA can't (no CEG binaries).
    /// Maxima-installed games already are the EA originals — Maxima is
    /// the launcher, no role picker needed (handled by skipping this
    /// page entirely).
    private var availableRoles: [MaximaRole] {
        switch selectedSource {
        case .steam: return [.fullReplace, .authOnly, .none]
        case .ea:    return [.authOnly, .none]
        default:     return []
        }
    }

    private var shouldOfferMaximaRoleStep: Bool {
        selectedSource == .steam || selectedSource == .ea
    }

    private var stepTwoTitle: String {
        switch selectedSource {
        case .steam:  return "Install Steam, then Titanfall 2"
        case .ea:     return "Install EA app, then Titanfall 2"
        case .maxima: return "Maxima downloads Titanfall 2"
        case .epic:   return "Install Epic Games Launcher, then Titanfall 2"
        }
    }

    private var stepTwoDetail: String {
        switch selectedSource {
        case .steam:
            return "Steam downloads inside the bottle. Log into Steam, install Titanfall 2, and wait for it to reach 100%. Then run the game once so Steam's bundled EA setup completes before continuing."
        case .ea:
            return "EA app downloads inside the bottle. Log in, install Titanfall 2, run the game once so EA Desktop's auto-setup finishes, then continue."
        case .maxima:
            return "Maxima downloads Titanfall 2 directly from EA's servers — no Steam, no EA Desktop. Requires the game to be in your EA library (purchased directly from EA, or Steam/Epic linked + synced at least once)."
        case .epic:
            return "Epic Games path is documented but not yet wired up in the wizard. Install Epic + Titanfall 2 manually for now."
        }
    }

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
                    .foregroundStyle(frontend.available ? Color.accentColor : Color.primary.opacity(0.25))
                Text(frontend.displayName)
                    .font(TF.title(13))
                    .foregroundStyle(frontend.available ? Color.primary : Color.primary.opacity(0.35))
                if !frontend.available {
                    Text("— coming soon")
                        .font(TF.body(11))
                        .foregroundStyle(.primary.opacity(0.35))
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

private struct RoleRow: View {
    let role: MaximaRole
    let source: BottleInstaller.Frontend
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(role.displayName).font(.body.weight(.semibold))
                        if role == .fullReplace {
                            Text("Recommended")
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(role.detail(for: source))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var circleFill: Color {
        switch state {
        case .done:   return .white.opacity(DraconisTheme.Card.pillActive)
        case .active: return .accentColor.opacity(0.25)
        case .pending: return .primary.opacity(0.08)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
        case .active:
            ProgressView().controlSize(.small)
        case .pending:
            Image(systemName: "circle.dotted")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
        }
    }
}
