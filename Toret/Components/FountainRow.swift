import SwiftUI

/// One fountain in a list, on plaster or at night.
///
/// The needle at the head of the row is the same instrument as the one filling
/// the compass screen — it points where the fountain actually is, so a list of
/// distances is also a list of directions. Reading down the rows tells you which
/// way to turn before you have opened anything.
struct FountainRow: View {
    let fountain: Fountain
    let needleAngle: Double
    let token: Int
    var isSelected: Bool = false
    var isDimmed: Bool = false
    var night: Bool = false
    /// The compact night variant used inside the compass panel.
    var compact: Bool = false
    let action: () -> Void

    private var primary: Color {
        if night { return isSelected ? Palette.paper : Palette.paper.opacity(0.75) }
        return Palette.ink
    }

    private var secondary: Color {
        night ? Palette.paper.opacity(0.6) : Palette.ink.opacity(0.55)
    }

    private var stem: Color {
        night ? Palette.paper.opacity(0.25) : Palette.ink.opacity(0.2)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Needle.row(
                    angle: needleAngle,
                    tint: fountain.state.color(night: night),
                    stem: stem,
                    diameter: compact ? 22 : 20
                )
                .animation(Motion.needle, value: token)

                if compact {
                    Text(fountain.place)
                        .font(Typo.ui(14.5, 500))
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(fountain.distance) m")
                        .font(Typo.display(15))
                        .foregroundStyle(Palette.paper.opacity(0.7))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fountain.place)
                            .font(Typo.ui(15.5, 500))
                            .foregroundStyle(primary)
                            .lineLimit(1)
                        Text("\(fountain.plateTitle) · \(fountain.state.label)")
                            .font(Typo.ui(12.5))
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(fountain.distance) m")
                            .font(Typo.display(19))
                            .foregroundStyle(primary)
                        Text("\(fountain.walkingMinutes) min")
                            .font(Typo.ui(11, 500))
                            .foregroundStyle(secondary)
                    }
                }
            }
            .padding(.horizontal, compact ? 0 : 22)
            .padding(.vertical, compact ? 9 : 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.45 : 1)
        .background {
            if isSelected, !compact {
                Palette.green.opacity(0.07)
            }
        }
        .overlay(alignment: compact ? .bottom : .top) {
            Rectangle()
                .fill(night ? Palette.paper.opacity(0.1) : Palette.ink.opacity(0.09))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fountain.place), \(fountain.plateTitle)")
        .accessibilityValue(
            "\(fountain.state.label). \(fountain.distance) metros, \(fountain.walkingMinutes) minutos a pé"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The state badge: a dot in the state colour and the state, spelled out.
struct StatusChip: View {
    let state: WaterState
    var night: Bool = false
    /// Overrides the label when the chip needs to carry more than the state —
    /// a plate number, or the provenance of the reading.
    var text: String?
    var breathes: Bool = false

    @State private var breath = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.color(night: night))
                .frame(width: night ? 7 : 8, height: night ? 7 : 8)
                .opacity(breathes ? (breath ? 0.9 : 0.35) : 1)

            Text(text ?? state.label)
                .font(Typo.ui(12.5, night ? 500 : 600))
                .foregroundStyle(night ? Palette.paper.opacity(0.85) : state.color)
        }
        .padding(.horizontal, night ? 12 : 13)
        .frame(height: night ? 26 : 34)
        .background {
            Capsule().fill(
                night ? Palette.sage.opacity(0.14) : state.color.opacity(0.1)
            )
        }
        .onAppear {
            guard breathes else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                breath = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}
