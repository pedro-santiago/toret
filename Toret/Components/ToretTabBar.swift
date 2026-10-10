import SwiftUI

/// The four tabs, on a single pane of Liquid Glass.
///
/// The glyphs are drawn from the app's own vocabulary rather than taken from SF
/// Symbols: the tilted block grid for the map, range rings for where you stand,
/// the cast-iron lozenge for the saved ones, three ruled sliders for the
/// settings. The same four marks appear on the map, in the ornament and on the
/// app icon, so there is one small alphabet to learn instead of two.
struct ToretTabBar: View {
    /// The bar's own height, above the home indicator.
    ///
    /// Fixed rather than intrinsic, and enforced with a frame, so screens can
    /// reserve exactly this much room without measuring anything.
    static let contentHeight: CGFloat = 64

    @Binding var selection: Tab
    /// Tapping the tab you are already on pops that tab to its root.
    var onReselect: (Tab) -> Void = { _ in }

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let isOn = selection == tab
                Button {
                    if isOn { onReselect(tab) } else { selection = tab }
                } label: {
                    VStack(spacing: 6) {
                        TabGlyph(tab: tab, isOn: isOn)
                            .frame(width: 22, height: 22)
                        Text(tab.title)
                            .font(Typo.ui(10.5, isOn ? 600 : 500))
                            .foregroundStyle(isOn ? Palette.green : Palette.ink.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isOn {
                            // The selected tab carries its own small pane, which
                            // slides between tabs rather than cutting.
                            Capsule()
                                .fill(Palette.green.opacity(0.10))
                                .matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.contentHeight)
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(
                    .regular.tint(Color(hex: 0xFFFDF8, opacity: 0.34)),
                    in: .rect
                )
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.6)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(duration: 0.34, bounce: 0.18), value: selection)
    }
}

struct TabGlyph: View {
    let tab: Tab
    let isOn: Bool

    private var tint: Color { isOn ? Palette.green : Palette.ink.opacity(0.45) }
    private var weight: CGFloat { isOn ? 2 : 1.7 }

    var body: some View {
        switch tab {
        case .map:
            IconView(shape: Icon.Grid(), size: 19, weight: weight, tint: tint)
        case .nearby:
            ZStack {
                IconView(shape: Icon.Rings(), size: 19, weight: weight, tint: tint)
                Circle().fill(tint).frame(width: 3.4, height: 3.4)
            }
        case .saved:
            IconView(
                shape: Icon.Lozenge(), size: 17, weight: weight,
                tint: tint, filled: isOn
            )
        case .community:
            IconView(shape: Icon.Voices(), size: 19, weight: weight, tint: tint)
        case .settings:
            IconView(shape: Icon.Sliders(), size: 18, weight: weight, tint: tint)
        }
    }
}
