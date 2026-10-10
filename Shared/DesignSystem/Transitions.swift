import SwiftUI
import UIKit

/// Motion for the list screens and the shared chrome.
///
/// Printed things do not glow; they slide, snap and stack. Everything here is an
/// ease-out — fast at the start, because that is the moment the eye is on it —
/// and short: nothing in a list is allowed to take longer than a third of a
/// second, and nothing runs twice in one launch.
///
/// With Reduce Motion on, movement is dropped and what is left is a short
/// crossfade or a cut. The animation still tells you something changed; it just
/// does not travel to do it.
@MainActor
enum ScreenMotion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// A block rising into place. Strong ease-out: most of the distance is covered
    /// in the first third of the time.
    static var rise: Animation {
        reduced ? .easeOut(duration: 0.15) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.32)
    }

    /// A toggle, a chip, a state change: nothing to watch, only to confirm.
    static var snap: Animation {
        reduced ? .easeOut(duration: 0.1) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    }

    /// A pane changing size or content under your finger.
    static var morph: Animation {
        reduced ? .easeOut(duration: 0.15) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.26)
    }

    /// Pause between one row and the next, in seconds. Short on purpose: a long
    /// stagger is a list that makes you wait for it.
    static let stagger = 0.03

    /// Rows past this index are on screen on arrival and do not animate: the
    /// stagger is for the first screenful, not for the whole catalogue.
    static let staggerLimit = 10
}

/// Which lists have already made their entrance in this launch.
///
/// Tab switches rebuild the screens, so without a ledger every visit to Perto
/// would replay the rise. A list is something you come back to tens of times a
/// day; it gets its entrance once, the first time, and is simply there after.
@MainActor
enum EntranceLedger {
    private static var played: Set<String> = []

    static func hasPlayed(_ key: String) -> Bool { played.contains(key) }
    static func markPlayed(_ key: String) { played.insert(key) }

    /// Forgets everything. For tests.
    static func reset() { played = [] }
}

private struct StaggeredEntrance: ViewModifier {
    let key: String
    let index: Int

    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(key: String, index: Int) {
        self.key = key
        self.index = index
        // Decided before the first frame: a row that is going to be visible
        // already must never flash through opacity 0.
        _shown = State(
            initialValue: EntranceLedger.hasPlayed(key) || index >= ScreenMotion.staggerLimit
        )
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                withAnimation(ScreenMotion.rise.delay(Double(index) * ScreenMotion.stagger)) {
                    shown = true
                }
            }
    }
}

private struct EntranceLedgerMark: ViewModifier {
    let key: String

    func body(content: Content) -> some View {
        content.task {
            // Long enough for every row of the first screenful to have appeared
            // and scheduled itself; rows that scroll in later find the list
            // already played and arrive without moving.
            try? await Task.sleep(for: .milliseconds(700))
            EntranceLedger.markPlayed(key)
        }
    }
}

extension View {
    /// Rises into place with a short stagger, the first time this list appears in
    /// this launch and never again.
    func staggeredEntrance(key: String, index: Int) -> some View {
        modifier(StaggeredEntrance(key: key, index: index))
    }

    /// Put once on the list's container: after the entrance has had time to play,
    /// the list is recorded as seen.
    func marksEntrancePlayed(key: String) -> some View {
        modifier(EntranceLedgerMark(key: key))
    }
}
