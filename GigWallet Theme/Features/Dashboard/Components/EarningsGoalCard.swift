import SwiftUI

/// Shows weekly earnings progress toward user-set goal
struct EarningsGoalCard: View {
    let currentWeeklyEarnings: Double
    let weeklyGoal: Double
    let onSetGoal: () -> Void

    private var progress: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(currentWeeklyEarnings / weeklyGoal, 1.0)
    }

    private var remaining: Double {
        max(weeklyGoal - currentWeeklyEarnings, 0)
    }

    private var daysLeftInWeek: Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: .now)
        // Sunday = 1, Saturday = 7. Days left including today.
        return 8 - weekday
    }

    var body: some View {
        if weeklyGoal > 0 {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "target")
                        .font(.system(size: 18))
                        .foregroundStyle(BrandColors.primary)

                    Text(L10n.weeklyGoal)
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    Button {
                        onSetGoal()
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BrandColors.primary.opacity(0.12))
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(progress >= 1.0 ? BrandColors.success : BrandColors.primary)
                            .frame(width: geo.size.width * progress, height: 12)
                            .animation(AnimationConstants.smooth, value: progress)
                    }
                }
                .frame(height: 12)

                HStack {
                    if progress >= 1.0 {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BrandColors.success)
                            Text(L10n.goalReached)
                                .font(Typography.bodyMedium)
                                .foregroundStyle(BrandColors.success)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("\(CurrencyFormatter.format(currentWeeklyEarnings)) \(L10n.of) \(CurrencyFormatter.format(weeklyGoal))")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(BrandColors.textPrimary)
                            Text("\(CurrencyFormatter.format(remaining)) \(L10n.toGo) \u{00B7} \("dashboard.daysLeft".localized(with: daysLeftInWeek))")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    }

                    Spacer()

                    Text("\(String(Int(progress * 100)))%")
                        .font(Typography.moneySmall)
                        .foregroundStyle(progress >= 1.0 ? BrandColors.success : BrandColors.primary)
                }
            }
            .gwCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Weekly goal: \(CurrencyFormatter.format(currentWeeklyEarnings)) of \(CurrencyFormatter.format(weeklyGoal)), \(String(Int(progress * 100))) percent complete")
        } else {
            // No goal set — prompt to set one
            Button {
                onSetGoal()
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "target")
                        .font(.system(size: 22))
                        .foregroundStyle(BrandColors.primary)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.setGoal)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.textPrimary)
                        Text(L10n.setGoalSubtitle)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .padding(Spacing.lg)
                .background(BrandColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            }
        }
    }
}
