import SwiftUI

struct TaxOwedBanner: View {
    let quarterlyTaxDue: Double
    let currentQuarter: TaxQuarter
    let daysUntilDue: Int

    var urgencyColor: Color {
        if daysUntilDue < 14 { return BrandColors.destructive }
        if daysUntilDue < 30 { return BrandColors.warning }
        return BrandColors.secondary
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: daysUntilDue < 14 ? "exclamationmark.triangle.fill" : "building.columns.fill")
                .font(.system(size: 24))
                .foregroundStyle(urgencyColor)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Estimated \(currentQuarter.shortName) Tax")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                Text(CurrencyFormatter.format(quarterlyTaxDue))
                    .font(Typography.moneyMedium)
                    .foregroundStyle(BrandColors.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                GWBadge(
                    daysUntilDue < 14 ? "URGENT" : "\(daysUntilDue) days",
                    color: urgencyColor
                )
                Text(currentQuarter.dueDescription)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .gwCard()
    }
}
