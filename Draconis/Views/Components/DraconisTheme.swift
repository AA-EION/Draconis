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
        /// Strongest accent tint — instruction / warning cards.
        public static let accentStrong: Double  = 0.25
        /// Medium accent tint — Maxima card and progress cards.
        public static let accentMedium: Double  = 0.20
        /// Standard accent tint — most glass cards.
        public static let accent: Double        = 0.18
        /// Subtle accent tint — hero card.
        public static let accentSubtle: Double  = 0.10
        /// Status-pill semantic tint (coloured by tone).
        public static let status: Double        = 0.08
        /// Dark tint for error / console surfaces.
        public static let dark: Double          = 0.06
    }
}
