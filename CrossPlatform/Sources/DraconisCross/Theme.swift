import Foundation
import SwiftCrossUI

/// Draconis's palette and Liquid Glass-style surfaces, matching the macOS
/// app: dark, translucent rimmed panels, silver accent, snow-white
/// "active" pills, capsule controls.
enum Theme {
    static let accent = Color(red: 0.82, green: 0.847, blue: 0.871)
    static let background = Color(red: 0.05, green: 0.06, blue: 0.075)
    static let backgroundTop = Color(red: 0.15, green: 0.17, blue: 0.2)
    static let glassFill = Color(white: 1, opacity: 0.07)
    static let glassRim = Color(white: 1, opacity: 0.16)
    static let tintFill = Color(red: 0.82, green: 0.847, blue: 0.871, opacity: 0.12)
    static let snow = Color(white: 0.96, opacity: 0.95)
    static let darkGlass = Color(white: 0, opacity: 0.28)
    static let errorFill = Color(red: 0.9, green: 0.25, blue: 0.25, opacity: 0.18)
    static let primary = Color(white: 0.96)
    static let secondary = Color(white: 1, opacity: 0.78)
    static let tertiary = Color(white: 1, opacity: 0.68)
    static let faint = Color(white: 1, opacity: 0.5)
}

/// Font roles, after the macOS `TF` palette: Orbitron for hero/display,
/// a condensed bold for titles and stencil labels, Inter for body text.
enum TF {
    static func hero(_ size: Double) -> Font { .system(size: size, weight: .black) }
    static func display(_ size: Double) -> Font { .system(size: size, weight: .bold) }
    static func title(_ size: Double) -> Font { .system(size: size, weight: .bold) }
    static func body(_ size: Double) -> Font { .system(size: size) }
}

/// Wide tracking that SwiftCrossUI can measure: hair spaces between letters.
func tracked(_ text: String, _ spaces: Int = 1) -> String {
    text.map(String.init).joined(separator: String(repeating: "\u{200A}", count: spaces))
}

extension View {
    /// A Liquid Glass-style card. Native CSS (Linux) adds highlights and blur.
    func glassCard(tinted: Bool = false, radius: Double = 22, padding: Int = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius).fill(tinted ? Theme.tintFill : Theme.glassFill))
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(Theme.glassRim) }
            .nativeClass("draconis-glass")
    }

    func errorCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.errorFill))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color(red: 1, green: 0.4, blue: 0.4, opacity: 0.4)) }
            .nativeClass("draconis-glass")
    }

    /// Uppercase HUD label (macOS `stencilLabel()`).
    func stencil(_ size: Double = 11, color: Color = Theme.secondary) -> some View {
        self.font(.system(size: size, weight: .bold)).foregroundColor(color).nativeClass("draconis-stencil")
    }

    func hero(_ size: Double = 34) -> some View {
        self.font(TF.hero(size)).nativeClass("draconis-hero")
    }

    func display(_ size: Double) -> some View {
        self.font(TF.display(size)).nativeClass("draconis-display")
    }

    func titleFont(_ size: Double = 16) -> some View {
        self.font(TF.title(size)).nativeClass("draconis-title")
    }
}

/// Uppercase tracked stencil text.
struct Stencil: View {
    var text: String
    var size: Double = 11
    var color: Color = Theme.secondary
    init(_ text: String, size: Double = 11, color: Color = Theme.secondary) {
        self.text = text; self.size = size; self.color = color
    }
    var body: some View { Text(tracked(text.uppercased())).stencil(size, color: color) }
}

/// A bundled Lucide icon (ISC), light for dark glass, dark for snow pills.
struct IconView: View {
    var name: String
    var dark = false
    var size: Double = 16

    var body: some View {
        if let url = NativeStyle.resources?.appendingPathComponent("icons/\(name)-\(dark ? "dark" : "light").png") {
            Image(url).resizable().frame(width: size, height: size)
        }
    }
}

/// `.glass` / `.glassProminent` buttons, drawn the same on every backend.
struct GlassButton: View {
    enum Kind { case glass, prominent }
    var title: String
    var icon: String? = nil
    var kind: Kind = .glass
    var fullWidth = false
    var size: Double = 14
    var disabled = false
    var action: @MainActor @Sendable () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon { IconView(name: icon, dark: kind == .prominent, size: size + 2) }
            Text(title)
                .titleFont(size)
                .foregroundColor(kind == .prominent ? Color(red: 0.06, green: 0.08, blue: 0.1) : Theme.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, fullWidth ? 12 : 9)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .background(Capsule().fill(fill))
        .overlay { Capsule().stroke(kind == .prominent ? Color(white: 1, opacity: 0.6) : Theme.glassRim) }
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .onTapGesture { if !disabled { action() } }
        .fixedSize(horizontal: !fullWidth, vertical: true)
    }

    var fill: Color {
        switch kind {
        case .prominent: return Color(white: hovering && !disabled ? 1 : 0.9)
        case .glass: return Color(white: 1, opacity: hovering && !disabled ? 0.16 : 0.09)
        }
    }
}

/// The macOS status capsule: snow-white when active, dark glass otherwise.
struct StatusPill: View {
    var label: String
    var value: String
    var icon: String
    var active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                IconView(name: icon, dark: active, size: 13)
                Stencil(label, size: 10, color: active ? Color(white: 0, opacity: 0.72) : Color(white: 1, opacity: 0.78))
            }
            Text(value).display(18).foregroundColor(active ? Color(white: 0.02) : Theme.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(active ? Theme.snow : Theme.darkGlass))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.glassRim) }
        .nativeClass("draconis-glass")
    }
}

/// A capsule segmented control (macOS `.pickerStyle(.segmented)`).
struct Segmented<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Text(option.1)
                    .titleFont(15)
                    .foregroundColor(selected ? Color(white: 0.04) : Theme.secondary)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(selected ? Theme.snow : Color(white: 1, opacity: 0)))
                    .onTapGesture { selection = option.0 }
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.darkGlass))
        .overlay { Capsule().stroke(Theme.glassRim) }
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
