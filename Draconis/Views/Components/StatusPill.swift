import SwiftUI

/// Liquid Glass capsule used in PlayView to summarise bottle state.
///
/// Two visual states only:
///   • `active = true`  → snow-white pill, black text. Used for detected /
///                         installed / ready statuses.
///   • `active = false` → dark translucent glass, white text. Matches the
///                         `.buttonStyle(.glass)` look so a missing item
///                         feels "ready to be acted on" instead of alarming.
///
/// No semantic colour (no green / orange / red) — the contrast between
/// snow-white and dark glass alone communicates active vs missing.
struct StatusPill: View {
    let label: String
    let value: String
    let symbol: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol)
                .stencilLabel(
                    size: 10,
                    color: active
                        ? Color.black.opacity(0.72)
                        : Color.white.opacity(0.78)
                )
            Text(value)
                .font(TF.display(18))
                .foregroundStyle(active ? Color.black : Color.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(
            .regular.tint(
                active
                    ? Color.white.opacity(DraconisTheme.Card.pillActive)
                    : Color.black.opacity(DraconisTheme.Card.pillInactive)
            ),
            in: .rect(cornerRadius: 16)
        )
    }
}
