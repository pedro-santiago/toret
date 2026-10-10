import CoreText
import SwiftUI
import UIKit

/// Follows the user's text size so type scales for everyone.
///
/// `UIFontMetrics` does the arithmetic, but the fonts here are built in view
/// bodies from plain point sizes, and a body only re-runs when something it read
/// changes. Reading ``generation`` inside every `Typo` call makes each of them a
/// dependency (Observation tracks any access made while a body evaluates), and the
/// system's size-change notification bumps it — so changing Settings > Display &
/// Brightness > Text Size redraws the open screen instead of the next launch.
///
/// The widget extension is opted out: a widget's layout is fixed by its family,
/// and the system scales widget text itself where it should.
@MainActor
@Observable
final class TypeScale {
    static let shared = TypeScale()

    enum Role {
        /// Reading text and controls: scales fully.
        case text
        /// Small labels: scales, but less, so a caption never outgrows its row.
        case label
        /// Poster type: scales a little, never past about a third. A 120 pt figure
        /// that doubled would leave the disc it sits on.
        case display
    }

    private(set) var generation = 0
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        guard isEnabled else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.generation += 1 }
        }
    }

    var isEnabled: Bool { !Bundle.main.bundlePath.hasSuffix(".appex") }

    func scale(_ size: CGFloat, _ role: Role) -> CGFloat {
        _ = generation
        guard isEnabled else { return size }
        switch role {
        case .text:
            return UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
        case .label:
            return min(UIFontMetrics(forTextStyle: .footnote).scaledValue(for: size), size * 2.2)
        case .display:
            return min(UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: size), size * 1.35)
        }
    }
}

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
            size: TypeScale.shared.scale(size, size <= 13.5 ? .label : .text),
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
            size: TypeScale.shared.scale(size, .label),
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
            size: TypeScale.shared.scale(size, .display),
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
        VStack(alignment: alignment, spacing: font.pointSize * leading - font.lineHeight) {
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
