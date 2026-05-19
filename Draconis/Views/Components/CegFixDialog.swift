import SwiftUI

/// Steam-CEG fix dialog. Presented as a sheet from any view that has
/// access to `AppEnvironment` and a detected `WineBottle` whose
/// `titanfall2InstallPath` lives under Steam's library
/// (`steamapps\common\Titanfall2`).
///
/// The two options match what's documented in Maxima-Draconis CLAUDE.md
/// under "Engine Error: File corruption detected — Update 2026-05-19
/// (CEG fix confirmed end-to-end)":
///
///   A. Apply Maxima fix — replace the two CEG-signed launcher binaries
///      (`Titanfall2.exe` + `Titanfall2_trial.exe`) with the EA
///      originals via `maxima-cli install --replace-files
///      --only-listed-files`. ~3 MB download, <60 s. Save games and
///      Northstar files preserved.
///
///   B. Leave in place — keep the Steam binaries as-is. May work on
///      certain CrossOver builds; if it doesn't the user can re-open
///      this dialog later and apply A.
public struct CegFixDialog: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    public let bottle: WineBottle
    public let gamePath: String

    @State private var selection: Choice = .applyFix

    private enum Choice: Hashable {
        case applyFix
        case leaveInPlace
    }

    public init(bottle: WineBottle, gamePath: String) {
        self.bottle = bottle
        self.gamePath = gamePath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            optionsSection
            if let err = env.cegFixError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            footer
        }
        .padding(20)
        .frame(width: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Steam CEG heads-up")
                    .font(.title3.bold())
            }
            Text("The Titanfall 2 binary Steam installed is signed with Steam's per-user CEG DRM. Under some CrossOver builds this trips the in-game \"File corruption detected\" error because the validation path goes through Wine's `ntdll-Junction_Points` patch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Install path: \(gamePath)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            optionRow(
                value: .applyFix,
                title: "Apply Maxima fix",
                badge: "Recommended",
                detail: "Replace Titanfall2.exe and Titanfall2_trial.exe with the EA originals. ~3 MB download, under a minute. Save games, Northstar files, and the rest of the install are preserved."
            )
            optionRow(
                value: .leaveInPlace,
                title: "Leave in place, try anyway",
                badge: nil,
                detail: "Keep the Steam binaries as-is. May work on your CrossOver build. If you hit \"File corruption\" later, re-open this dialog and apply the fix."
            )
        }
    }

    @ViewBuilder
    private func optionRow(value: Choice, title: String, badge: String?, detail: String) -> some View {
        Button {
            selection = value
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selection == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selection == value ? Color.accentColor : .secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title).font(.body.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(env.cegFixRunning)
            Spacer()
            Button(action: applySelection) {
                if env.cegFixRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Applying…")
                    }
                } else {
                    Text(selection == .applyFix ? "Apply fix" : "Skip")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(env.cegFixRunning)
        }
    }

    private func applySelection() {
        switch selection {
        case .applyFix:
            env.applyCegFix(in: bottle, gamePath: gamePath)
        case .leaveInPlace:
            dismiss()
        }
    }
}
