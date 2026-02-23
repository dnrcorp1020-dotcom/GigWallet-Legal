import SwiftUI

/// User's preferred appearance mode
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
@Observable
final class AppState {
    var hasCompletedAuth: Bool
    var hasCompletedOnboarding: Bool
    var selectedTab: AppTab = .dashboard
    var showingAddEntry: Bool = false
    var showingPaywall: Bool = false

    /// Deep link action from widgets
    var deepLinkAction: DeepLinkAction? = nil

    /// User's preferred appearance: system, light, or dark
    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }

    init() {
        // Restore persisted state to prevent auth/onboarding flash on cold launch
        hasCompletedAuth = UserDefaults.standard.bool(forKey: "hasCompletedAuth")
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Restore appearance preference
        let savedAppearance = UserDefaults.standard.string(forKey: "appearanceMode") ?? "System"
        appearanceMode = AppearanceMode(rawValue: savedAppearance) ?? .system
    }

    func markAuthCompleted() {
        hasCompletedAuth = true
        UserDefaults.standard.set(true, forKey: "hasCompletedAuth")
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    /// Signs the user out: clears Firebase auth, local state, and API token.
    /// The SwiftData profile is NOT deleted — it remains as an anonymous local profile.
    /// This allows preserving financial data while removing the auth association.
    func signOut() {
        // Sign out from Firebase
        try? FirebaseAuthManager.shared.signOut()

        // Clear API client token
        APIClient.shared.clearAuthToken()

        // Reset navigation state — sends user back to AuthView
        hasCompletedAuth = false
        UserDefaults.standard.set(false, forKey: "hasCompletedAuth")

        // Keep onboarding completed — they don't need to redo onboarding after re-signing in
    }
}

/// Actions triggered by widget deep links (gigwallet:// URL scheme)
enum DeepLinkAction {
    case addIncome
    case addExpense
    case addMileage
}

enum AppTab: Int, CaseIterable, Identifiable {
    case dashboard = 0
    case income = 1
    case addEntry = 2
    case expenses = 3
    case taxCenter = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .income: return "Income"
        case .addEntry: return "Add"
        case .expenses: return "Expenses"
        case .taxCenter: return "Tax Center"
        }
    }

    var sfSymbol: String {
        switch self {
        case .dashboard: return "wallet.bifold.fill"
        case .income: return "dollarsign.circle.fill"
        case .addEntry: return "plus.circle.fill"
        case .expenses: return "creditcard.fill"
        case .taxCenter: return "building.columns.fill"
        }
    }
}
