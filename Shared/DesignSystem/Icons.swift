import SwiftUI

/// The app's own icons, drawn rather than borrowed.
///
/// SF Symbols would be the obvious choice and would look like every other app.
/// These are built from the same four primitives the map already uses — the
/// tilted grid, the ring, the lozenge, the rule — at the map's own line weight,
/// so the chrome and the cartography read as one drawing. Each is a `Shape`, so
/// it scales, takes a stroke style, and tints from the surrounding foreground.
enum Icon {
    /// Turin's block grid, tilted six degrees, in a square frame — the map tab.
    struct Grid: Shape {
        func path(in rect: CGRect) -> Path {
            var inner = Path()
            let step = rect.width / 3
            for index in 1 ..< 3 {
                let offset = step * CGFloat(index)
                inner.move(to: CGPoint(x: rect.minX + offset, y: rect.minY - 3))
                inner.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY + 3))
                inner.move(to: CGPoint(x: rect.minX - 3, y: rect.minY + offset))
                inner.addLine(to: CGPoint(x: rect.maxX + 3, y: rect.minY + offset))
            }
            let tilted = inner.applying(
                CGAffineTransform(translationX: rect.midX, y: rect.midY)
                    .rotated(by: -6 * .pi / 180)
                    .translatedBy(x: -rect.midX, y: -rect.midY)
            )
            var path = Path(roundedRect: rect, cornerRadius: 2)
            path.addPath(tilted)
            return path
        }
    }

    /// Concentric range rings around a fix — the "nearby" tab, and the radar.
    struct Rings: Shape {
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = min(rect.width, rect.height) / 2
            var path = Path()
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            path.addEllipse(in: CGRect(
                x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1
            ))
            return path
        }
    }

    /// A cast-iron lozenge — the saved tab, and the collar stamp.
    struct Lozenge: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        }
    }

    /// Three rules with a stop on each — the settings tab.
    struct Sliders: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let rows: [CGFloat] = [0.16, 0.5, 0.84]
            let stops: [CGFloat] = [0.66, 0.34, 0.58]
            for (row, stop) in zip(rows, stops) {
                let y = rect.minY + rect.height * row
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                let x = rect.minX + rect.width * stop
                path.addEllipse(in: CGRect(x: x - 2.1, y: y - 2.1, width: 4.2, height: 4.2))
            }
            return path
        }
    }

    /// A magnifier whose lens is the same ring as everything else.
    struct Magnifier: Shape {
        func path(in rect: CGRect) -> Path {
            let r = min(rect.width, rect.height) * 0.36
            let c = CGPoint(x: rect.minX + r, y: rect.minY + r)
            var path = Path()
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let start = CGPoint(x: c.x + r * 0.72, y: c.y + r * 0.72)
            path.move(to: start)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        }
    }

    /// A drop — water confirmed.
    struct Drop: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            let tip = CGPoint(x: rect.midX, y: rect.minY)
            let waist = rect.minY + h * 0.42
            var path = Path()
            path.move(to: tip)
            path.addCurve(
                to: CGPoint(x: rect.midX + w * 0.36, y: waist + h * 0.16),
                control1: CGPoint(x: rect.midX + w * 0.16, y: rect.minY + h * 0.24),
                control2: CGPoint(x: rect.midX + w * 0.36, y: waist - h * 0.06)
            )
            path.addArc(
                center: CGPoint(x: rect.midX, y: waist + h * 0.16),
                radius: w * 0.36,
                startAngle: .degrees(0), endAngle: .degrees(180),
                clockwise: false
            )
            path.addCurve(
                to: tip,
                control1: CGPoint(x: rect.midX - w * 0.36, y: waist - h * 0.06),
                control2: CGPoint(x: rect.midX - w * 0.16, y: rect.minY + h * 0.24)
            )
            path.closeSubpath()
            return path
        }
    }

    /// A flag on a pole — reporting a problem.
    struct Flag: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.midY * 0.9))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.62))
            path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.height * 0.62))
            return path
        }
    }

    /// A right turn — the route step marker.
    struct TurnRight: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let w = rect.width, h = rect.height
            path.move(to: CGPoint(x: rect.minX + w * 0.12, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.42))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + w * 0.52, y: rect.minY + h * 0.16),
                control: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.16)
            )
            path.addLine(to: CGPoint(x: rect.maxX - w * 0.06, y: rect.minY + h * 0.16))
            path.move(to: CGPoint(x: rect.maxX - w * 0.34, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - w * 0.06, y: rect.minY + h * 0.16))
            path.addLine(to: CGPoint(x: rect.maxX - w * 0.34, y: rect.minY + h * 0.34))
            return path
        }
    }

    // MARK: Poster glyphs
    //
    // Drawn for a stroke of 2.5 pt at about 22 pt, and equally good filled. They
    // are the same shapes the poster is made of — square, circle, diamond,
    // half-disc — so the tab bar and the artwork speak one alphabet.

    /// A cross, for clearing a field.
    struct Cross: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            return path
        }
    }

    /// Mapa: a square with one diagonal street through it.
    struct TabMap: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path(rect)
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.16))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.16))
            return path
        }
    }

    /// Perto: a circle inside a circle.
    struct TabNearby: Shape {
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = min(rect.width, rect.height) / 2
            var path = Path()
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            path.addEllipse(in: CGRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84))
            return path
        }
    }

    /// Salvas: a diamond.
    struct TabSaved: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        }
    }

    /// Relatos: a half-disc with a tail — someone saying something.
    struct TabFeed: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            let base = rect.minY + h * 0.7
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: base))
            path.addArc(
                center: CGPoint(x: rect.midX, y: base), radius: w / 2,
                startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + w * 0.66, y: base))
            path.addLine(to: CGPoint(x: rect.minX + w * 0.3, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: base))
            path.closeSubpath()
            return path
        }
    }

    /// Ajustes: three bars, each with a square stop.
    struct TabSettings: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let rows: [CGFloat] = [0.14, 0.5, 0.86]
            let stops: [CGFloat] = [0.68, 0.3, 0.56]
            let knob = rect.width * 0.26
            for (row, stop) in zip(rows, stops) {
                let y = rect.minY + rect.height * row
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                let x = rect.minX + rect.width * stop
                path.addRect(CGRect(x: x - knob / 2, y: y - knob / 2, width: knob, height: knob))
            }
            return path
        }
    }
}

/// A drawn icon at a given size and stroke weight.
///
/// Wraps the shapes above so call sites do not repeat the stroke style, and so
/// the whole set can be re-weighted in one place.
struct IconView<S: Shape>: View {
    let shape: S
    var size: CGFloat = 22
    var weight: CGFloat = 1.8
    var tint: Color = Palette.ink
    /// Icons that read better solid than outlined — the lozenge, when saved.
    var filled: Bool = false

    var body: some View {
        Group {
            if filled {
                shape.fill(tint)
            } else {
                shape.stroke(
                    tint,
                    style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size, height: size)
    }
}
