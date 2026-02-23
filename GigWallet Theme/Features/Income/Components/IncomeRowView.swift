import SwiftUI

struct IncomeRowView: View {
    let entry: IncomeEntry

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Platform icon
            Image(systemName: entry.platform.sfSymbol)
                .font(.system(size: 18))
                .foregroundStyle(entry.platform.brandColor)
                .frame(width: 36, height: 36)
                .background(entry.platform.brandColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.platform.displayName)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.textPrimary)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: entry.entryMethod.sfSymbol)
                        .font(.system(size: 10))
                    Text(entry.entryMethod.rawValue)
                        .font(Typography.caption2)
                }
                .foregroundStyle(BrandColors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(CurrencyFormatter.format(entry.netAmount))
                    .font(Typography.moneySmall)
                    .foregroundStyle(BrandColors.success)

                if entry.tips > 0 {
                    Text("incl. \(CurrencyFormatter.format(entry.tips)) tips")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
