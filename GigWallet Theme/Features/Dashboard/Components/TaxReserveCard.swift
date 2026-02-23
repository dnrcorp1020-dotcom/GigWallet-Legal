import SwiftUI

/// Virtual "Tax Vault" — shows how much of their money belongs to the IRS.
///
/// This is the precursor to a real savings account integration. For now, it acts
/// as a psychological nudge: every time they see their balance, they see the IRS's
/// portion separated out. This prevents the #1 gig worker mistake: spending tax money.
///
/// Design: A compact card with two amounts side-by-side:
///   "Yours: $3,421"  |  "IRS Reserve: $1,847"
///   with a visual divider and progress toward quarterly payment
struct TaxReserveCard: View {
    let yearlyNetIncome: Double
    let yearlyTaxEstimate: Double
    let yearlyTaxPaid: Double
    let effectiveTaxRate: Double
    var vaultBalance: Double = 0
    var onTap: (() -> Void)? = nil

    @State private var hasAppeared = false

    /// How much they should have set aside but haven't paid yet
    private var taxReserve: Double {
        max(yearlyTaxEstimate - yearlyTaxPaid, 0)
    }

    /// What's truly "theirs" after tax
    private var theirMoney: Double {
        max(yearlyNetIncome - taxReserve, 0)
    }

    /// How much of each dollar earned goes to reserve
    private var reservePercent: Double {
        guard yearlyNetIncome > 0 else { return 0 }
        return min(taxReserve / yearlyNetIncome, 1)
    }

    var body: some View {
        if yearlyNetIncome > 500 {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Money Split")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    // Rate badge
                    Text("\(String(Int(effectiveTaxRate * 100)))% tax rate")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BrandColors.textTertiary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 3)
                        .background(BrandColors.secondaryBackground)
                        .clipShape(Capsule())
                }

                // Two-column split
                HStack(spacing: 0) {
                    // Your money
                    VStack(spacing: Spacing.xxs) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.success)

                        Text(CurrencyFormatter.format(theirMoney))
                            .font(Typography.moneySmall)
                            .foregroundStyle(BrandColors.success)

                        Text("Yours to keep")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    // Divider
                    Rectangle()
                        .fill(BrandColors.textTertiary.opacity(0.2))
                        .frame(width: 1, height: 50)

                    // Tax reserve
                    VStack(spacing: Spacing.xxs) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.destructive.opacity(0.7))

                        Text(CurrencyFormatter.format(taxReserve))
                            .font(Typography.moneySmall)
                            .foregroundStyle(BrandColors.destructive.opacity(0.8))

                        Text("Tax reserve")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Visual bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.success, BrandColors.success.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: hasAppeared ? max(geo.size.width * (1 - reservePercent) - 1, 6) : 0)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrandColors.destructive.opacity(0.3))
                            .frame(width: hasAppeared ? max(geo.size.width * reservePercent - 1, 6) : 0)
                    }
                }
                .frame(height: 8)

                // Vault balance (if user has set aside money)
                if vaultBalance > 0 {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.primary)
                        Text("Tax Vault: \(CurrencyFormatter.format(vaultBalance))")
                            .font(Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(BrandColors.primary)
                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(BrandColors.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                }

                // Smart nudge
                if yearlyTaxPaid > 0 {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColors.success)
                        Text("You've paid \(CurrencyFormatter.format(yearlyTaxPaid)) toward taxes this year")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                } else if taxReserve > 500 {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColors.warning)
                        Text("Set aside \(CurrencyFormatter.format(taxReserve)) — don't spend the IRS's money")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.warning)
                    }
                }

                // Tap hint
                if onTap != nil {
                    HStack {
                        Spacer()
                        Text("Tap to manage \u{203A}")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }
            .gwCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tax reserve: you keep \(CurrencyFormatter.format(theirMoney)), tax reserve \(CurrencyFormatter.format(taxReserve)). Vault balance: \(CurrencyFormatter.format(vaultBalance))")
            .onTapGesture {
                if let onTap {
                    HapticManager.shared.tap()
                    onTap()
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                    hasAppeared = true
                }
            }
        }
    }
}
