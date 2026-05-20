import SwiftUI

private enum AutoStep { case creatingBottle, installingGame, done }
fileprivate enum StepState { case pending, active, done }

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private enum Page {
        case preflight     // CrossOver check / intro
        case bottleChoice  // shown only when existing bottles are detected
        case sourceChoice  // pick install source (Maxima / EA / Steam / Epic)
        case progress      // installing bottle + launcher + game
        case maximaRole    // optional sub-step for Steam / EA → MaximaRole picker
    }

    @State private var page: Page = .preflight
    @State private var selectedSource: BottleInstaller.Frontend = .maxima
    @State private var selectedRole: MaximaRole = .fullReplace

    /// User's choice on the `bottleChoice` page. `nil` until they've
    /// either picked an existing bottle or chosen "Create new bottle".
    /// When non-nil and pointing at an existing bottle, the wizard
    /// skips bottle creation; when nil + the user chose "Create new",
    /// `pendingNewBottleName` carries the auto-suffixed name for
    /// `startAutoBottleInstall`.
    @State private var selectedExistingBottle: WineBottle?

    /// Pre-computed unique bottle name for the "Create new" branch.
    /// Resolved once when the user lands on `bottleChoice` so the
    /// label can show it ("Create new bottle (Titanfall 2 (2))") and
    /// `startAutoBottleInstall` can reuse it without recomputing.
    @State private var pendingNewBottleName: String = "Titanfall 2"

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
        case .bottleChoice: return .preflight
        case .sourceChoice:
            // If we got here from bottleChoice (because the user picked
            // "Create new" or chose an empty existing bottle), Back
            // should return to that picker. Otherwise we came straight
            // from preflight (no existing bottles).
            return env.bottles.isEmpty ? .preflight : .bottleChoice
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
        case .bottleChoice: bottleChoicePage
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
                    Text(preflightBlurb)
                        .font(TF.body(11))
                        .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        advanceFromPreflight()
                    } label: {
                        Label(preflightButtonLabel,
                              systemImage: "arrow.right.circle.fill")
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

    /// Picker shown when Draconis already detected one or more
    /// CrossOver bottles on this Mac. Lets the user "Use this bottle"
    /// (which scans it and routes to whichever step is missing) or
    /// "Create new bottle" (with an auto-suffixed name to avoid the
    /// `bottleAlreadyExists` collision). Skipped entirely on a fresh
    /// install where `env.bottles` is empty.
    private var bottleChoicePage: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Use an existing bottle?", systemImage: "wineglass")
                    .stencilLabel()

                Text("Draconis found \(env.bottles.count == 1 ? "a CrossOver bottle" : "\(env.bottles.count) CrossOver bottles") on this Mac. Pick one to scan and pick up where the previous setup left off, or create a brand-new bottle alongside.")
                    .font(TF.body(11))
                    .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(env.bottles) { bottle in
                    ExistingBottleRow(
                        bottle: bottle,
                        selected: selectedExistingBottle?.id == bottle.id,
                        onTap: { selectedExistingBottle = bottle }
                    )
                }

                // "Create new bottle" row. Selected when
                // `selectedExistingBottle == nil`.
                CreateNewBottleRow(
                    bottleName: pendingNewBottleName,
                    selected: selectedExistingBottle == nil,
                    onTap: { selectedExistingBottle = nil }
                )

                Button {
                    if let bottle = selectedExistingBottle {
                        useExistingBottle(bottle)
                    } else {
                        page = .sourceChoice
                    }
                } label: {
                    Label(selectedExistingBottle == nil
                            ? "Create new bottle"
                            : "Use this bottle",
                          systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .padding(.top, 4)
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
                    // When the user came through bottleChoice and
                    // picked "Create new", we already have a fresh
                    // auto-suffixed name. Otherwise fall back to
                    // the default ("Titanfall 2") which is fine for
                    // first-run.
                    let name = env.bottles.isEmpty ? nil : pendingNewBottleName
                    env.startAutoBottleInstall(frontend: selectedSource, bottleName: name)
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

    /// Intro copy that adapts to whether Draconis already found
    /// CrossOver bottles on this Mac. When bottles exist, the next
    /// step is a chooser; when none exist, the wizard creates one.
    private var preflightBlurb: String {
        if env.bottles.isEmpty {
            return "Draconis creates a fresh win10_64 bottle, installs the launcher you pick, and walks you through getting Titanfall 2 installed inside it."
        } else if env.bottles.count == 1 {
            return "Draconis found a CrossOver bottle already on this Mac. The next step lets you reuse it (scan + pick up where the previous setup left off) or create a new bottle alongside."
        } else {
            return "Draconis found \(env.bottles.count) CrossOver bottles already on this Mac. The next step lets you reuse one (scan + pick up where the previous setup left off) or create a new bottle alongside."
        }
    }

    private var preflightButtonLabel: String {
        env.bottles.isEmpty
            ? "Choose install source"
            : "Choose existing or new bottle"
    }

    /// Continue from the preflight page. With no existing bottles we
    /// go straight to the source picker; with one or more, we surface
    /// the chooser first.
    private func advanceFromPreflight() {
        if env.bottles.isEmpty {
            page = .sourceChoice
        } else {
            pendingNewBottleName = nextAvailableBottleName(from: "Titanfall 2")
            // Default selection: highlight the bottle that already
            // looks the most "ready" so a single Enter press is the
            // common-case action.
            selectedExistingBottle = env.bottles.first(where: \.hasTitanfall2)
                ?? env.bottles.first(where: \.hasLauncher)
                ?? env.bottles.first
            page = .bottleChoice
        }
    }

    /// User picked an existing bottle on the bottleChoice page and
    /// hit Continue. Mark it as the selected bottle, infer the install
    /// source from whichever launcher is already in it, then route to
    /// whichever step is still missing.
    private func useExistingBottle(_ bottle: WineBottle) {
        env.selectedBottleID = bottle.id
        if let inferred = inferredSource(for: bottle) {
            selectedSource = inferred
        }
        switch nextPageForExistingBottle(bottle) {
        case .dismiss:
            dismiss()
        case .maximaRole:
            page = .maximaRole
        case .progress:
            env.resumeAutoWatching(forBottle: bottle)
            page = .progress
        case .sourceChoice:
            page = .sourceChoice
        }
    }

    /// Inferred install source for a bottle whose launcher already
    /// landed. Matches the precedence used by the source picker (most
    /// reliable on macOS first). `nil` when none of the known
    /// launchers / Maxima are present.
    private func inferredSource(for bottle: WineBottle) -> BottleInstaller.Frontend? {
        if bottle.hasMaxima  { return .maxima }
        if bottle.hasEAApp   { return .ea }
        if bottle.hasSteam   { return .steam }
        if bottle.hasEpicGames { return .epic }
        return nil
    }

    /// Where the wizard should land after a user picks an existing
    /// bottle.
    private enum ExistingBottleRoute {
        /// Bottle already has TF2 + an explicit MaximaRole — nothing
        /// to do, close the wizard.
        case dismiss
        /// Bottle has TF2 but no role saved yet → role picker.
        case maximaRole
        /// Bottle has a launcher but no TF2 yet → watcher page so the
        /// user can install TF2 inside their launcher.
        case progress
        /// Bottle is bare (no launcher, no game) → source picker.
        case sourceChoice
    }

    private func nextPageForExistingBottle(_ bottle: WineBottle) -> ExistingBottleRoute {
        if bottle.hasTitanfall2 {
            return MaximaRole.isExplicitlySet(forBottle: bottle.id)
                ? .dismiss
                : .maximaRole
        }
        if bottle.hasLauncher {
            return .progress
        }
        return .sourceChoice
    }

    /// Find the first bottle name not yet present on disk by
    /// suffixing `(N)` from N=2 upward. The picker only enters this
    /// path when at least one bottle already exists, so the first
    /// candidate is almost always `(2)`.
    private func nextAvailableBottleName(from base: String) -> String {
        if !WineBottleCreator.shared.bottleExists(named: base) { return base }
        var n = 2
        while WineBottleCreator.shared.bottleExists(named: "\(base) (\(n))") {
            n += 1
            // Defensive guard — we should never get here, but
            // refusing to loop forever beats spinning the UI.
            if n > 999 { return "\(base) (\(n))" }
        }
        return "\(base) (\(n))"
    }

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

/// Row used on the `bottleChoice` page for each existing bottle.
/// Shows the bottle name + a horizontal strip of small status chips
/// summarising what's already inside (TF2, Northstar, Steam, EA App,
/// Epic, Maxima) so the user can tell at a glance whether the bottle
/// is "ready to launch" or "halfway through setup".
private struct ExistingBottleRow: View {
    let bottle: WineBottle
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(bottle.name)
                        .font(.body.weight(.semibold))
                    HStack(spacing: 6) {
                        if bottle.hasTitanfall2 { chip("Titanfall 2",  "gamecontroller") }
                        if bottle.hasNorthstar  { chip("Northstar",    "star.fill") }
                        if bottle.hasMaxima     { chip("Maxima",       "key.fill") }
                        if bottle.hasSteam      { chip("Steam",        "shippingbox.fill") }
                        if bottle.hasEAApp      { chip("EA app",       "person.2.fill") }
                        if bottle.hasEpicGames  { chip("Epic",         "gamecontroller.fill") }
                        if !bottle.hasTitanfall2 && !bottle.hasLauncher && !bottle.hasMaxima {
                            Text("empty bottle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ label: String, _ symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(label).font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

/// "Create new bottle" row alongside the existing-bottle rows.
/// Shows the auto-suffixed name that will be used so the user knows
/// up front it won't collide with the bottle(s) already on disk.
private struct CreateNewBottleRow: View {
    let bottleName: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a new bottle")
                        .font(.body.weight(.semibold))
                    Text("Name: \(bottleName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
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
