import SwiftUI

/// The five tabs, printed on the bottom edge of the plate.
///
/// A flat strip of stock under a 3 pt black rule. The selected tab sits in front
/// of the sun: a yellow disc that slides from tab to tab on a spring, the same
/// disc that rises behind the titles and sets the dial on the compass screen, so
/// the one shape means "you are here" everywhere in the app.
///
/// The glyphs are drawn from the app's own vocabulary rather than taken from SF
/// Symbols — a square with a street through it for the map, rings for where you
/// stand, a diamond for the saved ones, a speech half-disc for what people say,
/// bars for the settings.
struct ToretTabBar: View {
    /// The bar's own height, above the home indicator.
    ///
    /// Fixed rather than intrinsic, and enforced with a frame, so screens can
    /// reserve exactly this much room without measuring anything.
    static let contentHeight: CGFloat = 64

    @Binding var selection: Tab
    /// Tapping the tab you are already on pops that tab to its root.
    var onReselect: (Tab) -> Void = { _ in }

    @Namespace private var sun
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let isOn = selection == tab
                Button {
                    if isOn { onReselect(tab) } else { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if isOn {
                                SunDisc()
                                    .frame(width: 38, height: 38)
                                    .matchedGeometryEffect(id: "sun", in: sun)
                            }
                            TabGlyph(tab: tab, isOn: isOn)
                                .frame(width: 24, height: 24)
                        }
                        .frame(height: 38)

                        Text(tab.title)
                            .font(Typo.ui(11, isOn ? 800 : 600))
                            .foregroundStyle(Palette.inchiostro.opacity(isOn ? 1 : 0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .frame(height: Self.contentHeight)
        .background {
            Palette.carta
                .overlay(alignment: .top) { PosterRule() }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.22),
            value: selection
        )
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// One tab's mark, in black ink; the sun behind it carries the "selected" state.
struct TabGlyph: View {
    let tab: Tab
    let isOn: Bool

    var body: some View {
        switch tab {
        case .map: glyph(Icon.TabMap())
        case .nearby: glyph(Icon.TabNearby())
        case .saved: glyph(Icon.TabSaved())
        case .community: glyph(Icon.TabFeed())
        case .settings: glyph(Icon.TabSettings())
        }
    }

    private func glyph<S: Shape>(_ shape: S) -> some View {
        IconView(shape: shape, size: 21, weight: isOn ? 2.2 : 1.9, tint: Palette.inchiostro)
    }
}
