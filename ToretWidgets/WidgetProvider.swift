import SwiftUI
import WidgetKit

struct FountainEntry: TimelineEntry {
    let date: Date
    let reading: WidgetReading

    /// The gallery and placeholder reading: the nearest water to the old town.
    static var preview: FountainEntry { FountainEntry(date: .now, reading: .preview) }
}

/// Measures once per refresh — from the widget's own location when the user
/// allowed it, from the app's last published position otherwise, and from the old
/// town as a last, labelled, resort.
struct FountainProvider: AppIntentTimelineProvider {
    typealias Intent = FountainSelectionIntent

    func placeholder(in context: Context) -> FountainEntry { .preview }

    func snapshot(for configuration: FountainSelectionIntent, in context: Context) async -> FountainEntry {
        context.isPreview ? .preview : await entry(for: configuration)
    }

    func timeline(
        for configuration: FountainSelectionIntent, in context: Context
    ) async -> Timeline<FountainEntry> {
        let entry = await entry(for: configuration)
        let next = entry.date.addingTimeInterval(RefreshPolicy.interval(for: entry.reading.provenance))
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: FountainSelectionIntent) async -> FountainEntry {
        let measured = await OneShotLocation.fetch(for: .widget, timeout: .seconds(5))
        let resolution = FixResolver.resolve(
            own: measured.fix, bridged: WidgetBridge.origin(), denied: measured.denied
        )
        let reading = WidgetReading.make(
            source: configuration.source,
            saved: WidgetBridge.savedIDs(),
            resolution: resolution,
            cycle: CycleStore.load()
        )
        return FountainEntry(date: .now, reading: reading)
    }
}
