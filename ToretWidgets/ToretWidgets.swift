import SwiftUI
import WidgetKit

// MARK: - Timeline

struct CompassEntry: TimelineEntry {
    let date: Date
    let nearest: Fountain
    let nearby: [Fountain]
    /// Whether the distances were measured from the user's own fix.
    ///
    /// The widget carries the same catalogue as the app; the only thing it needs
    /// from the app is where the user is standing. When that has not arrived —
    /// a fresh install, or the compass told to stay inside the app — the figures
    /// are from the centre of Turin and the widget says so rather than passing
    /// them off as an answer.
    let isLive: Bool

    /// The reading as it stands now, from whatever the app last published.
    static func current() -> CompassEntry {
        let origin = WidgetBridge.origin()
        let sorted = Catalogue.fountains(from: origin ?? Catalogue.anchor)
            .sorted { $0.distance < $1.distance }
        return CompassEntry(
            date: .now, nearest: sorted[0], nearby: Array(sorted.prefix(3)),
            isLive: origin != nil
        )
    }

    /// The gallery and placeholder reading, always from the anchor.
    static var preview: CompassEntry {
        let sorted = Catalogue.fountains().sorted { $0.distance < $1.distance }
        return CompassEntry(
            date: .now, nearest: sorted[0], nearby: Array(sorted.prefix(3)), isLive: true
        )
    }
}

struct CompassProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompassEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (CompassEntry) -> Void) {
        completion(context.isPreview ? .preview : .current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompassEntry>) -> Void) {
        // A walking distance goes stale fast; refresh on the quarter hour and let
        // the system move it when the user is not walking. Every fix the app takes
        // reloads this timeline anyway, so the quarter hour is only the floor.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [.current()], policy: .after(next)))
    }
}

// MARK: - Home screen

/// The medium widget: the dial, the name, and the three nearest as chips.
///
/// It is the compass screen at a glance — same needle, same figure, same Bodoni —
/// so that glancing at the home screen and opening the app teach the same thing.
struct CompassWidgetView: View {
    let entry: CompassEntry

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.sage.opacity(0.16), Palette.sage.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 40
                        )
                    )
                    .overlay { Circle().strokeBorder(Palette.sage.opacity(0.35), lineWidth: 1) }

                Needle(
                    angle: entry.nearest.bearing, diameter: 112,
                    headWidth: 14, headHeight: 17, headInset: 8,
                    tint: Palette.sage, stemLength: 9,
                    stemColor: Palette.sage.opacity(0.7), stemFades: true
                )

                VStack(spacing: 3) {
                    Text("\(entry.nearest.distance)")
                        .font(Typo.display(32))
                        .foregroundStyle(Palette.paper)
                    Text("METROS")
                        .font(Typo.narrow(7.5))
                        .tracking(Typo.tracking(0.2, at: 7.5))
                        .foregroundStyle(Palette.paper.opacity(0.55))
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.isLive ? "FONTE MAIS PRÓXIMA" : "NO CENTRO DE TORINO")
                    .font(Typo.narrow(8.5))
                    .tracking(Typo.tracking(0.16, at: 8.5))
                    .foregroundStyle(Palette.paper.opacity(0.55))

                DisplayText(
                    entry.nearest.place, size: 25, leading: 1.05, color: Palette.paper
                )
                .padding(.top, 7)
                .lineLimit(2)

                Text("\(entry.nearest.walkingMinutes) min a pé · \(entry.nearest.state.label)")
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Palette.paper.opacity(0.66))
                    .padding(.top, 6)

                HStack(spacing: 7) {
                    ForEach(entry.nearby) { fountain in
                        HStack(spacing: 5) {
                            Needle(
                                angle: fountain.bearing, diameter: 12,
                                headWidth: 6, headHeight: 7, headInset: 1,
                                tint: fountain.state.nightColor
                            )
                            Text("\(fountain.distance)")
                                .font(Typo.ui(10.5, 500))
                                .foregroundStyle(Palette.paper.opacity(0.8))
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 9)
                        .frame(height: 24)
                        .background {
                            Capsule()
                                .fill(Palette.paper.opacity(0.12))
                                .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
                        }
                    }
                }
                .padding(.top, 13)
            }
        }
        .padding(18)
        .containerBackground(for: .widget) { WidgetGround() }
    }
}

/// The small widget: the distance, big, and the place under it.
struct DistanceWidgetView: View {
    let entry: CompassEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("TORET")
                    .font(Typo.narrow(8.5))
                    .tracking(Typo.tracking(0.18, at: 8.5))
                    .foregroundStyle(Palette.paper.opacity(0.75))
                Spacer()
                Needle(
                    angle: entry.nearest.bearing, diameter: 20,
                    headWidth: 10, headHeight: 12, tint: Palette.paper
                )
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 5) {
                Text("\(entry.nearest.distance)")
                    .font(Typo.display(52))
                    .foregroundStyle(Palette.paperRaised)
                Text("m")
                    .font(Typo.ui(14, 500))
                    .foregroundStyle(Palette.paperRaised.opacity(0.7))
                    .padding(.bottom, 6)
            }

            Text(entry.nearest.place)
                .font(Typo.ui(12.5, 500))
                .foregroundStyle(Palette.paperRaised.opacity(0.85))
                .lineLimit(1)
                .padding(.top, 5)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Palette.sage.opacity(0.65), Palette.green],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// The ground both home-screen widgets sit on — the same tilted grid as the map,
/// under a green-and-brass wash.
struct WidgetGround: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x3C4C3F), Color(hex: 0x212821), Color(hex: 0x151815)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = -size.height
                while x <= size.width + size.height {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += 48
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += 48
                }
                context.rotate(by: .degrees(-6))
                context.stroke(path, with: .color(Palette.paper.opacity(0.3)), lineWidth: 1)
            }
            .opacity(0.14)
        }
    }
}

// MARK: - Lock screen

/// The rectangular lock-screen complication: needle, place, and state.
struct LockRectangularView: View {
    let entry: CompassEntry

    var body: some View {
        HStack(spacing: 10) {
            Needle(
                angle: entry.nearest.bearing, diameter: 30,
                headWidth: 10, headHeight: 12, headInset: 2,
                tint: .primary, stemLength: 8, stemColor: .primary.opacity(0.5)
            )
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.nearest.distance) m · \(entry.nearest.walkingMinutes) min")
                    .font(.system(size: 15, weight: .semibold))
                Text(entry.nearest.place)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(entry.nearest.state.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// The circular complication: the needle round the figure.
struct LockCircularView: View {
    let entry: CompassEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Needle(
                angle: entry.nearest.bearing, diameter: 54,
                headWidth: 9, headHeight: 11, headInset: 2, tint: .primary
            )
            Text("\(entry.nearest.distance)")
                .font(.system(size: 17, weight: .medium))
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// The inline complication, above the clock.
struct LockInlineView: View {
    let entry: CompassEntry

    var body: some View {
        Text(
            entry.isLive
                ? "Água a \(entry.nearest.distance) m · \(entry.nearest.place)"
                : "Toret · \(entry.nearest.place)"
        )
    }
}

// MARK: - Declarations

struct CompassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "toret.compass", provider: CompassProvider()) { entry in
            CompassWidgetView(entry: entry)
        }
        .configurationDisplayName("Bússola")
        .description("A agulha e a distância até a fonte mais próxima.")
        .supportedFamilies([.systemMedium])
    }
}

struct DistanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "toret.distance", provider: CompassProvider()) { entry in
            DistanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Distância")
        .description("Quantos metros até a água.")
        .supportedFamilies([.systemSmall])
    }
}

struct LockCompassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "toret.lock", provider: CompassProvider()) { entry in
            LockWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Bússola")
        .description("A fonte mais próxima, na tela bloqueada.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct LockWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CompassEntry

    var body: some View {
        switch family {
        case .accessoryCircular: LockCircularView(entry: entry)
        case .accessoryInline: LockInlineView(entry: entry)
        default: LockRectangularView(entry: entry)
        }
    }
}

@main
struct ToretWidgetBundle: WidgetBundle {
    init() {
        Typo.registerBundledFonts()
    }

    var body: some Widget {
        CompassWidget()
        DistanceWidget()
        LockCompassWidget()
    }
}
