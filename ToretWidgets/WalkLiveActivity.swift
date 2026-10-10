import ActivityKit
import SwiftUI
import WidgetKit

/// The walk, on the Lock Screen and in the Dynamic Island: the moon, a black
/// triangle, the metres.
struct WalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            WalkLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Palette.notte)
                .activitySystemActionForegroundColor(Palette.carta)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WalkDisc(state: context.state, diameter: 54) { EmptyView() }
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DistanceFigure(metres: context.state.remaining, size: 30, color: Palette.carta)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.fountainName.uppercased())
                        .font(Typo.display(16, 900))
                        .foregroundStyle(Palette.carta)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.arrived
                        ? String(localized: "Você chegou")
                        : "\(context.state.instruction) · \(context.state.minutes) min")
                        .font(Typo.ui(14, 600))
                        .foregroundStyle(Palette.carta)
                        .lineLimit(1)
                }
            } compactLeading: {
                WalkDisc(state: context.state, diameter: 22) { EmptyView() }
            } compactTrailing: {
                Text(DistanceFormat.short(context.state.remaining))
                    .font(Typo.display(15, 800))
                    .foregroundStyle(Palette.carta)
                    .monospacedDigit()
            } minimal: {
                WalkDisc(state: context.state, diameter: 22) { EmptyView() }
            }
            .widgetURL(DeepLink.route(context.attributes.fountainID).url)
            .keylineTint(Palette.luna)
        }
    }
}
