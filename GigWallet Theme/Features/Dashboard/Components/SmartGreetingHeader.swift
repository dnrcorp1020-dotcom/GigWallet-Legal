import SwiftUI

/// The brand anchor for the Dashboard — combines GigWallet identity with a contextual,
/// personal greeting. This is the first thing users see, and it sets the tone.
///
/// Layout:
///  ┌─────────────────────────────────────┐
///  │ [◼] GigWallet                       │
///  │                                     │
///  │  Good evening, Sarah                │
///  │  $847 earned this week              │
///  └─────────────────────────────────────┘
///
/// The greeting adapts to time, earnings momentum, and goal progress.
struct SmartGreetingHeader: View {
    let userName: String
    let todaysIncome: Double
    let weeklyIncome: Double
    let weeklyGoal: Double
    let lastIncomeDate: Date?
    let topInsight: InsightsEngine.Insight?
    var profileImageURL: String = ""
    var initials: String = "GW"

    @State private var hasAppeared = false

    private var firstName: String {
        let first = userName.components(separatedBy: " ").first ?? userName
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// Whether user has set a name (empty = anonymous/new user).
    private var hasName: Bool { !firstName.isEmpty }

    private var greeting: (title: String, subtitle: String?) {
        let hour = Calendar.current.component(.hour, from: .now)

        // Priority 1: Today's earnings callout (most relevant)
        if todaysIncome > 50 {
            let timeContext: String
            if hour < 12 { timeContext = L10n.greetingStrongMorning }
            else if hour < 17 { timeContext = L10n.greetingGreatAfternoon }
            else { timeContext = L10n.greetingSolidDay }

            let title = hasName ? "\(timeContext), \(firstName)" : timeContext
            return (
                title,
                "\(CurrencyFormatter.format(todaysIncome)) \(L10n.greetingEarnedToday)"
            )
        }

        // Priority 2: Weekly goal progress
        if weeklyGoal > 0 && weeklyIncome > weeklyGoal * 0.5 {
            let progress = Int((weeklyIncome / weeklyGoal) * 100)
            if progress >= 100 {
                let title = hasName
                    ? "greeting.goalCrushed".localized(with: firstName)
                    : L10n.goalReached
                return (
                    title,
                    "\(CurrencyFormatter.format(weeklyIncome)) \(L10n.momentumThisWeek)"
                )
            } else {
                return (
                    timeGreeting(hour: hour),
                    "\(String(progress))% to your \(L10n.weeklyGoal.lowercased())"
                )
            }
        }

        // Priority 3: Time-based contextual greeting
        let title = timeGreeting(hour: hour)

        // Smart subtitle based on context
        var subtitle: String? = nil
        if weeklyIncome > 100 {
            subtitle = "\(CurrencyFormatter.format(weeklyIncome)) \(L10n.greetingEarnedThisWeek)"
        } else if let lastDate = lastIncomeDate {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: .now).day ?? 0
            if daysSince > 3 {
                subtitle = L10n.greetingReadyToGetBack
            }
        }

        return (title, subtitle)
    }

    private func timeGreeting(hour: Int) -> String {
        if hasName {
            switch hour {
            case 5..<12: return "greeting.goodMorning".localized(with: firstName)
            case 12..<17: return "greeting.goodAfternoon".localized(with: firstName)
            case 17..<21: return "greeting.goodEvening".localized(with: firstName)
            default: return "greeting.hey".localized(with: firstName)
            }
        } else {
            switch hour {
            case 5..<12: return "greeting.goodMorningNoName".localized
            case 12..<17: return "greeting.goodAfternoonNoName".localized
            case 17..<21: return "greeting.goodEveningNoName".localized
            default: return "greeting.heyNoName".localized
            }
        }
    }

    var body: some View {
        let greetingData = greeting

        HStack(spacing: Spacing.md) {
            // Profile avatar
            ProfileAvatarView(
                profileImageURL: profileImageURL,
                initials: initials,
                size: 44
            )

            // Greeting text
            VStack(alignment: .leading, spacing: 3) {
                Text(greetingData.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle = greetingData.subtitle {
                    Text(subtitle)
                        .font(Typography.subheadline)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
        .padding(.horizontal, Spacing.xs)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) {
                hasAppeared = true
            }
        }
    }
}
