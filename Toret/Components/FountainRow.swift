import SwiftUI

/// How far, in words and figures.
///
/// Under a kilometre the figure is whole metres; past it, kilometres with a
/// decimal, because "3200 m" asks the reader to do the division. The decimal
/// separator follows the device, so a phone set to Portuguese says "1,2 km".
enum Distance {
    static func parts(_ metres: Int, locale: Locale = .autoupdatingCurrent) -> (value: String, unit: String) {
        DistanceFormat.parts(metres, locale: locale)
    }

    /// "84 m", "1,2 km".
    static func text(_ metres: Int, locale: Locale = .autoupdatingCurrent) -> String {
        DistanceFormat.short(metres, locale: locale)
    }

    /// For VoiceOver: "84 metros", "1,2 quilômetros".
    static func spoken(_ metres: Int, locale: Locale = .autoupdatingCurrent) -> String {
        DistanceFormat.spoken(metres, locale: locale)
    }
}

/// One fountain in a list, on cream stock or at night.
///
/// Four things, in this order: what the water is doing (a shape, not just a
/// colour), what the place is called, how far it is, and how long that takes. The
/// first three are what decide a walk; the fourth is the same figure in the unit
/// a person actually plans in. Rows are divided by a light rule and nothing else:
/// no chevron, no card — a row that is a button does not need to say so.
struct FountainRow: View {
    let fountain: Fountain
    /// Kept so existing call sites compile. The list used to carry a needle per
    /// row; direction now lives on the compass and the map.
    var needleAngle: Double = 0
    var token: Int = 0
    var isSelected: Bool = false
    var isDimmed: Bool = false
    var night: Bool = false
    /// The compact night variant used inside the compass panel.
    var compact: Bool = false
    /// The other fountains on screen with it. Two of them can share a street name;
    /// the row then adds what tells them apart (see ``Fountain/place(distinguishedIn:)``).
    var siblings: [Fountain] = []
    let action: () -> Void

    private var title: String { fountain.place }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var primary: Color { night ? Palette.carta : Palette.inchiostro }
    private var secondary: Color { night ? Palette.carta.opacity(0.78) : Palette.inchiostro.opacity(0.72) }
    private var rule: Color { night ? Palette.carta.opacity(0.22) : Palette.inchiostro.opacity(0.35) }

    /// "Toret em Cenisia". When the place name already carries the neighbourhood,
    /// the kind alone.
    private var kindLine: String {
        let base = fountain.place.contains(fountain.zone)
            ? fountain.kind.label
            : String(localized: "\(fountain.kind.label) em \(fountain.zone)")
        // Two fountains on the same square read the same; the subtitle says which.
        guard let extra = fountain.distinguisher(in: siblings) else { return base }
        return "\(base) · \(extra)"
    }

    var body: some View {
        Button(action: action) {
            Group {
                if compact { compactBody } else { fullBody }
            }
            .padding(.horizontal, compact ? 0 : 22)
            .padding(.vertical, compact ? 10 : 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(RowPressStyle(night: night))
        .opacity(isDimmed ? 0.45 : 1)
        .background {
            if isSelected, !compact { Palette.cartaScura }
        }
        .overlay(alignment: .leading) {
            if isSelected, !compact {
                Rectangle().fill(Palette.inchiostro).frame(width: 6)
            }
        }
        .overlay(alignment: compact ? .bottom : .top) {
            Rectangle().fill(rule).frame(height: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(kindLine)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(String(localized: "Abre a página da fonte"))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityValue: String {
        var parts = [
            fountain.state.label,
            Distance.spoken(fountain.distance),
            String(localized: "\(fountain.walkingMinutes) minutos a pé"),
        ]
        if let line = fountain.community.ratingLine {
            parts.append(String(localized: "nota \(line)"))
        }
        return parts.joined(separator: ". ")
    }

    // MARK: Full

    @ViewBuilder private var fullBody: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    StateMark(state: fountain.state, size: 28, night: night)
                    Spacer(minLength: 12)
                    distance(size: 34)
                }
                names(lines: 3)
                minutes
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                thumbnail
                names(lines: 1)
                VStack(alignment: .trailing, spacing: 2) {
                    distance(size: 30)
                    minutes
                }
            }
        }
    }

    /// The fountain's own plate, small, with the water's state printed on its
    /// corner. The plate never shows water (see ``FountainPlate``), so the mark is
    /// the only thing in this square that speaks about it.
    private var thumbnail: some View {
        FountainPlate(fountain: fountain, night: night)
            .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
            .overlay { Rectangle().strokeBorder(primary, lineWidth: 2) }
            .overlay(alignment: .topLeading) {
                StateMark(state: fountain.state, size: 16, night: night)
                    .padding(3)
                    .background(Circle().fill(night ? Palette.notte : Palette.carta))
                    .overlay { Circle().strokeBorder(primary, lineWidth: 2) }
                    .offset(x: -8, y: -8)
            }
    }

    private static let thumbnailSide: CGFloat = 52

    private func names(lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Typo.ui(18, 700))
                .foregroundStyle(primary)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: lines > 1)
            HStack(spacing: 8) {
                Text(kindLine)
                    .font(Typo.ui(14))
                    .foregroundStyle(secondary)
                    .lineLimit(lines > 1 ? 2 : 1)
                if let average = fountain.community.average {
                    HStack(spacing: 4) {
                        Diamond().fill(primary).frame(width: 8, height: 8)
                        Text(average.formatted(.number.precision(.fractionLength(1))))
                            .font(Typo.ui(14, 700))
                            .foregroundStyle(primary)
                    }
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distance(size: CGFloat) -> some View {
        let parts = Distance.parts(fountain.distance)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts.value)
                .font(Typo.display(size, 800))
                .foregroundStyle(primary)
                .monospacedDigit()
            Text(parts.unit)
                .font(Typo.ui(14, 600))
                .foregroundStyle(secondary)
        }
        .fixedSize()
    }

    private var minutes: some View {
        Text(String(localized: "\(fountain.walkingMinutes) min a pé"))
            .font(Typo.ui(13, 500))
            .foregroundStyle(secondary)
    }

    // MARK: Compact (the compass panel)

    private var compactBody: some View {
        HStack(spacing: 12) {
            StateMark(state: fountain.state, size: 20, night: night)
            Text(title)
                .font(Typo.ui(15, isSelected ? 700 : 500))
                .foregroundStyle(primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            let parts = Distance.parts(fountain.distance)
            Text("\(parts.value) \(parts.unit)")
                .font(Typo.display(18, 800))
                .foregroundStyle(primary)
                .monospacedDigit()
        }
    }
}

/// A row that is pressed turns a shade darker, and nothing else: no glow, no
/// scale. Printed paper does not respond; it just gets handled.
struct RowPressStyle: ButtonStyle {
    var night = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? (night ? Palette.carta.opacity(0.1) : Palette.cartaScura)
                    : Color.clear
            )
    }
}

/// The state badge: the water's shape and the state, spelled out.
struct StatusChip: View {
    let state: WaterState
    var night: Bool = false
    /// Overrides the label when the chip needs to carry more than the state —
    /// the kind of fountain, or when it was last reported.
    var text: String?
    /// Kept so existing call sites compile; a printed mark does not breathe.
    var breathes: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            StateMark(state: state, size: night ? 16 : 18, night: night)
            Text(text ?? state.label)
                .font(Typo.ui(14, 700))
                .foregroundStyle(night ? Palette.carta : Palette.inchiostro)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay {
            Rectangle().strokeBorder(
                night ? Palette.carta.opacity(0.85) : Palette.inchiostro, lineWidth: 2
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text ?? state.label)
    }
}
