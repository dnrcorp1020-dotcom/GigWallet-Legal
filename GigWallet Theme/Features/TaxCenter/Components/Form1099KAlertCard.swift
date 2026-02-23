import SwiftUI

struct Form1099KAlertCard: View {
    let grossIncome: Double
    let threshold: Double
    let entryCount: Int

    private var percentToThreshold: Double {
        min(grossIncome / threshold, 1.0)
    }

    private var willReceive: Bool {
        grossIncome >= threshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: willReceive ? "checkmark.seal.fill" : "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(willReceive ? BrandColors.warning : BrandColors.info)

                Text("1099-K Status")
                    .font(Typography.headline)

                Spacer()

                if willReceive {
                    GWBadge("Will Receive", color: BrandColors.warning)
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: Spacing.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrandColors.primary.opacity(0.15))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(willReceive ? BrandColors.warning : BrandColors.primary)
                            .frame(width: geo.size.width * percentToThreshold, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(CurrencyFormatter.format(grossIncome))
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    Text("Threshold: \(CurrencyFormatter.format(threshold))")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }

            if willReceive {
                Text("You'll likely receive a 1099-K. Make sure all income is properly reported to avoid IRS discrepancies.")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineSpacing(2)
            }
        }
        .gwCard()
    }
}
