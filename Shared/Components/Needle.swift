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
/// geometry throughout — a flat triangle, an optional stem, an optional pivot —
/// scaled and re-inked. On the poster's moon it is a bold black wedge; on a dark
/// pill it is cream.
struct Needle: View {
    /// Degrees clockwise from north. Pass the model's *accumulated* angle, not a
    /// value reduced to 0..<360, or the needle will take the long way round.
    var angle: Double
    var diameter: CGFloat
    var headWidth: CGFloat
    var headHeight: CGFloat
    /// Gap between the top of the dial and the apex of the head.
    var headInset: CGFloat = 0
    var tint: Color = Palette.inchiostro
    /// Length of the tail below the head, if this size carries one.
    var stemLength: CGFloat = 0
    var stemColor: Color = Palette.inchiostro.opacity(0.5)
    /// Whether the tail fades out rather than ending flat.
    var stemFades: Bool = false
    /// The counterweight dot opposite the head, on the largest dial only.
    var pivotDiameter: CGFloat = 0
    var pivotInset: CGFloat = 0
    var pivotColor: Color = Palette.inchiostro.opacity(0.3)

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

// MARK: - The sizes the app actually uses

extension Needle {
    /// 28 pt — inside the compass pill on the map. The pill is a black plate, so
    /// the needle is cream.
    static func pill(angle: Double) -> Needle {
        Needle(
            angle: angle, diameter: 28, headWidth: 9, headHeight: 11, headInset: 2,
            tint: Palette.carta
        )
    }

    /// 20–22 pt — the direction marker at the head of a list row.
    static func row(angle: Double, tint: Color, stem: Color, diameter: CGFloat = 22) -> Needle {
        Needle(
            angle: angle, diameter: diameter, headWidth: 9, headHeight: 10,
            tint: tint, stemLength: diameter - 11, stemColor: stem
        )
    }

    /// The compass screen: a bold black wedge that rides the moon's inner rim.
    ///
    /// `diameter` is the dial's own (twice its radius); the apex stops short of
    /// the tick band and the base stays clear of the figure in the middle.
    static func dial(angle: Double, diameter: CGFloat = 312) -> Needle {
        let radius = diameter / 2
        let height = radius * 0.3
        return Needle(
            angle: angle, diameter: diameter,
            headWidth: radius * 0.3, headHeight: height,
            headInset: radius * 0.12
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
                    Circle().fill(stroke.opacity(0.12))
                }
            }
            .frame(width: diameter, height: diameter)
    }
}
