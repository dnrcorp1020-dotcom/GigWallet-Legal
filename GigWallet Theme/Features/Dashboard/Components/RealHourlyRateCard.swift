import SwiftUI

/// THE killer feature — shows gig workers their REAL hourly rate after expenses and taxes.
///
/// Most gig workers think they earn $25-35/hour. When you factor in:
/// - Platform fees (15-30%)
/// - Vehicle expenses (gas, maintenance, depreciation)
/// - Self-employment tax (15.3%)
/// - Federal + state income tax
/// - Phone, insurance, supplies
///
/// Their REAL hourly rate is often $12-18/hour. This truth bomb is what drives
/// subscription conversions — once they see this, they NEED the deduction tracking.
///
/// This card computes real hourly rate per-platform so they can see which
/// platform is actually worth their time.
struct RealHourlyRateCard: View {
    let monthlyGrossIncome: Double
    let monthlyNetIncome: Double
    let monthlyExpenses: Double
    let monthlyMileage: Double
    let estimatedMonthlyHours: Double // Rough estimate: entries × avg trip time
    let effectiveTaxRate: Double
    let platformBreakdown: [PlatformRate]

    @State private var hasAppeared = false
    @State private var showBreakdown = false

    struct PlatformRate: Identifiable {
        let id = UUID()
        let platform: GigPlatformType
        let grossPerHour: Double
        let realPerHour: Double
    }

    /// The real hourly rate after ALL costs
    private var realHourlyRate: Double {
        guard estimatedMonthlyHours > 0 else { return 0 }
        let afterExpenses = monthlyNetIncome - monthlyExpenses
        let afterTax = afterExpenses * (1 - effectiveTaxRate)
        return max(afterTax / estimatedMonthlyHours, 0)
    }

    /// What they THINK they earn (gross / hours)
    private var perceivedRate: Double {
        guard estimatedMonthlyHours > 0 else { return 0 }
        return monthlyGrossIncome / estimatedMonthlyHours
    }

    /// How much lower the real rate is
    private var rateReduction: Double {
        guard perceivedRate > 0 else { return 0 }
        return ((perceivedRate - realHourlyRate) / perceivedRate) * 100
    }

    /// Vehicle cost per mile (industry average for gig workers)
    private var costPerMile: Double {
        // Average: $0.32/mile (gas $0.15 + depreciation $0.12 + maintenance $0.05)
        // IRS rate is $0.70 — the difference is your deduction benefit
        guard monthlyMileage > 0 else { return 0 }
        return 0.32
    }

    var body: some View {
        if estimatedMonthlyHours > 0 && monthlyGrossIncome > 100 {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.info.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrandColors.info)
                    }

                    Text("Your Real Hourly Rate")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()
                }

                // The big reveal — real vs perceived
                HStack(spacing: Spacing.xxl) {
                    // Real rate (the truth)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Actual")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(CurrencyFormatter.format(realHourlyRate))
                                .font(Typography.moneyLarge)
                                .foregroundStyle(realHourlyRate < 15 ? BrandColors.warning : BrandColors.success)
                                .contentTransition(.numericText(value: realHourlyRate))
                            Text("/hr")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                    .opacity(hasAppeared ? 1 : 0)

                    // Arrow showing the drop
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(BrandColors.destructive.opacity(0.5))
                        Text("-\(String(Int(rateReduction)))%")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.destructive)
                    }
                    .opacity(hasAppeared ? 1 : 0)

                    // Perceived rate (what they think)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Before Costs")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(CurrencyFormatter.format(perceivedRate))
                                .font(Typography.moneySmall)
                                .foregroundStyle(BrandColors.textSecondary)
                                .strikethrough(color: BrandColors.destructive.opacity(0.4))
                            Text("/hr")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                    .opacity(hasAppeared ? 1 : 0)
                }

                // Cost breakdown waterfall
                if showBreakdown {
                    VStack(spacing: Spacing.sm) {
                        Divider()

                        WaterfallRow(label: "Gross Earnings", amount: perceivedRate, isPositive: true)
                        WaterfallRow(label: "Platform Fees", amount: -(perceivedRate - (monthlyNetIncome / max(estimatedMonthlyHours, 1))), isPositive: false)
                        WaterfallRow(label: "Expenses", amount: -(monthlyExpenses / max(estimatedMonthlyHours, 1)), isPositive: false)
                        WaterfallRow(label: "Taxes (\(String(Int(effectiveTaxRate * 100)))%)", amount: -((monthlyNetIncome - monthlyExpenses) * effectiveTaxRate / max(estimatedMonthlyHours, 1)), isPositive: false)

                        Divider()

                        HStack {
                            Text("You Keep")
                                .font(Typography.bodyMedium)
                            Spacer()
                            Text("\(CurrencyFormatter.format(realHourlyRate))/hr")
                                .font(Typography.moneySmall)
                                .foregroundStyle(realHourlyRate < 15 ? BrandColors.warning : BrandColors.success)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Platform comparison (if multiple platforms)
                if platformBreakdown.count > 1 && showBreakdown {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("By Platform")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)

                        ForEach(platformBreakdown.sorted(by: { $0.realPerHour > $1.realPerHour })) { platform in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: platform.platform.sfSymbol)
                                    .font(.system(size: 12))
                                    .foregroundStyle(platform.platform.brandColor)
                                    .frame(width: 18)

                                Text(platform.platform.displayName)
                                    .font(Typography.caption)
                                    .frame(width: 72, alignment: .leading)

                                Spacer()

                                Text("\(CurrencyFormatter.format(platform.realPerHour))/hr")
                                    .font(Typography.moneyCaption)
                                    .foregroundStyle(platform.realPerHour < 15 ? BrandColors.warning : BrandColors.success)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Toggle breakdown
                Button {
                    withAnimation(AnimationConstants.spring) {
                        showBreakdown.toggle()
                    }
                    HapticManager.shared.select()
                } label: {
                    HStack {
                        Text(showBreakdown ? "Hide Breakdown" : "See Breakdown")
                            .font(Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(BrandColors.info)
                        Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BrandColors.info)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                    .fill(BrandColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.info.opacity(0.04), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .shadow(color: BrandColors.cardShadow, radius: 8, x: 0, y: 2)
            .onAppear {
                withAnimation(AnimationConstants.counterAnimation.delay(0.2)) {
                    hasAppeared = true
                }
            }
        }
    }
}

struct WaterfallRow: View {
    let label: String
    let amount: Double
    let isPositive: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            Spacer()
            Text("\(isPositive ? "" : "-")\(CurrencyFormatter.format(abs(amount)))/hr")
                .font(Typography.caption)
                .foregroundStyle(isPositive ? BrandColors.textPrimary : BrandColors.destructive.opacity(0.8))
        }
    }
}
