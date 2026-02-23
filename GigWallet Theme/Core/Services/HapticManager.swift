import UIKit

/// Centralized haptic feedback system — gives the app a tactile, premium feel
/// Every button press, action completion, and state change should FEEL real
@MainActor
final class HapticManager: @unchecked Sendable {
    static let shared = HapticManager()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        // Pre-warm all generators for instant response
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        impactSoft.prepare()
        impactRigid.prepare()
        selection.prepare()
        notification.prepare()
    }

    // MARK: - Button & Tap Feedback

    /// Standard button tap — light, crisp
    func tap() {
        impactLight.impactOccurred()
    }

    /// Primary action button (add income, add expense) — medium weight
    func action() {
        impactMedium.impactOccurred()
    }

    /// Heavy action (delete, destructive) — firm feedback
    func heavy() {
        impactHeavy.impactOccurred()
    }

    // MARK: - Selection & Navigation

    /// Tab change, picker scroll, segment switch
    func select() {
        selection.selectionChanged()
    }

    /// Soft touch for subtle interactions (card hover, toggle)
    func soft() {
        impactSoft.impactOccurred()
    }

    // MARK: - Notifications & Outcomes

    /// Success — income saved, goal reached, export complete
    func success() {
        notification.notificationOccurred(.success)
    }

    /// Warning — approaching threshold, deadline near
    func warning() {
        notification.notificationOccurred(.warning)
    }

    /// Error — validation failed, save error
    func error() {
        notification.notificationOccurred(.error)
    }

    // MARK: - Complex Patterns

    /// Double-tap confirmation pattern for important actions
    func confirm() {
        impactMedium.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            impactLight.impactOccurred()
        }
    }

    /// Ascending intensity — for counter animations or progress completion
    func ramp() {
        impactSoft.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            impactLight.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [self] in
            impactMedium.impactOccurred()
        }
    }

    /// Celebration — goal reached, big milestone
    func celebrate() {
        impactHeavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            notification.notificationOccurred(.success)
        }
    }
}
