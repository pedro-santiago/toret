import CoreText
import SwiftUI
import UIKit

/// Two voices, and they never trade jobs:
///
/// - **League Spartan**, set at the Black end of its weight axis, is the poster:
///   the screen titles, the figures, the numbers that answer the question. It is
///   a geometric grotesk with round Os and a tight fit, which is what lets a
///   title like "PER / TO" fill the width of a phone the way "TU / RIN" fills the
///   poster.
/// - **Archivo** is everything you read: rows, captions, buttons, body copy. A
///   neo-grotesque with plain letterforms, so it stays out of the way at 13 pt.
///   Its `wdth` axis bottoms out at 62, which gives a narrow cut for small
///   labels without a second font file.
@MainActor
enum Typo {
    // MARK: Interface

    static func ui(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
        Font(uiInterface(size, weight))
    }

    static func uiInterface(_ size: CGFloat, _ weight: CGFloat = 400) -> UIFont {
        VariableFont.font(
            family: VariableFont.Family.archivo,
            size: size,
            axes: [VariableFont.Axis.weight: weight, VariableFont.Axis.width: 100]
        )
    }

    // MARK: Narrow

    static func narrow(_ size: CGFloat, _ weight: CGFloat = 600) -> Font {
        Font(uiNarrow(size, weight))
    }

    static func uiNarrow(_ size: CGFloat, _ weight: CGFloat = 600) -> UIFont {
        VariableFont.font(
            family: VariableFont.Family.archivo,
            size: size,
            axes: [VariableFont.Axis.weight: weight, VariableFont.Axis.width: 62]
        )
    }

    // MARK: Display

    /// Poster type. Never lighter than Bold: a thin League Spartan is a different
    /// typeface, and the poster has only the one.
    static func display(_ size: CGFloat, _ weight: CGFloat = 800) -> Font {
        Font(uiDisplay(size, weight))
    }

    static func uiDisplay(_ size: CGFloat, _ weight: CGFloat = 800, italic: Bool = false) -> UIFont {
        VariableFont.font(
            family: VariableFont.Family.spartan,
            size: size,
            axes: [VariableFont.Axis.weight: min(900, max(700, weight))]
        )
    }

    /// The second line under a title. Not italic any more: the poster's "ALPINE
    /// ELEGANCE" is upright and plain.
    static func displayItalic(_ size: CGFloat, _ weight: CGFloat = 500) -> Font {
        ui(size, weight)
    }

    // MARK: Letterspacing

    /// CSS writes tracking in `em`; SwiftUI wants points.
    static func tracking(_ em: CGFloat, at size: CGFloat) -> CGFloat { em * size }

    // MARK: Registration

    /// `UIAppFonts` already registers these at launch. This is the safety net for
    /// SwiftUI previews and for the widget extension, and it is idempotent —
    /// a second registration of the same URL is simply reported as such.
    static func registerBundledFonts() {
        for name in ["Archivo", "LeagueSpartan"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Leading

extension View {
    /// Sets a CSS-style `line-height` multiple on wrapping copy.
    ///
    /// Only widens: SwiftUI clamps `lineSpacing` at zero, so anything tighter than
    /// the font's natural leading has to go through ``DisplayText``.
    @MainActor
    func lineHeight(_ multiple: CGFloat, font: UIFont) -> some View {
        lineSpacing(max(0, font.pointSize * multiple - font.lineHeight))
    }
}

/// Display type set on a tight leading — "Piazza / San Carlo" at 38/1.05.
///
/// `lineSpacing` cannot go negative, so each line becomes its own `Text` and the
/// stack takes the negative spacing instead.
struct DisplayText: View {
    let lines: [String]
    var size: CGFloat
    var weight: CGFloat = 500
    var leading: CGFloat = 1.0
    var tracking: CGFloat = 0
    var color: Color = Palette.ink
    var alignment: HorizontalAlignment = .leading

    init(
        _ text: String,
        size: CGFloat,
        weight: CGFloat = 500,
        leading: CGFloat = 1.0,
        tracking: CGFloat = 0,
        color: Color = Palette.ink,
        alignment: HorizontalAlignment = .leading
    ) {
        self.lines = text.components(separatedBy: "\n")
        self.size = size
        self.weight = weight
        self.leading = leading
        self.tracking = tracking
        self.color = color
        self.alignment = alignment
    }

    var body: some View {
        let font = Typo.uiDisplay(size, weight)
        VStack(alignment: alignment, spacing: size * leading - font.lineHeight) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Font(font))
                    .tracking(tracking)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lines.joined(separator: " "))
    }
}
