import SwiftUI
import WidgetKit

struct FountainWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FountainEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            LockCircularView(reading: entry.reading)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            LockRectangularView(reading: entry.reading)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            LockInlineView(reading: entry.reading)
        case .systemMedium:
            MediumFountainView(reading: entry.reading)
                .containerBackground(for: .widget) { Palette.carta }
        case .systemLarge, .systemExtraLarge:
            LargeFountainView(reading: entry.reading)
                .containerBackground(for: .widget) { Palette.carta }
        default:
            SmallFountainView(reading: entry.reading)
                .containerBackground(for: .widget) { Palette.carta }
        }
    }
}

/// The one widget: a fountain, how far, which way — from the home screen, the
/// Lock Screen or StandBy.
struct ToretFountainWidget: Widget {
    static let kind = "toret.fountain"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind, intent: FountainSelectionIntent.self, provider: FountainProvider()
        ) { entry in
            FountainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Fonte mais próxima")
        .description("A distância e a direção até a água, sem abrir o app.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
        // The tiles draw their own margins so the river can run to the edge.
        .contentMarginsDisabled()
    }
}

@main
struct ToretWidgetBundle: WidgetBundle {
    init() {
        Typo.registerBundledFonts()
    }

    var body: some Widget {
        ToretFountainWidget()
        WalkLiveActivity()
        NearestControl()
        RouteControl()
    }
}

#Preview("Pequeno", as: .systemSmall) {
    ToretFountainWidget()
} timeline: {
    FountainEntry.preview
}

#Preview("Médio", as: .systemMedium) {
    ToretFountainWidget()
} timeline: {
    FountainEntry.preview
}

#Preview("Grande", as: .systemLarge) {
    ToretFountainWidget()
} timeline: {
    FountainEntry.preview
}

#Preview("Bloqueio", as: .accessoryRectangular) {
    ToretFountainWidget()
} timeline: {
    FountainEntry.preview
}
