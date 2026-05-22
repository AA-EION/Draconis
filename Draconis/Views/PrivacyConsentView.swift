import SwiftUI
import AppKit

/// Shown inside the main window before any other content when the user
/// hasn't accepted the privacy notice yet. Styled to match the rest of
/// the app (GlassEffect cards, TF typography, dark mode).
struct PrivacyConsentView: View {
    @EnvironmentObject private var env: AppEnvironment

    enum Tab: String, CaseIterable {
        case privacy = "Privacy Notice"
        case license = "License (GPL-3.0)"
    }

    @State private var activeTab: Tab = .privacy
    @State private var visitedTabs: Set<Tab> = [.privacy]

    private var allTabsVisited: Bool { visitedTabs.count == Tab.allCases.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
                .padding(.horizontal, 24)
                .padding(.top, 4)
            ScrollView {
                Group {
                    switch activeTab {
                    case .privacy: privacyBody
                    case .license: licenseBody
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            actionRow
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.top, 32)

            Text("Before you continue")
                .font(TF.hero(22))

            Text("Please read the Privacy Notice and License.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        activeTab = tab
                        visitedTabs.insert(tab)
                    } label: {
                        HStack(spacing: 6) {
                            if visitedTabs.contains(tab) && tab != activeTab {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green.opacity(0.8))
                            }
                            Text(tab.rawValue)
                                .font(TF.title(13).weight(activeTab == tab ? .semibold : .regular))
                                .foregroundStyle(activeTab == tab ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(activeTab == tab ? Color.primary.opacity(0.10) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    // MARK: - Action row

    private var actionRow: some View {
        VStack(spacing: 10) {
            if !allTabsVisited {
                Text("Read both tabs to enable the accept button.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Button("Decline & Quit") {
                    ConsentManager.revoke()
                    NSApp.terminate(nil)
                }
                .buttonStyle(.glass)

                Spacer()

                Button("I accept — Continue") {
                    ConsentManager.accept()
                    env.privacyConsentAccepted = true
                }
                .buttonStyle(.glass)
                .disabled(!allTabsVisited)
                .opacity(allTabsVisited ? 1 : 0.4)
            }
        }
    }

    // MARK: - Privacy Notice

    private var privacyBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            card(title: "What Draconis collects") {
                VStack(alignment: .leading, spacing: 5) {
                    bullet("Crash reports and handled errors (via Sentry)")
                    bullet("Bottle state: whether Titanfall 2, Northstar, Steam, EA App, or Maxima are present")
                    bullet("Launcher version and CrossOver installation status")
                    bullet("Console output from the last session (last 60 lines, home path replaced with ~)")
                    bullet("Voluntary info you enter in a bug report: description, name, contact (all optional)")
                    bullet("A one-time event confirming you accepted this notice")
                }
            }

            card(title: "How it's used") {
                bodyText(
                    "Crash data and error reports are used solely to identify and fix bugs. " +
                    "No data is sold or shared beyond the processors listed below. " +
                    "Draconis runs entirely on your device — no game data, save files, or " +
                    "account credentials pass through Draconis's servers."
                )
            }

            card(title: "Third-party services") {
                VStack(alignment: .leading, spacing: 12) {
                    processorRow(
                        name: "Sentry",
                        detail: "Receives error reports and bug feedback submitted from within the app.",
                        url: "https://sentry.io/privacy/"
                    )
                    Divider().overlay(.primary.opacity(0.08))
                    processorRow(
                        name: "GitHub",
                        detail: "Hosts the source code, releases, and public issue tracker. Filing a GitHub issue is subject to GitHub's terms.",
                        url: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement"
                    )
                    Divider().overlay(.primary.opacity(0.08))
                    processorRow(
                        name: "Electronic Arts / Maxima",
                        detail: "If you use the Maxima integration, authentication and downloads go through EA's infrastructure. Draconis does not handle EA credentials.",
                        url: "https://www.ea.com/legal/privacy-policy"
                    )
                    Divider().overlay(.primary.opacity(0.08))
                    processorRow(
                        name: "Northstar master server",
                        detail: "When connecting to community servers your IP is visible to the Northstar master server and individual game servers.",
                        url: "https://northstar.tf"
                    )
                }
            }

            card(title: "Your rights (GDPR / CCPA)") {
                bodyText(
                    "To withdraw consent and stop data collection, delete your Draconis preferences: " +
                    "run \"defaults delete org.draconis.launcher\" in Terminal. " +
                    "This resets consent and Draconis will show this screen again on next launch. " +
                    "Your acceptance is stored in ~/Library/Preferences/org.draconis.launcher.plist. " +
                    "All error data is processed by Sentry on EU servers."
                )
            }
        }
    }

    // MARK: - License (GPL-3.0)

    private var licenseBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            card(title: "GNU General Public License v3.0") {
                VStack(alignment: .leading, spacing: 10) {
                    bodyText(
                        "Draconis is free software distributed under the GNU General Public License, " +
                        "version 3 (GPL-3.0-or-later). You are free to use, study, share, and modify " +
                        "this software under the terms of that license."
                    )
                    if let url = URL(string: "https://github.com/AA-EION/Draconis/blob/main/LICENSE") {
                        Link("Full license text on GitHub →", destination: url)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            card(title: "Your rights under GPL-3.0") {
                VStack(alignment: .leading, spacing: 5) {
                    bullet("Run the program for any purpose")
                    bullet("Study how the program works and modify it (source code on GitHub)")
                    bullet("Redistribute copies")
                    bullet("Distribute your modified versions to others")
                }
            }

            card(title: "§15 — Disclaimer of Warranty") {
                legalText(
                    "THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY " +
                    "APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT " +
                    "HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM \"AS IS\" WITHOUT WARRANTY " +
                    "OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, " +
                    "THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR " +
                    "PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM " +
                    "IS WITH YOU. SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF " +
                    "ALL NECESSARY SERVICING, REPAIR OR CORRECTION."
                )
            }

            card(title: "§16 — Limitation of Liability") {
                legalText(
                    "IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING " +
                    "WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS " +
                    "THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY " +
                    "GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE " +
                    "USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF " +
                    "DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD " +
                    "PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS), " +
                    "EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF " +
                    "SUCH DAMAGES."
                )
            }

            card(title: "Source code") {
                VStack(alignment: .leading, spacing: 6) {
                    bodyText("The complete source code for this version of Draconis is available at:")
                    if let url = URL(string: "https://github.com/AA-EION/Draconis") {
                        Link("github.com/AA-EION/Draconis →", destination: url)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sub-view helpers

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(TF.title(13))
                    .foregroundStyle(.primary.opacity(0.75))
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary).font(.callout)
            Text(text).font(.callout).foregroundStyle(.primary.opacity(0.8))
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

    private func processorRow(name: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
    }
}
