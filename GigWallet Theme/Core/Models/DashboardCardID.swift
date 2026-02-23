import SwiftUI

// MARK: - Dashboard Sections

/// The three focused views on the dashboard, each with its own set of reorderable cards.
enum DashboardSection: String, CaseIterable, Identifiable {
    case action = "Action"
    case insights = "Insights"
    case optimize = "Optimize"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .action: return "bolt.fill"
        case .insights: return "brain.head.profile.fill"
        case .optimize: return "slider.horizontal.3"
        }
    }
}

// MARK: - Dashboard Card Identifiers

/// Identifies every reorderable card on the dashboard.
/// The top 4 elements (greeting, earnings summary, quick actions, section picker) are fixed.
enum DashboardCardID: String, CaseIterable, Identifiable, Codable {
    // Action section
    case workAdvisor
    case taxCountdown
    case earningsGoal
    case localEvents
    case financialPlanner

    // Insights section
    case financialHealth
    case aiIntelligence
    case incomeMomentum

    // Optimize section
    case earningsHeatmap
    case taxBite
    case taxVault  // Was taxReserve — renamed to reflect interactive Tax Vault

    var id: String { rawValue }

    /// Human-readable name shown in the reorder sheet
    var displayName: String {
        switch self {
        case .workAdvisor: return "Work Advisor"
        case .taxCountdown: return "Tax Countdown"
        case .earningsGoal: return "Earnings Goal"
        case .localEvents: return "Local Events"
        case .financialPlanner: return "Financial Planner"
        case .financialHealth: return "Financial Health"
        case .aiIntelligence: return "AI Intelligence"
        case .incomeMomentum: return "Income Momentum"
        case .earningsHeatmap: return "Earnings Heatmap"
        case .taxBite: return "Today's Tax Bite"
        case .taxVault: return "Tax Vault"
        }
    }

    /// SF Symbol for the reorder sheet row
    var icon: String {
        switch self {
        case .workAdvisor: return "brain.head.profile.fill"
        case .taxCountdown: return "clock.badge.exclamationmark"
        case .earningsGoal: return "target"
        case .localEvents: return "calendar.badge.clock"
        case .financialPlanner: return "chart.bar.doc.horizontal.fill"
        case .financialHealth: return "heart.text.clipboard.fill"
        case .aiIntelligence: return "cpu.fill"
        case .incomeMomentum: return "arrow.up.right.circle.fill"
        case .earningsHeatmap: return "square.grid.3x3.fill"
        case .taxBite: return "scissors"
        case .taxVault: return "lock.shield.fill"
        }
    }

    /// Which section this card belongs to
    var section: DashboardSection {
        switch self {
        case .workAdvisor, .taxCountdown, .earningsGoal, .localEvents, .financialPlanner:
            return .action
        case .financialHealth, .aiIntelligence, .incomeMomentum:
            return .insights
        case .earningsHeatmap, .taxBite, .taxVault:
            return .optimize
        }
    }

    /// Whether this card requires Pro subscription
    var isPremium: Bool {
        switch self {
        case .workAdvisor, .financialHealth, .aiIntelligence, .earningsHeatmap, .financialPlanner:
            return true
        default:
            return false
        }
    }

    /// Whether this card is conditionally shown (e.g. only when data exists)
    var isConditional: Bool {
        self == .localEvents
    }

    /// Minimum experience level required to see this card.
    /// Cards below the user's level are hidden unless "Show All Cards" is enabled.
    var minimumLevel: DashboardExperienceLevel {
        switch self {
        // Newcomer — always visible (core value cards)
        case .taxCountdown, .earningsGoal, .taxBite:
            return .newcomer
        // Active — unlock after engagement (2+ weeks, 10+ entries)
        case .incomeMomentum, .taxVault, .localEvents, .financialPlanner:
            return .active
        // Power — premium/advanced (1+ month + subscribed)
        case .workAdvisor, .financialHealth, .aiIntelligence, .earningsHeatmap:
            return .power
        }
    }

    /// Default card order for each section (matches the original hardcoded order)
    static func defaultOrder(for section: DashboardSection) -> [DashboardCardID] {
        switch section {
        case .action:
            return [.workAdvisor, .taxCountdown, .earningsGoal, .localEvents, .financialPlanner]
        case .insights:
            return [.financialHealth, .aiIntelligence, .incomeMomentum]
        case .optimize:
            return [.earningsHeatmap, .taxBite, .taxVault]
        }
    }
}
