import SwiftUI

/// Dashboard teaser card for the Financial Planner feature.
/// Shows a summary for premium users or a locked teaser for free users.
struct FinancialPlannerCard: View {
    let isPremium: Bool
    let hasBudgetItems: Bool
    let monthlyIncome: Double
    let monthlyExpenses: Double
    let surplus: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.tap()
            onTap()
        }) {
            VStack(spacing: Spacing.md) {
                // Header
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BrandColors.primary)
                    Text("Financial Planner")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()

                    if !isPremium {
                        GWProBadge()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                if isPremium && hasBudgetItems {
                    // Premium with data — show summary
                    HStack(spacing: 0) {
                        VStack(spacing: Spacing.xxs) {
                            Text("Income")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(CurrencyFormatter.formatCompact(monthlyIncome))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(BrandColors.success)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: Spacing.xxs) {
                            Text("Expenses")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(CurrencyFormatter.formatCompact(monthlyExpenses))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(BrandColors.destructive)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: Spacing.xxs) {
                            Text(surplus >= 0 ? "Surplus" : "Deficit")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(CurrencyFormatter.formatCompact(abs(surplus)))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(surplus >= 0 ? BrandColors.success : BrandColors.destructive)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Mini split bar
                    let total = max(monthlyIncome, monthlyExpenses, 1)
                    let incomeRatio = monthlyIncome / total
                    let expenseRatio = monthlyExpenses / total

                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(BrandColors.success)
                                .frame(width: max(geo.size.width * incomeRatio - 1, 0))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(BrandColors.destructive)
                                .frame(width: max(geo.size.width * expenseRatio - 1, 0))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                } else if isPremium {
                    // Premium but no budget items — prompt to set up
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.primary)
                        Text("Set up your monthly budget to see your full financial picture")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    // Free user — teaser
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.primary)
                        Text("See your full monthly picture — income, expenses, and what's left")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
        }
        .buttonStyle(GWButtonPressStyle())
    }
}
