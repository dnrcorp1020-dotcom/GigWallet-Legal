import SwiftUI

struct ExpenseRowView: View {
    let expense: ExpenseEntry

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: expense.category.sfSymbol)
                .font(.system(size: 18))
                .foregroundStyle(expense.category.color)
                .frame(width: 36, height: 36)
                .background(expense.category.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.textPrimary)

                HStack(spacing: Spacing.xs) {
                    Text(expense.category.rawValue)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)

                    if expense.isDeductible {
                        GWBadge(
                            expense.deductionPercentage < 100 ? "\(Int(expense.deductionPercentage))%" : "Deductible",
                            color: BrandColors.success
                        )
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(CurrencyFormatter.format(expense.amount))
                    .font(Typography.moneySmall)
                    .foregroundStyle(BrandColors.textPrimary)

                Text(expense.expenseDate.shortDate)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
