import SwiftUI

/// Small Liquid Glass capsule used in PlayView to summarise bottle state.
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
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(
            .regular.tint(tone.color.opacity(0.35)),
            in: .rect(cornerRadius: 16)
        )
    }
}
