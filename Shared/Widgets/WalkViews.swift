import SwiftUI
import WidgetKit

/// The moon as a dial, with a black triangle on its rim that points at the
/// fountain — turning with the phone when the heading is trustworthy, north-up
/// when it is not. On arrival the triangle gives way to a diamond in the middle.
///
/// The metres are *not* inside it: a three-digit figure is wider than a Dynamic
/// Island's disc, and the triangle on the rim would run through it.
struct WalkDisc: View {
    let state: WalkActivityAttributes.ContentState
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Palette.luna)
            if state.arrived {
                Diamond()
                    .fill(Palette.inchiostro)
                    .frame(width: diameter * 0.34, height: diameter * 0.34)
            } else {
                Needle(
                    angle: state.needleAngle, diameter: diameter,
                    headWidth: diameter * 0.2, headHeight: diameter * 0.22,
                    headInset: diameter * 0.03, tint: Palette.inchiostro
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The Lock Screen banner: a night plate with the moon, the name and next
/// instruction, and the metres set large on the right.
struct WalkLockScreenView: View {
    let attributes: WalkActivityAttributes
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                WalkDisc(state: state, diameter: 72)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.arrived ? String(localized: "Você chegou") : String(localized: "A pé até"))
                        .font(Typo.ui(12.5, 700))
                        .foregroundStyle(Palette.luna)
                    Text(attributes.fountainName.uppercased())
                        .font(Typo.display(21, 900))
                        .tracking(Typo.tracking(-0.01, at: 21))
                        .foregroundStyle(Palette.carta)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(state.arrived ? attributes.zone : state.instruction)
                        .font(Typo.ui(13))
                        .foregroundStyle(Palette.carta.opacity(0.85))
                        .lineLimit(1)
                    if !state.isRelative, !state.arrived {
                        Text("Norte para cima")
                            .font(Typo.ui(12))
                            .foregroundStyle(Palette.carta.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !state.arrived {
                    VStack(alignment: .trailing, spacing: 0) {
                        DistanceFigure(metres: state.remaining, size: 36, color: Palette.carta)
                        Text("\(state.minutes) min")
                            .font(Typo.ui(12.5, 700))
                            .foregroundStyle(Palette.luna)
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            WaterStripes(bands: 3, color: Palette.correnteNotte, gap: Palette.notte)
                .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    /// The whole state in one sentence, for VoiceOver: where, how far, how long,
    /// and what to do next.
    private var spoken: String {
        guard !state.arrived else {
            return String(localized: "Você chegou a \(attributes.fountainName)")
        }
        let walk = String(localized: "\(state.minutes) minutos a pé")
        let distance = DistanceFormat.spoken(state.remaining)
        return String(localized: "\(attributes.fountainName), \(distance), \(walk). \(state.instruction)")
    }
}
