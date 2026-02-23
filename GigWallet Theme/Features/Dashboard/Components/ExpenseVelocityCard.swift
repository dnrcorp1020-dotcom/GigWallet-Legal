import SwiftUI

/// Shows how fast expenses are growing relative to income — the "burn rate" for gig workers.
/// If expenses are growing faster than income, this is a red flag the user needs to see.
///
/// Also shows the expense-to-income ratio and compares it to the gig worker average (~25-35%).
struct ExpenseVelocityCard: View {
    let monthlyIncome: Double
    let monthlyExpenses: Double
    let priorMonthIncome: Double
    let priorMonthExpenses: Double

    private var expenseRatio: Double {
        guard monthlyIncome > 0 else { return 0 }
        return monthlyExpenses / monthlyIncome
    }

    private var priorExpenseRatio: Double {
        guard priorMonthIncome > 0 else { return 0 }
        return priorMonthExpenses / priorMonthIncome
    }

    private var ratioChange: Double {
        expenseRatio - priorExpenseRatio
    }

    private var isHealthy: Bool {
        expenseRatio < 0.35
    }

    private var statusColor: Color {
        if expenseRatio < 0.25 { return BrandColors.success }
        if expenseRatio < 0.35 { return BrandColors.warning }
        return BrandColors.destructive
    }

    private var statusText: String {
        if expenseRatio < 0.20 { return "Excellent" }
        if expenseRatio < 0.30 { return "Healthy" }
        if expenseRatio < 0.40 { return "Watch it" }
        return "High"
    }

    var body: some View {
        if monthlyIncome > 200 && monthlyExpenses > 0 {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Expense Ratio")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    // Status badge
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
                }

                // Main ratio display
                HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                    Text("\(String(Int(expenseRatio * 100)))%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)

                    Text("of income goes to expenses")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                // Visual bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrandColors.secondaryBackground)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [statusColor.opacity(0.6), statusColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(expenseRatio, 1.0))

                        // Industry average marker
                        Rectangle()
                            .fill(BrandColors.textTertiary)
                            .frame(width: 2, height: 14)
                            .offset(x: geo.size.width * 0.30 - 1)
                    }
                }
                .frame(height: 10)

                // Legend
                HStack {
                    Text("You: \(CurrencyFormatter.format(monthlyExpenses))")
                        .font(Typography.caption2)
                        .foregroundStyle(statusColor)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Rectangle()
                            .fill(BrandColors.textTertiary)
                            .frame(width: 8, height: 2)
                        Text("Avg: 30%")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                // Month-over-month change
                if priorMonthIncome > 200 {
                    HStack(spacing: Spacing.xs) {
                        let arrow = ratioChange > 0.02 ? "arrow.up.right" : (ratioChange < -0.02 ? "arrow.down.right" : "arrow.right")
                        let changeColor = ratioChange > 0.02 ? BrandColors.destructive : (ratioChange < -0.02 ? BrandColors.success : BrandColors.textTertiary)

                        Image(systemName: arrow)
                            .font(.system(size: 10))
                            .foregroundStyle(changeColor)

                        if abs(ratioChange) > 0.01 {
                            Text("\(ratioChange > 0 ? "+" : "")\(String(Int(ratioChange * 100)))% vs last month")
                                .font(Typography.caption2)
                                .foregroundStyle(changeColor)
                        } else {
                            Text("Stable vs last month")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
            }
            .gwCard()
        }
    }
}
