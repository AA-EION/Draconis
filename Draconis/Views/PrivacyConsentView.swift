import SwiftUI
import AppKit

/// Full-window overlay shown on first launch (and every launch until accepted).
/// Blocks all underlying UI; "Decline & Quit" terminates the app immediately.
struct PrivacyConsentView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ZStack {
            // Solid backdrop so the underlying UI is fully obscured
            Color.black.opacity(0.85).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(.white.opacity(0.12))
                    noticeBody
                    Divider().overlay(.white.opacity(0.12))
                    actionRow
                }
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

            Text("Privacy & Data Notice")
                .font(TF.hero(24))
                .foregroundStyle(.white)

            Text("Please read before using Draconis.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    // MARK: - Notice body

    private var noticeBody: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── What Draconis collects ─────────────────────────────────────
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

            // ── How it's used ──────────────────────────────────────────────
            section(title: "How it's used") {
                bodyText(
                    "Crash data and error reports are used solely to identify and fix bugs. " +
                    "No data is sold or shared beyond the processors listed below. " +
                    "Draconis itself runs entirely on your device; no game data, " +
                    "save files, or account credentials pass through Draconis's servers."
                )
            }

            // ── Third-party processors ─────────────────────────────────────
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
                                "Northstar master server and individual game servers. " +
                                "This is managed by the Northstar project, not Draconis.",
                        url: "https://northstar.tf"
                    )
                }
            }

            // ── Your rights ────────────────────────────────────────────────
            section(title: "Your rights (GDPR / CCPA)") {
                bodyText(
                    "You may request access to, correction of, or deletion of your data by contacting " +
                    "the respective service. To withdraw consent and stop future data collection from Draconis, " +
                    "delete your Draconis preferences: open Terminal and run " +
                    "\"defaults delete org.draconis.launcher\". " +
                    "This resets consent and Draconis will present this notice again on next launch."
                )
            }

            // ── Data storage ───────────────────────────────────────────────
            section(title: "Data storage") {
                bodyText(
                    "Your acceptance of this notice is stored in " +
                    "~/Library/Preferences/org.draconis.launcher.plist on your Mac. " +
                    "All crash and error data is processed by Sentry on servers in the EU. " +
                    "Draconis does not maintain its own remote database."
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button("Decline & Quit") {
                ConsentManager.revoke()
                NSApp.terminate(nil)
            }
            .buttonStyle(ConsentDeclineButtonStyle())

            Button("Accept & Continue") {
                ConsentManager.accept()
                env.privacyConsentAccepted = true
            }
            .buttonStyle(ConsentAcceptButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TF.title(14))
            .foregroundStyle(.black)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1.0))
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
