import SwiftUI

/// Modal shown on launch when GitHub has a Draconis release newer than the
/// running version. User picks one of three:
///   • Update Now            → download DMG, swap on quit
///   • Remind Me Later       → dismiss for this session only
///   • Skip This Version     → persist skip; only re-prompt for a newer tag
struct DraconisUpdateSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    let release: DraconisUpdater.Release

    private var currentVersion: String { DraconisUpdater.shared.currentVersion }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if env.draconisUpdating {
                progressSection
            } else {
                releaseNotes
            }

            if let err = env.draconisUpdateError {
                Text(err)
                    .font(TF.body(12))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            buttonRow
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accentSubtle)),
            in: .rect(cornerRadius: 22)
        )
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Draconis update available")
                .font(TF.title(20))
            Text("\(currentVersion)  →  \(release.tagName)")
                .font(TF.body(13))
                .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
        }
    }

    private var releaseNotes: some View {
        ScrollView {
            Text(release.body.isEmpty ? "No release notes provided." : release.body)
                .font(TF.body(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: .rect(cornerRadius: 12))
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(env.draconisUpdateProgress?.detail ?? "Working…")
                .font(TF.body(12))
                .foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))
            if let frac = env.draconisUpdateProgress?.fraction, frac >= 0 {
                ProgressView(value: frac)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: .rect(cornerRadius: 12))
    }

    private var buttonRow: some View {
        HStack(spacing: 10) {
            Button("Skip This Version") {
                env.skipDraconisUpdateForever()
            }
            .buttonStyle(.glass)
            .disabled(env.draconisUpdating)

            Spacer()

            Button("Remind Me Later") {
                env.skipDraconisUpdateOnce()
            }
            .buttonStyle(.glass)
            .disabled(env.draconisUpdating)

            Button(env.draconisUpdating ? "Updating…" : "Update Now") {
                Task { await env.installDraconisUpdate() }
            }
            .buttonStyle(.glassProminent)
            .disabled(env.draconisUpdating)
        }
    }
}
