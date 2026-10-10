import SwiftUI

/// A run of arcade arches, used as a section rule.
///
/// Turin is eighteen kilometres of porticoes; this is their cornice, reduced to
/// fourteen bays of open arch. It marks the top of a panel the way the arcade
/// marks the top of a street.
struct ArcadeCornice: View {
    var bays: Int = 14
    var height: CGFloat = 13
    var stroke: Color = Palette.ink.opacity(0.22)
    var lineWidth: CGFloat = 1
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0 ..< bays, id: \.self) { _ in
                UnevenRoundedRectangle(
                    topLeadingRadius: height * 0.54,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: height * 0.54,
                    style: .continuous
                )
                .strokeBorder(stroke, lineWidth: lineWidth)
                // The arch has no floor: the bay opens onto the content below it.
                .mask(alignment: .top) { Rectangle().frame(height: height - lineWidth) }
                .frame(maxWidth: .infinity)
                .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A cast-iron lozenge — the diamond stamped on the fountains' collars.
struct Lozenge: View {
    var size: CGFloat = 7
    var filled: Bool = true
    var color: Color = Palette.terracotta
    var lineWidth: CGFloat = 1

    var body: some View {
        Group {
            if filled {
                Rectangle().fill(color)
            } else {
                Rectangle().strokeBorder(color, lineWidth: lineWidth)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(45))
        .frame(width: size * 1.42, height: size * 1.42)
    }
}

/// Three lozenges strung on a hairline — the divider between a fountain's
/// headline and its specification.
struct LozengeRule: View {
    var color: Color = Palette.terracotta
    var rule: Color = Palette.ink.opacity(0.14)

    var body: some View {
        HStack(spacing: 7) {
            Lozenge(size: 6, color: color)
            Rectangle().fill(rule).frame(height: 1)
            Lozenge(size: 6, color: color)
            Rectangle().fill(rule).frame(height: 1)
            Lozenge(size: 6, color: color)
        }
        .accessibilityHidden(true)
    }
}

/// The four-lozenge tick that opens a list, alternating solid and outline.
struct LozengeTicks: View {
    var body: some View {
        HStack(spacing: 6) {
            Lozenge(size: 7, color: Palette.terracotta)
            Lozenge(size: 7, filled: false, color: Palette.ink.opacity(0.35))
            Lozenge(size: 7, color: Palette.green)
            Lozenge(size: 7, filled: false, color: Palette.ink.opacity(0.35))
            Rectangle().fill(Palette.ink.opacity(0.14)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A small caps eyebrow — narrow, letterspaced, terracotta by default.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 9.5
    var tracking: CGFloat = 0.14
    var color: Color = Palette.terracotta

    var body: some View {
        Text(text.uppercased())
            .font(Typo.narrow(size))
            .tracking(Typo.tracking(tracking, at: size))
            .foregroundStyle(color)
    }
}
