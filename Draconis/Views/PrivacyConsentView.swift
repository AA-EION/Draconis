import SwiftUI
import AppKit

/// Full-window overlay shown on first launch (and every launch until accepted).
/// Blocks all underlying UI; "Decline & Quit" terminates the app immediately.
/// The user must visit both the Privacy Notice and License tabs before accepting.
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
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabPicker
                Divider().overlay(.white.opacity(0.12))
                ScrollView {
                    Group {
                        switch activeTab {
                        case .privacy:  privacyBody
                        case .license:  licenseBody
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .frame(maxWidth: 640)
                Divider().overlay(.white.opacity(0.12))
                actionRow
            }
            .frame(maxWidth: 640)
            .padding(.vertical, 32)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 8)

            Text("Before you continue")
                .font(TF.hero(24))
                .foregroundStyle(.white)

            Text("Please read the Privacy Notice and License before using Draconis.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
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
                            .font(.callout.weight(activeTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(activeTab == tab ? .white : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        activeTab == tab
                            ? Color.white.opacity(0.12)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.06))
    }

    // MARK: - Action row

    private var actionRow: some View {
        VStack(spacing: 10) {
            if !allTabsVisited {
                Text("Read both tabs to continue.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            HStack(spacing: 16) {
                Button("Decline & Quit") {
                    ConsentManager.revoke()
                    NSApp.terminate(nil)
                }
                .buttonStyle(ConsentDeclineButtonStyle())

                Button("I accept — Continue") {
                    ConsentManager.accept()
                    env.privacyConsentAccepted = true
                }
                .buttonStyle(ConsentAcceptButtonStyle(enabled: allTabsVisited))
                .disabled(!allTabsVisited)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: - Privacy Notice body

    private var privacyBody: some View {
        VStack(alignment: .leading, spacing: 20) {

            section(title: "What Draconis collects") {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Crash reports and handled errors (via Sentry)")
                    bullet("Your bottle state: whether Titanfall 2, Northstar, Steam, EA App, or Maxima are present")
                    bullet("Launcher version and CrossOver installation status")
                    bullet("Console output from launch sessions (last 60 lines, home-directory path replaced with ~)")
                    bullet("Voluntary information you enter in a bug report: description, display name, and contact handle (all optional)")
                    bullet("A one-time event confirming you accepted this notice")
                }
            }

            section(title: "How it's used") {
                bodyText(
                    "Crash data and error reports are used solely to identify and fix bugs. " +
                    "No data is sold or shared beyond the processors listed below. " +
                    "Draconis runs entirely on your device; no game data, save files, or " +
                    "account credentials pass through Draconis's servers."
                )
            }

            section(title: "Third-party services") {
                VStack(alignment: .leading, spacing: 12) {
                    processorRow(
                        name: "Sentry",
                        detail: "Receives error reports and bug feedback submitted from within the app.",
                        url: "https://sentry.io/privacy/"
                    )
                    processorRow(
                        name: "GitHub",
                        detail: "Hosts the Draconis source code, releases, and public issue tracker. " +
                                "If you file a GitHub issue you are subject to GitHub's terms.",
                        url: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement"
                    )
                    processorRow(
                        name: "Electronic Arts / Maxima",
                        detail: "If you use the Maxima integration, authentication and game-download data " +
                                "are handled by EA's infrastructure. Draconis does not process EA credentials.",
                        url: "https://www.ea.com/legal/privacy-policy"
                    )
                    processorRow(
                        name: "Northstar master server",
                        detail: "When you connect to community servers, your IP address is visible to the " +
                                "Northstar master server and individual game servers.",
                        url: "https://northstar.tf"
                    )
                }
            }

            section(title: "Your rights (GDPR / CCPA)") {
                bodyText(
                    "You may request access to, correction of, or deletion of your data by contacting " +
                    "the respective service. To withdraw consent and stop future data collection, " +
                    "delete your Draconis preferences: open Terminal and run " +
                    "\"defaults delete org.draconis.launcher\". " +
                    "This resets consent and Draconis will present this notice again on next launch."
                )
            }

            section(title: "Data storage") {
                bodyText(
                    "Your acceptance is stored in ~/Library/Preferences/org.draconis.launcher.plist. " +
                    "All crash and error data is processed by Sentry on servers in the EU. " +
                    "Draconis does not maintain its own remote database."
                )
            }
        }
    }

    // MARK: - License body

    private var licenseBody: some View {
        VStack(alignment: .leading, spacing: 20) {

            section(title: "GNU General Public License v3.0") {
                bodyText(
                    "Draconis is free software distributed under the GNU General Public " +
                    "License, version 3 (GPL-3.0-or-later). You are free to use, study, " +
                    "share, and modify this software under the terms of that license."
                )
                if let url = URL(string: "https://github.com/AA-EION/Draconis/blob/main/LICENSE") {
                    Link("Full license text on GitHub →", destination: url)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            section(title: "Your rights under GPL-3.0") {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Run the program for any purpose")
                    bullet("Study how the program works and modify it (source code available on GitHub)")
                    bullet("Redistribute copies")
                    bullet("Distribute your modified versions to others")
                }
            }

            section(title: "15. Disclaimer of Warranty") {
                legalBox(
                    "THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY " +
                    "APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT " +
                    "HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY " +
                    "OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, " +
                    "THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR " +
                    "PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM " +
                    "IS WITH YOU. SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF " +
                    "ALL NECESSARY SERVICING, REPAIR OR CORRECTION."
                )
            }

            section(title: "16. Limitation of Liability") {
                legalBox(
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

            section(title: "Source code") {
                bodyText("The complete source code for this version of Draconis is available at:")
                if let url = URL(string: "https://github.com/AA-EION/Draconis") {
                    Link("github.com/AA-EION/Draconis →", destination: url)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    // MARK: - Sub-view helpers

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(TF.title(14))
                .foregroundStyle(.white)
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.white.opacity(0.5)).font(.callout)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.75))
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func legalBox(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10)))
    }

    private func processorRow(name: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                if let dest = URL(string: url) {
                    Link("Privacy Policy →", destination: dest)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Button styles

private struct ConsentAcceptButtonStyle: ButtonStyle {
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TF.title(14))
            .foregroundStyle(enabled ? .black : .white.opacity(0.3))
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(
                enabled
                    ? Color.white.opacity(configuration.isPressed ? 0.8 : 1.0)
                    : Color.white.opacity(0.15)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ConsentDeclineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
