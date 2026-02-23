import SwiftUI

/// Shows today's earnings split into estimated keep vs estimated taxes.
/// This makes tax obligation visceral and real — not an abstract number you see in April.
/// All amounts are estimates based on self-employment income only.
/// Actual tax liability depends on total household income, deductions, credits, and filing status.
struct TaxBiteCard: View {
    let todaysGross: Double
    let effectiveTaxRate: Double
    let yearlyTaxOwed: Double
    let yearlyTaxPaid: Double  // Estimated quarterly payments already made

    @State private var hasAppeared = false

    private var todaysTax: Double {
        todaysGross * effectiveTaxRate
    }

    private var todaysKeep: Double {
        todaysGross - todaysTax
    }

    /// Visual split percentage (how much of the bar is "keep" vs "tax")
    private var keepPercent: Double {
        guard todaysGross > 0 else { return 1.0 }
        return max(todaysKeep / todaysGross, 0)
    }

    /// Running tax balance (how much they still owe)
    private var taxBalance: Double {
        max(yearlyTaxOwed - yearlyTaxPaid, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(L10n.taxBiteTitle)
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                if todaysGross > 0 {
                    Text("est. " + CurrencyFormatter.format(todaysGross))
                        .font(Typography.moneyCaption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            if todaysGross > 1 {
                // Visual split bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        // You keep
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.success, BrandColors.success.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: hasAppeared ? max(geo.size.width * keepPercent - 1, 0) : 0)
                            .overlay(
                                Text(L10n.taxBiteYouKeep)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .opacity(keepPercent > 0.3 ? 1 : 0)
                            )

                        // Tax portion
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.destructive.opacity(0.7), BrandColors.destructive.opacity(0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: hasAppeared ? max(geo.size.width * (1 - keepPercent) - 1, 0) : 0)
                            .overlay(
                                Text(L10n.taxBiteTax)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .opacity((1 - keepPercent) > 0.15 ? 1 : 0)
                            )
                    }
                }
                .frame(height: 28)

                // Amount labels
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("~" + CurrencyFormatter.format(todaysKeep))
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.success)
                        Text(L10n.taxBiteEstInPocket)
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("~" + CurrencyFormatter.format(todaysTax))
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.destructive)
                        Text("taxBite.estTax".localized(with: String(Int(effectiveTaxRate * 100))))
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            } else {
                // No income today — motivational prompt
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BrandColors.primary.opacity(0.6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.taxBiteNoEarnings)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text("taxBite.estTaxRate".localized(with: String(Int(effectiveTaxRate * 100))))
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }

            // Running tax balance (always show when meaningful)
            if taxBalance > 0 {
                Divider()

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColors.textTertiary)

                    Text("taxBite.estBalance".localized(with: CurrencyFormatter.format(taxBalance)))
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)

                    Spacer()
                }
            }

            // Disclaimer
            Text(L10n.taxBiteDisclaimer)
                .font(.system(size: 11))
                .foregroundStyle(BrandColors.textTertiary.opacity(0.6))
        }
        .gwCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(todaysGross > 0
            ? "Today's tax bite: you keep \(CurrencyFormatter.format(todaysKeep)), estimated tax \(CurrencyFormatter.format(todaysTax))"
            : "No earnings logged today, estimated tax rate \(String(Int(effectiveTaxRate * 100))) percent")
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
                hasAppeared = true
            }
        }
    }
}
