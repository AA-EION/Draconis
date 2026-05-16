import SwiftUI
import AppKit

/// Typography palette tuned to evoke the Titanfall HUD: condensed, heavy, with
/// generous tracking. Falls back gracefully through:
///   1. Orbitron (if a TTF was dropped into the bundle as `Orbitron-Black.ttf`)
///   2. Helvetica Neue Condensed Black (system on macOS Tahoe)
///   3. SF Pro Rounded Black (always available)
///
/// Use these instead of `.font(.title)` throughout the app for a coherent look.
public enum TF {

    /// Hero text — "DRACONIS", section banners.
    public static func hero(_ size: CGFloat = 44) -> Font {
        if NSFont(name: "Orbitron-Black", size: size) != nil {
            return .custom("Orbitron-Black", size: size)
        }
        if NSFont(name: "HelveticaNeue-CondensedBlack", size: size) != nil {
            return .custom("HelveticaNeue-CondensedBlack", size: size)
        }
        return .system(size: size, weight: .black, design: .rounded)
    }

    /// Display — large numbers / readouts.
    public static func display(_ size: CGFloat = 28) -> Font {
        if NSFont(name: "Orbitron-Bold", size: size) != nil {
            return .custom("Orbitron-Bold", size: size)
        }
        if NSFont(name: "HelveticaNeue-CondensedBold", size: size) != nil {
            return .custom("HelveticaNeue-CondensedBold", size: size)
        }
        return .system(size: size, weight: .bold, design: .rounded)
    }

    /// Card title.
    public static func title(_ size: CGFloat = 18) -> Font {
        if NSFont(name: "HelveticaNeue-CondensedBold", size: size) != nil {
            return .custom("HelveticaNeue-CondensedBold", size: size)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Body — running text, longer descriptions. Stays as SF for legibility.
    public static func body(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    /// Small monospace — used by the in-app console.
    public static func mono(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    /// Stencil / label — small uppercase status text.
    public static func stencil(_ size: CGFloat = 10) -> Font {
        if NSFont(name: "HelveticaNeue-CondensedBold", size: size) != nil {
            return .custom("HelveticaNeue-CondensedBold", size: size)
        }
        return .system(size: size, weight: .heavy, design: .rounded)
    }
}

/// View modifier: wide tracking + small caps look that reads as "Titanfall HUD".
public struct StencilLabel: ViewModifier {
    var size: CGFloat = 11
    var color: Color = .primary.opacity(0.88)

    public func body(content: Content) -> some View {
        content
            .font(TF.stencil(size))
            .tracking(2.5)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

public extension View {
    func stencilLabel(size: CGFloat = 11, color: Color = .primary.opacity(0.88)) -> some View {
        modifier(StencilLabel(size: size, color: color))
    }
}
