import SwiftUI

struct DeductionSavingsCard: View {
    let currentDeductions: Double
    let yearlyIncome: Double
    var onFindDeductions: () -> Void = {}

    /// Industry average: gig workers can typically deduct 15-25% of gross income
    /// We use a conservative 18% estimate based on IRS data for Schedule C filers
    private var estimatedPotential: Double {
        yearlyIncome * 0.18
    }

    private var missedSavings: Double {
        max(estimatedPotential - currentDeductions, 0)
    }

    private var deductionPercentage: Double {
        guard estimatedPotential > 0 else { return 0 }
        return min(currentDeductions / estimatedPotential, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: missedSavings > 500 ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(missedSavings > 500 ? BrandColors.warning : BrandColors.success)

                Text("Deduction Insights")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()
            }

            if missedSavings > 100 {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("~\(CurrencyFormatter.formatCompact(missedSavings))")
                        .font(Typography.moneyLarge)
                        .foregroundStyle(BrandColors.warning)

                    Text("in potential deductions")
                        .font(Typography.subheadline)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Text("Avg gig worker deducts ~18% of income \u{00B7} Track expenses to claim yours")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            } else if yearlyIncome > 0 {
                Text("You're tracking deductions well! Keep logging expenses to maximize tax savings.")
                    .font(Typography.subheadline)
                    .foregroundStyle(BrandColors.success)
            }

            GWButton("Find My Deductions", icon: "sparkles", style: .small) {
                onFindDeductions()
            }
        }
        .gwCard()
    }
}
