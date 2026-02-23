import SwiftUI

struct EarningsSummaryCard: View {
    let monthlyEarnings: Double
    let monthlyExpenses: Double
    let todaysEarnings: Double
    let effectiveTaxRate: Double

    @State private var hasAppeared = false

    private var netProfit: Double {
        monthlyEarnings - monthlyExpenses
    }

    /// How much of today's earnings go to taxes — makes tax real and visceral
    private var todaysTaxBite: Double {
        todaysEarnings * effectiveTaxRate
    }

    /// What they actually keep from today
    private var todaysKeep: Double {
        todaysEarnings - todaysTaxBite
    }

    private var isEmpty: Bool {
        monthlyEarnings == 0 && todaysEarnings == 0
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if isEmpty {
                // Empty state — friendly guidance for new users
                VStack(spacing: Spacing.md) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.5))

                    Text(L10n.startTracking)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)

                    Text(L10n.startTrackingSubtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
            } else {
                // Hero row — monthly earnings
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.thisMonth)
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(CurrencyFormatter.format(hasAppeared ? monthlyEarnings : 0))
                            .font(Typography.moneyHero)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: monthlyEarnings))
                    }
                    Spacer()

                    // Profit margin indicator
                    if monthlyEarnings > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            let margin = netProfit / monthlyEarnings * 100
                            Text("\(String(Int(margin)))%")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                            Text(L10n.profitMargin)
                                .font(Typography.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 1)

                // Bottom stats row
                HStack(spacing: 0) {
                    // Expenses
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.expenses)
                            .font(Typography.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(CurrencyFormatter.format(monthlyExpenses))
                            .font(Typography.moneySmall)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Net Profit
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.netProfit)
                            .font(Typography.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(CurrencyFormatter.format(netProfit))
                            .font(Typography.moneySmall)
                            .foregroundStyle(netProfit >= 0 ? .white : BrandColors.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Today's keep (the "aha moment")
                    if todaysEarnings > 10 {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text(L10n.todayYouKeep)
                                .font(Typography.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(CurrencyFormatter.format(todaysKeep))
                                .font(Typography.moneySmall)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .background(
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: [BrandColors.primary, BrandColors.primaryDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle radial highlight for depth
                RadialGradient(
                    colors: [BrandColors.primaryLight.opacity(0.3), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 300
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusXl))
        .shadow(color: BrandColors.primary.opacity(0.3), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monthly earnings: \(CurrencyFormatter.format(monthlyEarnings)), expenses: \(CurrencyFormatter.format(monthlyExpenses)), net profit: \(CurrencyFormatter.format(netProfit))")
        .onAppear {
            withAnimation(AnimationConstants.counterAnimation) {
                hasAppeared = true
            }
        }
    }
}
