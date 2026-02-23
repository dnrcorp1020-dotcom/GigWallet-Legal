import SwiftUI

/// Displays income momentum — whether the user is earning above or below their recent averages.
/// Shows today vs. 30-day daily average, week-over-week change, and consecutive earning streak.
///
/// Layout:
///  ┌────────────────────────────────────┐
///  │  Income Momentum          ▲ +15%  │
///  │                                    │
///  │  [$187/day avg]  →  [$223 today]  │
///  │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░              │
///  │                                    │
///  │  ↑ $847 this week (+15% vs last)  │
///  │  3 day earning streak             │
///  └────────────────────────────────────┘
struct IncomeMomentumCard: View {
    let thisWeekIncome: Double
    let lastWeekIncome: Double
    let weekOverWeekChange: Double
    let currentStreak: Int
    let avgDailyIncome: Double
    let todaysIncome: Double

    @State private var hasAppeared = false

    // MARK: - Computed Properties

    /// Today's income as a proportion of the 30-day daily average, capped at 2.0 (200%).
    private var momentumRatio: Double {
        guard avgDailyIncome > 0 else { return 0 }
        return min(todaysIncome / avgDailyIncome, 2.0)
    }

    /// Whether today's income exceeds the rolling average.
    private var isAboveAverage: Bool {
        todaysIncome >= avgDailyIncome
    }

    /// Whether this week's income is up vs. last week.
    private var isWeekPositive: Bool {
        weekOverWeekChange >= 0
    }

    /// Week-over-week percentage formatted as a whole number.
    private var weekChangePercent: Int {
        Int((weekOverWeekChange * 100).rounded())
    }

    /// Color for the week-over-week indicator.
    private var weekChangeColor: Color {
        isWeekPositive ? BrandColors.success : BrandColors.destructive
    }

    /// Color for the momentum bar.
    private var momentumBarColor: Color {
        isAboveAverage ? BrandColors.success : BrandColors.primary
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            headerRow

            if thisWeekIncome > 0 || avgDailyIncome > 0 {
                // Has some income data — show full momentum view
                todayVsAverageRow
                momentumBar
                weekOverWeekRow

                if currentStreak > 0 {
                    streakRow
                }
            } else {
                // No income yet — motivational nudge
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.primary)

                    Text(L10n.momentumLogFirst)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .gwCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Income momentum: \(CurrencyFormatter.format(todaysIncome)) today, \(CurrencyFormatter.format(thisWeekIncome)) this week, \(currentStreak) day earning streak")
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text(L10n.momentumTitle)
                .font(Typography.headline)
                .foregroundStyle(BrandColors.textPrimary)

            Spacer()

            weekChangeBadge
        }
    }

    private var weekChangeBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: isWeekPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))

            Text("\(isWeekPositive ? "+" : "")\(weekChangePercent)%")
                .font(Typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(weekChangeColor)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(weekChangeColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
    }

    // MARK: - Today vs Average

    private var todayVsAverageRow: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(L10n.momentumThirtyDayAvg)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)

                Text("\(CurrencyFormatter.format(avgDailyIncome))\(L10n.momentumPerDay)")
                    .font(Typography.moneySmall)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandColors.textTertiary)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(L10n.momentumToday)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)

                Text(CurrencyFormatter.format(todaysIncome))
                    .font(Typography.moneySmall)
                    .foregroundStyle(isAboveAverage ? BrandColors.success : BrandColors.primary)
            }

            Spacer()
        }
    }

    // MARK: - Momentum Bar

    private var momentumBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(momentumBarColor.opacity(0.10))
                    .frame(height: 8)

                // Average marker at the 50% point (since bar caps at 200% of avg)
                Rectangle()
                    .fill(BrandColors.textTertiary.opacity(0.3))
                    .frame(width: 1, height: 14)
                    .offset(x: geo.size.width * 0.5)

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [momentumBarColor.opacity(0.6), momentumBarColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: hasAppeared ? max(geo.size.width * (momentumRatio / 2.0), 4) : 0,
                        height: 8
                    )
            }
        }
        .frame(height: 14)
    }

    // MARK: - Week Over Week

    private var weekOverWeekRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: isWeekPositive ? "arrow.up" : "arrow.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(weekChangeColor)

            Text("\(CurrencyFormatter.format(thisWeekIncome)) \(L10n.momentumThisWeek) (\(isWeekPositive ? "+" : "")\(weekChangePercent)% \("momentum.vsLast".localized))")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    // MARK: - Streak

    private var streakRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 11))
                .foregroundStyle(BrandColors.textTertiary)

            Text("momentum.dayStreak".localized(with: currentStreak))
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textTertiary)
        }
    }
}
