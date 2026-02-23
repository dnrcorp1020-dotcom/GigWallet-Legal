import SwiftUI

struct QuarterlyEstimateCard: View {
    let quarter: TaxQuarter
    let estimatedPayment: Double
    let isCurrent: Bool
    let daysUntilDue: Int

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Quarter badge
            VStack(spacing: Spacing.xxs) {
                Text(quarter.shortName)
                    .font(Typography.headline)
                    .foregroundStyle(isCurrent ? .white : BrandColors.primary)

                Text(quarter.months)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isCurrent ? .white.opacity(0.7) : BrandColors.textTertiary)
            }
            .frame(width: 60, height: 54)
            .background(isCurrent ? BrandColors.primary : BrandColors.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(CurrencyFormatter.format(estimatedPayment))
                    .font(Typography.moneySmall)
                    .foregroundStyle(BrandColors.textPrimary)

                Text(quarter.dueDescription)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Spacer()

            if isCurrent {
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    GWBadge(daysUntilDue < 30 ? "Due Soon" : "Current", color: daysUntilDue < 30 ? BrandColors.warning : BrandColors.primary)
                    Text("\(String(daysUntilDue)) days left")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                    if estimatedPayment > 0, let irsURL = URL(string: "https://directpay.irs.gov") {
                        Link(destination: irsURL) {
                            Text("Pay IRS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 3)
                                .background(BrandColors.success)
                                .clipShape(Capsule())
                        }
                    }
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .padding(Spacing.md)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                .stroke(isCurrent ? BrandColors.primary.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}
