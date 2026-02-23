import SwiftUI

/// Dashboard card that displays ML-powered earnings and expense forecasts.
///
/// Unlike the old linear projection, this uses real regression + EMA + seasonal
/// decomposition from GigMLEngine. Shows predicted next week and month with
/// confidence intervals and trend classification.
struct MLForecastCard: View {
    let earningsForecast: GigMLEngine.EarningsForecast?
    let expenseForecast: GigMLEngine.ExpenseForecast?

    @State private var hasAppeared = false

    private var hasForecast: Bool {
        earningsForecast != nil || expenseForecast != nil
    }

    private var trendIcon: String {
        guard let forecast = earningsForecast else { return "chart.line.flattrend.xyaxis" }
        switch forecast.trend {
        case .accelerating: return "chart.line.uptrend.xyaxis"
        case .decelerating: return "chart.line.downtrend.xyaxis"
        case .steady: return "chart.line.flattrend.xyaxis"
        case .volatile: return "waveform.path.ecg"
        case .insufficient: return "chart.line.flattrend.xyaxis"
        }
    }

    private var trendColor: Color {
        guard let forecast = earningsForecast else { return BrandColors.textSecondary }
        switch forecast.trend {
        case .accelerating: return BrandColors.success
        case .decelerating: return BrandColors.warning
        case .steady: return BrandColors.primary
        case .volatile: return BrandColors.info
        case .insufficient: return BrandColors.textTertiary
        }
    }

    var body: some View {
        if hasForecast {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                HStack {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.primary)

                        Text("ML Forecast")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }

                    Spacer()

                    if let forecast = earningsForecast {
                        HStack(spacing: 3) {
                            Image(systemName: trendIcon)
                                .font(.system(size: 11))
                            Text(forecast.trend.rawValue)
                                .font(Typography.caption2)
                        }
                        .foregroundStyle(trendColor)
                    }
                }

                // Earnings forecast
                if let forecast = earningsForecast {
                    HStack(alignment: .top) {
                        // Next week prediction
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Next 7 Days")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(CurrencyFormatter.format(forecast.predictedNextWeek))
                                .font(Typography.moneySmall)
                                .foregroundStyle(BrandColors.textPrimary)
                        }

                        Spacer()

                        // Next month prediction
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("Next 30 Days")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(CurrencyFormatter.format(forecast.predictedNextMonth))
                                .font(Typography.moneySmall)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                    }

                    // Confidence bar
                    HStack(spacing: Spacing.sm) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(BrandColors.primary.opacity(0.12))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(BrandColors.primary)
                                    .frame(width: geo.size.width * (hasAppeared ? forecast.confidence : 0), height: 6)
                                    .animation(AnimationConstants.smooth, value: hasAppeared)
                            }
                        }
                        .frame(height: 6)

                        Text("\(Int(forecast.confidence * 100))% confident")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                            .fixedSize()
                    }

                    // Basis
                    Text(forecast.forecastBasis)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                // Expense forecast
                if let expenses = expenseForecast {
                    Divider()
                        .padding(.vertical, Spacing.xxs)

                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Projected Expenses")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(CurrencyFormatter.format(expenses.predictedMonthlyExpenses))
                                .font(Typography.moneySmall)
                                .foregroundStyle(BrandColors.destructive)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("Burn Rate")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text("\(CurrencyFormatter.format(expenses.burnRatePerDay))/day")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                    }
                }
            }
            .gwCard()
            .onAppear {
                withAnimation(AnimationConstants.smooth) {
                    hasAppeared = true
                }
            }
        }
    }
}
