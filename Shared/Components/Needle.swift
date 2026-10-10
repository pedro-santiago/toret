import SwiftUI

/// An isosceles triangle standing on its base, apex up — the needle head.
struct NeedleHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The compass needle, at every size it appears in.
///
/// It is the one element on every screen: a pill on the map, the whole of the
/// compass screen, a row marker in the lists, a dial in the widgets. Same
/// geometry throughout — head, stem, pivot — scaled and re-tinted.
struct Needle: View {
    /// Degrees clockwise from north. Pass the model's *accumulated* angle, not a
    /// value reduced to 0..<360, or the needle will take the long way round.
    var angle: Double
    var diameter: CGFloat
    var headWidth: CGFloat
    var headHeight: CGFloat
    /// Gap between the top of the dial and the apex of the head.
    var headInset: CGFloat = 0
    var tint: Color = Palette.sage
    /// Length of the tail below the head, if this size carries one.
    var stemLength: CGFloat = 0
    var stemColor: Color = Palette.sage.opacity(0.5)
    /// Whether the tail fades out rather than ending flat.
    var stemFades: Bool = false
    /// The counterweight dot opposite the head, on the largest dial only.
    var pivotDiameter: CGFloat = 0
    var pivotInset: CGFloat = 0
    var pivotColor: Color = Palette.paper.opacity(0.3)

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            VStack(spacing: 0) {
                NeedleHead()
                    .fill(tint)
                    .frame(width: headWidth, height: headHeight)

                if stemLength > 0 {
                    Rectangle()
                        .fill(
                            stemFades
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [stemColor, stemColor.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                : AnyShapeStyle(stemColor)
                        )
                        .frame(width: max(1, headWidth / 9), height: stemLength)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, headInset)

            if pivotDiameter > 0 {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Circle()
                        .fill(pivotColor)
                        .frame(width: pivotDiameter, height: pivotDiameter)
                        .padding(.bottom, pivotInset)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(angle))
    }
}

// MARK: - The sizes the design actually uses

extension Needle {
    /// 28 pt — inside the compass pill on the map.
    static func pill(angle: Double) -> Needle {
        Needle(angle: angle, diameter: 28, headWidth: 8, headHeight: 9, headInset: 2)
    }

    /// 20–22 pt — the direction marker at the head of a list row.
    static func row(angle: Double, tint: Color, stem: Color, diameter: CGFloat = 22) -> Needle {
        Needle(
            angle: angle, diameter: diameter, headWidth: 8, headHeight: 9,
            tint: tint, stemLength: diameter - 11, stemColor: stem
        )
    }

    /// 260 pt — the compass screen itself.
    static func dial(angle: Double) -> Needle {
        Needle(
            angle: angle, diameter: 260, headWidth: 18, headHeight: 20, headInset: 6,
            tint: Palette.sage, stemLength: 40, stemColor: Palette.sage, stemFades: true,
            pivotDiameter: 5, pivotInset: 16
        )
    }
}

/// The ring a needle sits in — a thin circle, sometimes with a wash inside it.
struct NeedleRing: View {
    var diameter: CGFloat
    var stroke: Color
    var lineWidth: CGFloat = 1
    var wash: Bool = false

    var body: some View {
        Circle()
            .strokeBorder(stroke, lineWidth: lineWidth)
            .background {
                if wash {
                    Circle().fill(
                        RadialGradient(
                            colors: [Palette.sage.opacity(0.16), Palette.sage.opacity(0)],
                            center: .center, startRadius: 0, endRadius: diameter * 0.36
                        )
                    )
                }
            }
            .frame(width: diameter, height: diameter)
    }
}
