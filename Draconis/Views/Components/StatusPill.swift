import SwiftUI

/// Small Liquid Glass capsule used in PlayView to summarise bottle state.
/// Uses very light tints so the window stays see-through.
struct StatusPill: View {
    let label: String
    let value: String
    let symbol: String
    let tone: Tone

    enum Tone {
        case green, orange, red, accent, neutral
        var color: Color {
            switch self {
            case .green:    return .green
            case .orange:   return .orange
            case .red:      return .red
            case .accent:   return .accentColor
            case .neutral:  return .gray
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol)
                .stencilLabel(size: 10, color: tone.color.opacity(0.9))
            Text(value)
                .font(TF.display(18))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(
            .regular.tint(tone.color.opacity(0.08)),
            in: .rect(cornerRadius: 16)
        )
    }
}
