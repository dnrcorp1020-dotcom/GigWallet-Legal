import SwiftUI

/// Compact dashboard card showing a countdown to the next quarterly estimated tax deadline.
/// Critical for 1099/independent contractors who must pay estimated taxes quarterly.
/// All amounts shown are estimates based on self-employment income only.
struct TaxCountdownCard: View {
    let daysUntilDue: Int
    let quarterName: String
    let estimatedPayment: Double
    let amountPaid: Double
    let dueDate: String

    @State private var hasAppeared = false

    // MARK: - Computed Properties

    private var remaining: Double {
        max(estimatedPayment - amountPaid, 0)
    }

    private var progress: Double {
        guard estimatedPayment > 0 else { return 0 }
        return min(amountPaid / estimatedPayment, 1.0)
    }

    private var percentPaid: Int {
        Int(progress * 100)
    }

    private var isFullyPaid: Bool {
        amountPaid >= estimatedPayment
    }

    private var urgencyColor: Color {
        if isFullyPaid { return BrandColors.success }
        switch daysUntilDue {
        case ..<14: return BrandColors.destructive
        case 14..<30: return BrandColors.warning
        case 30..<61: return BrandColors.primary
        default: return BrandColors.success
        }
    }

    // MARK: - Body

    var body: some View {
        if daysUntilDue > 0 {
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerRow
                if estimatedPayment < 1 {
                    // No estimated tax yet — still show deadline awareness
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.textTertiary)

                        Text(L10n.taxCountdownLogMore)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                } else if isFullyPaid {
                    paidInFullRow
                } else {
                    amountsRow
                    progressBar
                    remainingRow
                }

                // Disclaimer for all states
                Text(L10n.taxCountdownDisclaimer)
                    .font(.system(size: 11))
                    .foregroundStyle(BrandColors.textTertiary.opacity(0.6))
            }
            .gwCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tax deadline: \(daysUntilDue) days until \(quarterName) payment, \(CurrencyFormatter.format(remaining)) remaining")
            .onAppear {
                withAnimation(AnimationConstants.smooth) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 16))
                    .foregroundStyle(urgencyColor)

                Text("tax.daysUntilDue".localized(with: daysUntilDue))
                    .font(Typography.moneySmall)
                    .foregroundStyle(urgencyColor)
            }

            Spacer()

            Text("\(quarterName) due \(dueDate)")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    private var paidInFullRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(BrandColors.success)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(L10n.taxCountdownPaidInFull)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.success)

                Text("taxCountdown.paidToward".localized(with: CurrencyFormatter.format(amountPaid), quarterName))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Spacer()
        }
    }

    private var amountsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(L10n.taxCountdownEstOwed)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
                Text(CurrencyFormatter.format(estimatedPayment))
                    .font(Typography.moneySmall)
                    .foregroundStyle(BrandColors.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(L10n.taxCountdownPaid)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
                Text(CurrencyFormatter.format(amountPaid))
                    .font(Typography.moneySmall)
                    .foregroundStyle(BrandColors.success)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: Spacing.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(urgencyColor.opacity(0.12))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(urgencyColor)
                        .frame(width: geo.size.width * (hasAppeared ? progress : 0), height: 8)
                        .animation(AnimationConstants.smooth, value: hasAppeared)
                }
            }
            .frame(height: 8)

            Text("taxCountdown.percentPaid".localized(with: percentPaid))
                .font(Typography.caption2)
                .foregroundStyle(BrandColors.textSecondary)
                .fixedSize()
        }
    }

    private var remainingRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundStyle(BrandColors.warning)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("taxCountdown.remaining".localized(with: CurrencyFormatter.format(remaining)))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textPrimary)

                if let irsURL = URL(string: "https://directpay.irs.gov") {
                    Link(destination: irsURL) {
                        HStack(spacing: Spacing.xs) {
                            Text(L10n.taxCountdownPayNow)
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.primary)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundStyle(BrandColors.primary)
                            Text("irs.gov/directpay")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Urgent - 12 days") {
    TaxCountdownCard(
        daysUntilDue: 12,
        quarterName: "Q1 2026",
        estimatedPayment: 1847,
        amountPaid: 500,
        dueDate: "April 15"
    )
    .padding()
}

#Preview("Moderate - 45 days") {
    TaxCountdownCard(
        daysUntilDue: 45,
        quarterName: "Q2 2026",
        estimatedPayment: 2100,
        amountPaid: 1050,
        dueDate: "June 16"
    )
    .padding()
}

#Preview("Fully Paid") {
    TaxCountdownCard(
        daysUntilDue: 30,
        quarterName: "Q1 2026",
        estimatedPayment: 1847,
        amountPaid: 1847,
        dueDate: "April 15"
    )
    .padding()
}
