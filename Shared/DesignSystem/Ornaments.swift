import SwiftUI

// The small devices that divide a page. The poster has few of them and they are
// all ink: a heavy rule, a run of arches, a diamond, the three colour bars a
// printer puts in the margin. None of them is decoration for its own sake — each
// marks where one thing ends and the next begins.

/// A round-headed arch standing on its base.
private struct ArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A heavy rule with a run of solid arches hanging from it — Turin's porticoes
/// seen from the street. It closes a block the way the arcade closes a pavement.
///
/// `stroke` is the ink of the rule and the arches; `lineWidth` and `spacing` are
/// kept from the first version so existing call sites compile.
struct ArcadeCornice: View {
    var bays: Int = 14
    var height: CGFloat = 13
    var stroke: Color = Palette.inchiostro
    var lineWidth: CGFloat = 1
    var spacing: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(stroke).frame(height: 3)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0 ..< bays, id: \.self) { _ in
                    ArchShape()
                        .fill(stroke)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A cast-iron lozenge — the diamond stamped on the fountains' collars.
struct Lozenge: View {
    var size: CGFloat = 7
    var filled: Bool = true
    var color: Color = Palette.rosso
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

/// A heavy rule with a diamond at its head: the divider between a headline and
/// what it is about.
struct LozengeRule: View {
    var color: Color = Palette.rosso
    var rule: Color = Palette.inchiostro

    var body: some View {
        HStack(spacing: 10) {
            Diamond().fill(color).frame(width: 11, height: 11)
            Rectangle().fill(rule).frame(height: 3)
        }
        .accessibilityHidden(true)
    }
}

/// The three colour bars of a printer's proof, then a heavy rule: the yellow, the
/// red and the blue the whole poster is made from, set at the head of a list.
struct LozengeTicks: View {
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(Palette.sole).frame(width: 11, height: 11)
            Rectangle().fill(Palette.rosso).frame(width: 11, height: 11)
            Rectangle().fill(Palette.blu).frame(width: 11, height: 11)
            Rectangle().fill(Palette.inchiostro).frame(height: 3)
        }
        .accessibilityHidden(true)
    }
}

/// A short line that names what the block below it is, in plain sentence case.
///
/// It was a tracked-out capital label. The poster sets its capitals only in the
/// display words, so this is now Archivo Bold at reading size, in red. `size` and
/// `tracking` are kept so existing call sites compile; the size sets a floor,
/// not a scale.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 9.5
    var tracking: CGFloat = 0.14
    var color: Color = Palette.rosso

    var body: some View {
        Text(text)
            .font(Typo.ui(max(13, size + 3.5), 700))
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}
