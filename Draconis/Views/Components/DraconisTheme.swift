import SwiftUI

/// Central palette for Draconis UI — opacity levels and glass card tints.
///
/// Use these constants instead of inline magic numbers so that a single edit
/// here propagates to every surface at once.
///
/// Usage:
///   `.foregroundStyle(.primary.opacity(DraconisTheme.Text.tertiary))`
///   `.glassEffect(.regular.tint(Color.accentColor.opacity(DraconisTheme.Card.accent)), ...)`
public enum DraconisTheme {

    public enum Text {
        /// Stencil / uppercase label — tracking 2.5, small caps.
        public static let stencil: Double   = 0.88
        /// Body copy, card titles, prominent secondary labels.
        public static let secondary: Double = 0.80
        /// Supporting / descriptive text, longer paragraphs.
        public static let tertiary: Double  = 0.75
        /// Hint text, footnotes, detected paths, small annotations.
        public static let faint: Double     = 0.65
    }

    public enum Card {
        /// Strongest accent tint — instruction / setup cards.
        public static let accentStrong: Double  = 0.18
        /// Medium accent tint — actions card, Maxima card.
        public static let accentMedium: Double  = 0.14
        /// Standard accent tint — most glass cards.
        public static let accent: Double        = 0.10
        /// Subtle accent tint — hero card.
        public static let accentSubtle: Double  = 0.06
        /// Active (snow-white) StatusPill tint.
        public static let pillActive: Double    = 0.92
        /// Inactive (dark glass) StatusPill tint.
        public static let pillInactive: Double  = 0.28
        /// Error / warning card red tint.
        public static let error: Double         = 0.15
        /// Dark tint for console surfaces.
        public static let dark: Double          = 0.22
    }
}
