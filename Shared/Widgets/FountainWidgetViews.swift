import SwiftUI
import WidgetKit

// MARK: - Small: a poster tile

/// A cream tile with the distance set as large as it will go, the way the poster
/// sets "TURIN". One fountain, one number, a river along the foot.
struct SmallFountainView: View {
    let reading: WidgetReading
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let ink = WidgetInk(mode: mode)
        ZStack(alignment: .bottom) {
            Group {
                if let fountain = reading.featured {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(reading.eyebrow)
                                .font(Typo.ui(12, 700))
                                .foregroundStyle(ink.color)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            CycleButton(count: reading.cycleCount, ink: ink.color)
                        }
                        Spacer(minLength: 0)
                        DistanceFigure(metres: fountain.distance, size: 64, color: ink.color)
                        Text(fountain.place)
                            .font(Typo.ui(15, 800))
                            .foregroundStyle(ink.color)
                            .lineLimit(1)
                            .padding(.top, 2)
                        Text(fountain.widgetDetail(measuredFromUser: reading.provenance.isMeasuringFromUser))
                            .font(Typo.ui(12.5))
                            .foregroundStyle(ink.secondary)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                    .widgetURL(fountain.deepLink)
                    .accessibilityElement(children: .contain)
                } else {
                    EmptyReading(reading: reading, ink: ink.color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WidgetRiver(height: 12)
        }
    }
}

// MARK: - Medium: the sun dial

/// The sun as a dial, with the distance inside it, a black triangle on its rim,
/// and the name beside it in poster capitals.
struct MediumFountainView: View {
    let reading: WidgetReading
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let ink = WidgetInk(mode: mode)
        ZStack(alignment: .bottom) {
            Group {
                if let fountain = reading.featured {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(spacing: 3) {
                            NorthLabel(color: ink.color)
                            BearingDisc(bearing: fountain.bearing, diameter: 106, needle: ink.color) {
                                DistanceFigure(metres: fountain.distance, size: 34, color: ink.color)
                                    .padding(.horizontal, 16)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top) {
                                Text(reading.eyebrow)
                                    .font(Typo.ui(12, 700))
                                    .foregroundStyle(ink.color)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                CycleButton(count: reading.cycleCount, ink: ink.color)
                            }
                            Text(fountain.place.uppercased())
                                .font(Typo.display(25, 900))
                                .tracking(Typo.tracking(-0.01, at: 25))
                                .foregroundStyle(ink.color)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                                .padding(.top, 2)
                            Text(fountain.widgetDetail(
                                measuredFromUser: reading.provenance.isMeasuringFromUser, long: true
                            ))
                                .font(Typo.ui(13))
                                .foregroundStyle(ink.secondary)
                                .lineLimit(1)
                                .padding(.top, 4)
                            StateLine(fountain: fountain, size: 12, ink: ink.color)
                                .padding(.top, 5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .widgetURL(fountain.deepLink)
                    .accessibilityElement(children: .contain)
                } else {
                    EmptyReading(reading: reading, ink: ink.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WidgetRiver(height: 12)
        }
    }
}

// MARK: - Large: four rows

/// The dial and the name on top, then the four nearest as rows, each its own link.
struct LargeFountainView: View {
    let reading: WidgetReading
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let ink = WidgetInk(mode: mode)
        ZStack(alignment: .bottom) {
            Group {
                if let fountain = reading.featured {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 14) {
                            BearingDisc(bearing: fountain.bearing, diameter: 92, needle: ink.color) {
                                DistanceFigure(metres: fountain.distance, size: 30, color: ink.color)
                                    .padding(.horizontal, 14)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(reading.eyebrow)
                                    .font(Typo.ui(12, 700))
                                    .foregroundStyle(ink.color)
                                    .lineLimit(1)
                                Text(fountain.place.uppercased())
                                    .font(Typo.display(24, 900))
                                    .tracking(Typo.tracking(-0.01, at: 24))
                                    .foregroundStyle(ink.color)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                    .padding(.top, 2)
                                Text(fountain.widgetDetail(
                                    measuredFromUser: reading.provenance.isMeasuringFromUser, long: true
                                ))
                                    .font(Typo.ui(12.5))
                                    .foregroundStyle(ink.secondary)
                                    .lineLimit(1)
                                    .padding(.top, 3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .widgetURL(fountain.deepLink)

                        if let note = reading.lookHint ?? reading.provenance.note {
                            Text(note)
                                .font(Typo.ui(12.5))
                                .foregroundStyle(ink.secondary)
                                .lineLimit(2)
                                .padding(.top, 8)
                        }

                        PosterRule()
                            .padding(.top, 10)

                        ForEach(Array(reading.candidates.enumerated()), id: \.element.id) { index, row in
                            Link(destination: row.deepLink) {
                                HStack(spacing: 11) {
                                    StateMark(state: row.state, size: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.place)
                                            .font(Typo.ui(15, 800))
                                            .foregroundStyle(ink.color)
                                            .lineLimit(1)
                                        Text(row.state == .unknown ? row.zone : row.state.label)
                                            .font(Typo.ui(12))
                                            .foregroundStyle(ink.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    DistanceFigure(metres: row.distance, size: 24, color: ink.color)
                                }
                                .padding(.vertical, 7)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(row.widgetSpoken)
                            }
                            if index < reading.candidates.count - 1 {
                                PosterRule(weight: .light, color: ink.color)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    EmptyReading(reading: reading, ink: ink.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WidgetRiver(height: 12)
        }
    }
}

// MARK: - Lock Screen: monochrome shapes

/// The system tints everything here, so it is shapes and weight, not colour.
struct LockRectangularView: View {
    let reading: WidgetReading

    var body: some View {
        if let fountain = reading.featured {
            HStack(spacing: 10) {
                ZStack {
                    Circle().strokeBorder(.primary, lineWidth: 2)
                    Needle(
                        angle: fountain.bearing, diameter: 36,
                        headWidth: 9, headHeight: 11, headInset: 3, tint: .primary
                    )
                }
                .frame(width: 36, height: 36)
                .widgetAccentable()

                VStack(alignment: .leading, spacing: 1) {
                    if reading.provenance.isMeasuringFromUser {
                        DistanceFigure(metres: fountain.distance, size: 22, color: .primary)
                    } else {
                        Text(reading.eyebrow)
                            .font(Typo.ui(13, 800))
                            .lineLimit(1)
                    }
                    Text(fountain.place)
                        .font(Typo.ui(13, 700))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        StateMark(state: fountain.state, size: 11)
                        Text(fountain.state.shortLabel)
                            .font(Typo.ui(11.5, 600))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(fountain.deepLink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(fountain.widgetSpoken)
        } else {
            Text(reading.savedIsEmpty ? "Nenhuma fonte salva" : "Sem fontes")
                .font(Typo.ui(14, 800))
        }
    }
}

struct LockCircularView: View {
    let reading: WidgetReading

    var body: some View {
        ZStack {
            Circle().strokeBorder(.primary, lineWidth: 2.5)
            if let fountain = reading.featured {
                Needle(
                    angle: fountain.bearing, diameter: 58,
                    headWidth: 10, headHeight: 12, headInset: 3, tint: .primary
                )
                Text(reading.provenance.isMeasuringFromUser
                    ? DistanceFormat.parts(fountain.distance).value : "–")
                    .font(Typo.display(20, 900))
                    .minimumScaleFactor(0.6)
            } else {
                Diamond().stroke(.primary, lineWidth: 2.5).frame(width: 20, height: 20)
            }
        }
        .widgetAccentable()
        .widgetURL(reading.featured?.deepLink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.featured?.widgetSpoken ?? "Sem fonte")
    }
}

struct LockInlineView: View {
    let reading: WidgetReading

    var body: some View {
        if let fountain = reading.featured {
            switch reading.provenance {
            case .live, .approximate:
                Text("Fonte a \(DistanceFormat.short(fountain.distance)) · \(fountain.place)")
            case .centre:
                Text("Toret · \(fountain.place)")
            case .outsideTurin:
                Text("Toret · longe de Turim")
            }
        } else {
            Text(reading.savedIsEmpty ? "Toret · nenhuma salva" : "Toret")
        }
    }
}
