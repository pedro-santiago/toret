import SwiftUI
import UIKit

/// The few moments in the app that earn a tap on the wrist.
///
/// Feedback that fires on everything teaches people to ignore all of it, so the
/// list is short and each entry names a *causal event* — the thing flipping, the
/// needle lining up, the walk ending — and fires on that frame, not after.
/// Both paths here go through the system haptic engine, so the user's Settings >
/// Sounds & Haptics switch silences them without the app doing anything.
enum HapticKind: Sendable {
    /// A choice was made: picking a pin, a filter, a tab.
    case selection
    /// Something engaged. A light, crisp tick — the needle lining up.
    case tick
    /// A thing was kept: saved, rated, sent.
    case success
    /// The walk is over. Distinct from `.success` in weight, not in kind.
    case arrival
    /// Something did not go through.
    case warning

    var feedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .tick: .impact(flexibility: .rigid, intensity: 0.7)
        case .success: .success
        case .arrival: .impact(weight: .heavy, intensity: 1)
        case .warning: .warning
        }
    }
}

@MainActor
enum Haptics {
    /// Fires a haptic from code that is not a view (a location callback, an intent).
    static func fire(_ kind: HapticKind) {
        switch kind {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .tick:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred(intensity: 0.7)
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .arrival:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}

extension View {
    /// Fires `kind` when `trigger` changes. `when` can narrow which changes count —
    /// `{ _, now in now }` to fire only on the way *into* a state.
    func haptic<T: Equatable>(
        _ kind: HapticKind, on trigger: T, when condition: @escaping (T, T) -> Bool = { _, _ in true }
    ) -> some View {
        sensoryFeedback(trigger: trigger) { old, new in
            condition(old, new) ? kind.feedback : nil
        }
    }
}
