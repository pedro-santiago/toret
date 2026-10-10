import SwiftUI

/// Everything the root view has to do for the community feature, in one modifier
/// so the root's own body stays small enough to type-check.
///
/// Hands what the community said to the model (so pins and rows know), starts
/// uploading when the network returns, and refreshes whenever the app comes back
/// to the foreground — a report's state expires with time, and nothing else
/// tells the pins.
struct CommunityHooks: ViewModifier {
    @Environment(ToretModel.self) private var model
    @Environment(Community.self) private var community
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-toret-seed-reports") {
                    community.seedSamples(fountains: model.byDistance)
                }
                #endif
                // What was said while the app was closed reaches the pins before
                // the first refresh does.
                model.apply(summaries: community.summaries)
                community.startMonitoring()
                await community.refresh()
            }
            .onChange(of: community.summaries) { model.apply(summaries: community.summaries) }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                community.recompute()
                Task { await community.refresh() }
            }
    }
}
