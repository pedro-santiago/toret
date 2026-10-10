import SwiftUI
import WidgetKit

// Each family reads the same `WidgetReading` and splits on one question: are the
// figures measured from *you*? If so the poster speaks in numbers and a bearing.
// If not (no permission, no fix yet, a fix far from Turin) the number would be a
// plausible wrong answer, so the tile leads with the fountain's name, drops the
// arrow, and says where the distance is measured from.

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
                        if reading.isPersonal {
                            DistanceFigure(metres: fountain.distance, size: 62, color: ink.color)
                            Text(fountain.place)
                                .font(Typo.ui(15, 800))
                                .foregroundStyle(ink.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.top, 2)
                        } else {
                            Text(fountain.place.uppercased())
                                .font(Typo.display(24, 900))
                                .tracking(Typo.tracking(-0.01, at: 24))
                                .foregroundStyle(ink.color)
                                .lineLimit(3)
                                .minimumScaleFactor(0.6)
                        }
                        Text(fountain.widgetDetail(measuredFromUser: reading.isPersonal))
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
                        dial(for: fountain, ink: ink)

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
                                measuredFromUser: reading.isPersonal, long: true
                            ))
                                .font(Typo.ui(13))
                                .foregroundStyle(ink.secondary)
                                .lineLimit(1)
                                .padding(.top, 4)
                            if reading.isPersonal {
                                StateLine(fountain: fountain, size: 12, ink: ink.color)
                                    .padding(.top, 5)
                            } else if let note = reading.provenance.shortNote {
                                Text(note)
                                    .font(Typo.ui(12, 700))
                                    .foregroundStyle(ink.color)
                                    .lineLimit(1)
                                    .padding(.top, 5)
                            }
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

    @ViewBuilder
    private func dial(for fountain: Fountain, ink: WidgetInk) -> some View {
        if reading.isPersonal {
            VStack(spacing: 3) {
                NorthLabel(color: ink.color)
                BearingDisc(bearing: fountain.bearing, diameter: 106, needle: ink.color) {
                    DistanceFigure(metres: fountain.distance, size: 34, color: ink.color)
                        .padding(.horizontal, 16)
                }
            }
        } else {
            OriginDisc(diameter: 106, ink: ink.color)
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
                            dial(for: fountain, ink: ink)
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
                                    .font(Typo.display(24, 900))
                                    .tracking(Typo.tracking(-0.01, at: 24))
                                    .foregroundStyle(ink.color)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                    .padding(.top, 2)
                                Text(fountain.widgetDetail(
                                    measuredFromUser: reading.isPersonal, long: true
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
                            .padding(.top, 12)

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
                                    // From the old town, a row's distance is not the
                                    // reader's: the header already says so, and the
                                    // row leaves the figure out rather than repeat it.
                                    if reading.isPersonal {
                                        DistanceFigure(metres: row.distance, size: 24, color: ink.color)
                                    }
                                }
                                .padding(.vertical, 10)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(reading.spoken(row))
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

    @ViewBuilder
    private func dial(for fountain: Fountain, ink: WidgetInk) -> some View {
        if reading.isPersonal {
            BearingDisc(bearing: fountain.bearing, diameter: 100, needle: ink.color) {
                DistanceFigure(metres: fountain.distance, size: 32, color: ink.color)
                    .padding(.horizontal, 14)
            }
        } else {
            OriginDisc(diameter: 100, ink: ink.color)
        }
    }
}

// MARK: - Lock Screen: monochrome shapes

/// The system tints everything here, so it is shapes and weight, not colour.
struct LockRectangularView: View {
    let reading: WidgetReading

    var body: some View {
        if let fountain = reading.featured {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(.primary, lineWidth: 2)
                    if reading.isPersonal {
                        Needle(
                            angle: fountain.bearing, diameter: 32,
                            headWidth: 8, headHeight: 10, headInset: 3, tint: .primary
                        )
                    } else {
                        Diamond().fill(.primary).frame(width: 11, height: 11)
                    }
                }
                .frame(width: 32, height: 32)
                .widgetAccentable()

                VStack(alignment: .leading, spacing: 1) {
                    if reading.isPersonal {
                        DistanceFigure(metres: fountain.distance, size: 22, color: .primary)
                    } else {
                        Text(reading.eyebrow)
                            .font(Typo.ui(12, 800))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(fountain.place)
                        .font(Typo.ui(12, 700))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if reading.isPersonal {
                        HStack(spacing: 5) {
                            StateMark(state: fountain.state, size: 11)
                            Text(fountain.state.shortLabel)
                                .font(Typo.ui(11.5, 600))
                                .lineLimit(1)
                        }
                    } else {
                        Text(reading.provenance.shortNote ?? fountain.zone)
                            .font(Typo.ui(11, 600))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(fountain.deepLink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(reading.spoken(fountain))
        } else {
            Text(reading.savedIsEmpty ? String(localized: "Nenhuma fonte salva") : String(localized: "Sem fontes"))
                .font(Typo.ui(14, 800))
        }
    }
}

struct LockCircularView: View {
    let reading: WidgetReading

    var body: some View {
        ZStack {
            Circle().strokeBorder(.primary, lineWidth: 2.5)
            if let fountain = reading.featured, reading.isPersonal {
                Needle(
                    angle: fountain.bearing, diameter: 58,
                    headWidth: 10, headHeight: 12, headInset: 3, tint: .primary
                )
                Text(DistanceFormat.parts(fountain.distance).value)
                    .font(Typo.display(20, 900))
                    .minimumScaleFactor(0.6)
            } else {
                Diamond()
                    .stroke(.primary, lineWidth: 2.5)
                    .frame(width: 20, height: 20)
            }
        }
        .widgetAccentable()
        .widgetURL(reading.featured?.deepLink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.featured.map(reading.spoken) ?? String(localized: "Sem fonte"))
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
            Text(reading.savedIsEmpty ? String(localized: "Toret · nenhuma salva") : String(localized: "Toret"))
        }
    }
}
