import SwiftCrossUI

/// Draconis's palette and glass surfaces, matching the macOS app: dark,
/// translucent white panels with a light rim, silver accent, capsule pills.
enum Theme {
    static let accent = Color(red: 0.82, green: 0.847, blue: 0.871)
    static let background = Color(red: 0.06, green: 0.07, blue: 0.085)
    static let backgroundTop = Color(red: 0.13, green: 0.15, blue: 0.18)
    static let glassFill = Color(white: 1, opacity: 0.07)
    static let glassRim = Color(white: 1, opacity: 0.16)
    static let tintFill = Color(red: 0.82, green: 0.847, blue: 0.871, opacity: 0.10)
    static let errorFill = Color(red: 0.9, green: 0.25, blue: 0.25, opacity: 0.16)
    static let secondary = Color(white: 1, opacity: 0.72)
    static let faint = Color(white: 1, opacity: 0.5)
}

extension View {
    /// A Liquid Glass-style card. Native CSS (Linux) adds blur and highlights.
    func glassCard(tinted: Bool = false, radius: Double = 18) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius).fill(tinted ? Theme.tintFill : Theme.glassFill))
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(Theme.glassRim) }
            .nativeClass(tinted ? "draconis-glass draconis-tinted" : "draconis-glass")
    }

    func errorCard() -> some View {
        self
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.errorFill))
            .nativeClass("draconis-glass")
    }

    /// Uppercase HUD label, like the macOS `stencilLabel()`.
    func stencil() -> some View {
        self.font(.system(size: 11, weight: .heavy)).foregroundColor(Theme.secondary).nativeClass("draconis-stencil")
    }

    func hero(_ size: Double = 34) -> some View {
        self.font(.system(size: size, weight: .black)).nativeClass("draconis-hero")
    }
}

/// A row of buttons kept at their natural widths.
struct ButtonRow<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        HStack(spacing: 10) { content }.fixedSize(horizontal: true, vertical: false)
    }
}
