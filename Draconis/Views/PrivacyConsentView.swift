import SwiftUI
import AppKit

struct PrivacyConsentView: View {
    @EnvironmentObject private var env: AppEnvironment

    enum Tab: String, CaseIterable, Identifiable {
        case privacy = "Privacy Notice"
        case license = "License (GPL-3.0)"
        var id: String { rawValue }
    }

    @State private var activeTab: Tab = .privacy
    @State private var visitedTabs: Set<Tab> = [.privacy]

    private var allTabsVisited: Bool { visitedTabs.count == Tab.allCases.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Divider().overlay(.primary.opacity(0.10))

            // ScrollView insets bottom so content never hides behind action row
            ScrollView {
                Group {
                    switch activeTab {
                    case .privacy: privacyBody
                    case .license: licenseBody
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }

            Divider().overlay(.primary.opacity(0.10))
            actionRow
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.top, 32)

            Text("Before you continue")
                .font(TF.hero(24))

            Text("Read both tabs, then accept to launch Draconis.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    // MARK: - Tab picker (native segmented)

    private var tabPicker: some View {
        Picker("", selection: Binding(
            get: { activeTab },
            set: { tab in
                activeTab = tab
                visitedTabs.insert(tab)
            }
        )) {
            ForEach(Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("Decline & Quit") {
                ConsentManager.revoke()
                NSApp.terminate(nil)
            }
            .buttonStyle(.glass)

            Spacer()

            if !allTabsVisited {
                Text("Read both tabs to continue.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                ConsentManager.accept()
                env.privacyConsentAccepted = true
            } label: {
                Text("I accept — Continue")
                    .font(TF.title(13).weight(.semibold))
                    .foregroundStyle(allTabsVisited ? .black : .primary.opacity(0.35))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(allTabsVisited ? Color.white : Color.primary.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!allTabsVisited)
            .animation(.easeInOut(duration: 0.2), value: allTabsVisited)
        }
    }

    // MARK: - Privacy Notice

    private var privacyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            card(title: "What Draconis collects", icon: "tray.and.arrow.up") {
                VStack(alignment: .leading, spacing: 5) {
                    bullet("Crash reports and handled errors (via Sentry)")
                    bullet("Bottle state: Titanfall 2, Northstar, Steam, EA App, Maxima presence")
                    bullet("App version and CrossOver installation status")
                    bullet("Last 60 console lines per session (home path replaced with ~)")
                    bullet("Voluntary bug report info: description, name, contact (all optional)")
                    bullet("A one-time event confirming you accepted this notice")
                }
            }

            card(title: "How it's used", icon: "magnifyingglass") {
                bodyText(
                    "Error reports are used solely to identify and fix bugs. No data is sold or shared " +
                    "beyond the processors below. Draconis runs entirely on your device — no game data, " +
                    "save files, or account credentials pass through Draconis's servers."
                )
            }

            card(title: "Third-party services", icon: "network") {
                VStack(alignment: .leading, spacing: 10) {
                    processorRow("Sentry",
                        detail: "Receives crash reports and bug feedback from within the app.",
                        url: "https://sentry.io/privacy/")
                    Divider().overlay(.primary.opacity(0.08))
                    processorRow("GitHub",
                        detail: "Hosts source code, releases, and the public issue tracker.",
                        url: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement")
                    Divider().overlay(.primary.opacity(0.08))
                    processorRow("Electronic Arts / Maxima",
                        detail: "Handles EA authentication and game downloads if you use the Maxima integration.",
                        url: "https://www.ea.com/legal/privacy-policy")
                    Divider().overlay(.primary.opacity(0.08))
                    processorRow("Northstar master server",
                        detail: "Your IP is visible to the master server and game servers when playing online.",
                        url: "https://northstar.tf")
                }
            }

            card(title: "Your rights & data storage", icon: "person.badge.shield.checkmark") {
                VStack(alignment: .leading, spacing: 8) {
                    bodyText(
                        "Acceptance is stored in ~/Library/Preferences/org.draconis.launcher.plist. " +
                        "All crash data is processed by Sentry on EU servers. " +
                        "To withdraw consent run: defaults delete org.draconis.launcher"
                    )
                    Text("(GDPR / CCPA: request access, correction, or deletion from the respective service.)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - License

    private var licenseBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            card(title: "GNU General Public License v3.0", icon: "doc.text") {
                VStack(alignment: .leading, spacing: 10) {
                    bodyText(
                        "Draconis is free software distributed under GPL-3.0-or-later. " +
                        "You are free to use, study, share, and modify this software."
                    )
                    if let url = URL(string: "https://github.com/AA-EION/Draconis/blob/main/LICENSE") {
                        Link("Full license text on GitHub →", destination: url)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            card(title: "Your rights under GPL-3.0", icon: "checkmark.seal") {
                VStack(alignment: .leading, spacing: 5) {
                    bullet("Run the program for any purpose")
                    bullet("Study how the program works and modify it")
                    bullet("Redistribute copies")
                    bullet("Distribute your modified versions to others")
                    if let url = URL(string: "https://github.com/AA-EION/Draconis") {
                        Link("Source code: github.com/AA-EION/Draconis →", destination: url)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }

            card(title: "§15 — Disclaimer of Warranty", icon: "exclamationmark.triangle") {
                legalText(
                    "THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW. " +
                    "EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES " +
                    "PROVIDE THE PROGRAM \"AS IS\" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, " +
                    "INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR " +
                    "A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM " +
                    "IS WITH YOU. SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY " +
                    "SERVICING, REPAIR OR CORRECTION."
                )
            }

            card(title: "§16 — Limitation of Liability", icon: "exclamationmark.triangle") {
                legalText(
                    "IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING WILL ANY " +
                    "COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS THE PROGRAM AS " +
                    "PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, " +
                    "INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE " +
                    "PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE " +
                    "OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE " +
                    "WITH ANY OTHER PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE " +
                    "POSSIBILITY OF SUCH DAMAGES."
                )
            }
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassEffectContainer {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.55))
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(TF.title(13))
                        .foregroundStyle(.primary.opacity(0.80))
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·")
                .foregroundStyle(.secondary)
                .font(.callout.weight(.bold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func legalText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func processorRow(_ name: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.callout.weight(.semibold))
                if let dest = URL(string: url) {
                    Link("Privacy Policy →", destination: dest)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
