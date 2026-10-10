import SwiftUI

/// The one orchestrated moment: on a cold start the poster assembles itself from
/// the bottom edge, the sun and the Alps first and the river last, and TORET is
/// printed in over the sky, one line after the other.
///
/// It is laid over the first screen, not instead of it, so the app is already
/// loading underneath and is never kept waiting; it ignores touches and removes
/// itself. The first frame is bare cream, the same colour as the system launch
/// screen, so there is no flash between the two. It plays once per process and
/// not at all when Reduce Motion is on: the launch screen simply gives way to the
/// app.
///
/// About 1.15 s in total: the layers slide up over 0.8 s, each on its own curve and
/// the far ones first (see ``ParallaxMath/entranceOffset(depth:progress:)``); the rule
/// and the two lines follow at 0.25, 0.33 and 0.43 s; the plate holds, and it clears
/// in 0.2 s.
struct LaunchOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor private static var hasPlayed = false

    @State private var arrival: CGFloat = 0
    @State private var ruleDrawn = false
    @State private var firstLine = false
    @State private var secondLine = false
    @State private var cleared = false
    @State private var finished = false

    /// Debug-only: `-toret-launch` forces the overlay in front of a
    /// `-toret-screen` shortcut, and `-toret-launch-slow 8` plays it eight times
    /// slower so a screenshot can catch a frame in the middle of it.
    private static let timeScale: Double = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-toret-launch-slow"),
           arguments.indices.contains(flag + 1), let scale = Double(arguments[flag + 1]) {
            return max(1, scale)
        }
        #endif
        return 1
    }()

    private static var suppressedByLaunchArguments: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-toret-screen") && !arguments.contains("-toret-launch")
            && !arguments.contains("-toret-launch-slow")
        #else
        return false
        #endif
    }

    var body: some View {
        if finished {
            EmptyView()
        } else {
            plate
                .opacity(cleared ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task { await play() }
        }
    }

    private var plate: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let titleSize = min(w * 0.26, 104)

            ZStack(alignment: .topLeading) {
                Palette.carta

                // The poster, sitting on the bottom edge. Its layers start below the fold
                // and are clipped by the scene's own frame, so they rise out of the screen.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ParallaxScene(scroll: nil, arrival: arrival, flowing: false)
                }

                wordmark(size: titleSize)
                    .padding(.leading, 22)
                    .padding(.top, Screen.safeArea.top + 14)
            }
            .frame(width: w, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    /// TO / RET, cut like TU / RIN: two lines, a heavy rule down the left.
    private func wordmark(size: CGFloat) -> some View {
        let font = Typo.uiDisplay(size, 900)
        return HStack(alignment: .top, spacing: size * 0.16) {
            Rectangle().fill(Palette.inchiostro)
                .frame(width: 3)
                .scaleEffect(y: ruleDrawn ? 1 : 0, anchor: .top)
            VStack(alignment: .leading, spacing: size * 0.8 - font.lineHeight) {
                line("TO", font: font, size: size, shown: firstLine)
                line("RET", font: font, size: size, shown: secondLine)
            }
        }
        .fixedSize()
    }

    private func line(_ text: String, font: UIFont, size: CGFloat, shown: Bool) -> some View {
        Text(text)
            .font(Font(font))
            .tracking(Typo.tracking(-0.01, at: size))
            .foregroundStyle(Palette.inchiostro)
            .mask(alignment: .leading) {
                // The line is printed in from the left, like a roller going by.
                Rectangle().scaleEffect(x: shown ? 1 : 0.001, anchor: .leading)
            }
    }

    // MARK: Sequence

    private func play() async {
        guard !Self.hasPlayed, !reduceMotion, !Self.suppressedByLaunchArguments else {
            finished = true
            return
        }
        Self.hasPlayed = true
        let t = Self.timeScale

        // One linear run of `arrival`; each layer shapes it into its own ease-out and delay.
        withAnimation(.linear(duration: 0.8 * t)) { arrival = 1 }
        await pause(0.25 * t)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24 * t)) { ruleDrawn = true }
        await pause(0.08 * t)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24 * t)) { firstLine = true }
        await pause(0.10 * t)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24 * t)) { secondLine = true }
        await pause(0.28 * t)
        withAnimation(.easeOut(duration: 0.2 * t)) { cleared = true }
        await pause(0.2 * t)
        finished = true
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

#Preview {
    LaunchOverlay()
}
