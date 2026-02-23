import Foundation

/// Controls progressive card disclosure on the dashboard.
/// New users see fewer cards to reduce overwhelm; cards unlock as they engage.
enum DashboardExperienceLevel: Int, Codable, CaseIterable, Comparable {
    case newcomer = 0   // First 2 weeks OR <10 entries — core cards only
    case active = 1     // 2+ weeks AND 10+ entries — most cards visible
    case power = 2      // 1+ month AND subscribed, OR manual override — everything

    /// Calculate experience level from user engagement signals.
    static func calculate(
        profileCreatedAt: Date,
        entryCount: Int,
        isPremium: Bool
    ) -> DashboardExperienceLevel {
        let daysSinceCreation = Calendar.current.dateComponents(
            [.day], from: profileCreatedAt, to: .now
        ).day ?? 0

        // Premium subscribers with 1+ month tenure → power
        if isPremium && daysSinceCreation >= 30 {
            return .power
        }

        // 2+ weeks AND 10+ entries → active
        if daysSinceCreation >= 14 && entryCount >= 10 {
            return .active
        }

        // Default: newcomer
        return .newcomer
    }

    // Comparable conformance: rawValue-based comparison
    static func < (lhs: DashboardExperienceLevel, rhs: DashboardExperienceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .newcomer: return "Getting Started"
        case .active: return "Active"
        case .power: return "Power User"
        }
    }
}
