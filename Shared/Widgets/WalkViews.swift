import SwiftUI
import WidgetKit

/// The moon as a dial, with a black triangle on its rim that points at the
/// fountain — turning with the phone when the heading is trustworthy, north-up
/// when it is not. On arrival the triangle gives way to a diamond.
struct WalkDisc<Content: View>: View {
    let state: WalkActivityAttributes.ContentState
    var diameter: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().fill(Palette.luna)
            content()
            if state.arrived {
                Diamond()
                    .fill(Palette.inchiostro)
                    .frame(width: diameter * 0.22, height: diameter * 0.22)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, diameter * 0.04)
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

/// The Lock Screen banner: a night plate with the moon, the metres and the next
/// instruction.
struct WalkLockScreenView: View {
    let attributes: WalkActivityAttributes
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                WalkDisc(state: state, diameter: 78) {
                    if state.arrived {
                        EmptyView()
                    } else {
                        DistanceFigure(metres: state.remaining, size: 26, color: Palette.inchiostro)
                            .padding(.horizontal, 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.arrived ? "Você chegou" : "A pé até")
                        .font(Typo.ui(12.5, 700))
                        .foregroundStyle(Palette.luna)
                    Text(attributes.fountainName.uppercased())
                        .font(Typo.display(23, 900))
                        .tracking(Typo.tracking(-0.01, at: 23))
                        .foregroundStyle(Palette.carta)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(state.arrived
                        ? attributes.zone
                        : "\(state.instruction) · \(state.minutes) min")
                        .font(Typo.ui(13))
                        .foregroundStyle(Palette.carta.opacity(0.85))
                        .lineLimit(1)
                    if !state.isRelative, !state.arrived {
                        Text("Norte para cima")
                            .font(Typo.ui(12))
                            .foregroundStyle(Palette.carta.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            WaterStripes(bands: 3, color: Palette.correnteNotte, gap: Palette.notte)
                .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            state.arrived
                ? "Você chegou a \(attributes.fountainName)"
                : "\(attributes.fountainName), \(DistanceFormat.spoken(state.remaining)), \(state.minutes) minutos a pé. \(state.instruction)"
        )
    }
}
