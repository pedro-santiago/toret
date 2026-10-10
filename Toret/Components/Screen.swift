import SwiftUI
import UIKit

/// The device's own safe-area insets.
///
/// The map screen needs two things at once: a basemap that bleeds under the
/// status bar and the home indicator, and glass positioned against the *real*
/// edges of the display. SwiftUI cannot give both through one hierarchy —
/// `ignoresSafeArea` on the map propagates out through the stack that contains
/// it and takes the insets with it, and a `GeometryReader` above that then
/// reports zero. So the numbers are read from the window, where they are not in
/// dispute, and applied as explicit padding.
///
/// Every other screen uses the ordinary safe area and never touches this.
@MainActor
enum Screen {
    static var safeArea: EdgeInsets {
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

        return EdgeInsets(
            top: insets.top, leading: insets.left,
            bottom: insets.bottom, trailing: insets.right
        )
    }

    /// Everything a screen has to clear at the bottom: the home indicator and
    /// the tab bar sitting on top of it.
    ///
    /// Screens ignore the bottom safe area and pad by this instead. Mixing the
    /// two — SwiftUI's inset for some screens, an explicit number for others —
    /// is what produced buttons hiding behind the bar on half of them.
    static var tabBarClearance: CGFloat {
        safeArea.bottom + ToretTabBar.contentHeight
    }
}

/// Launch-argument switches, so a screenshot script can reach screens and scroll
/// positions the simulator has no way to tap its way to.
enum Debug {
    /// `-toret-scroll fim` opens a long screen at its foot.
    static var startsAtBottom: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-toret-scroll"),
              arguments.indices.contains(flag + 1)
        else { return false }
        return arguments[flag + 1] == "fim"
        #else
        return false
        #endif
    }
}
