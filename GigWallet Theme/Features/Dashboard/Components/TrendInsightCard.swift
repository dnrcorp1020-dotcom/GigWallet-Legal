import SwiftUI

/// Dashboard card showing real time-series trend analysis from TrendAnalyzer.
///
/// Displays the multi-metric narrative, seasonal patterns, and change points
/// detected via regression, CUSUM, and Welch's t-test. This is real data science,
/// not simple percentage comparisons.
struct TrendInsightCard: View {
    let earningsTrend: TrendAnalyzer.TrendResult?
    let expenseTrend: TrendAnalyzer.TrendResult?
    let multiMetric: TrendAnalyzer.MultiMetricTrend?

    private var hasTrend: Bool {
        earningsTrend != nil || expenseTrend != nil
    }

    private var directionIcon: String {
        guard let trend = earningsTrend else { return "chart.line.flattrend.xyaxis" }
        switch trend.direction {
        case .strongUp: return "arrow.up.right.circle.fill"
        case .moderateUp: return "arrow.up.right"
        case .flat: return "arrow.right"
        case .moderateDown: return "arrow.down.right"
        case .strongDown: return "arrow.down.right.circle.fill"
        }
    }

    private var directionColor: Color {
        guard let trend = earningsTrend else { return BrandColors.textSecondary }
        switch trend.direction {
        case .strongUp, .moderateUp: return BrandColors.success
        case .flat: return BrandColors.primary
        case .moderateDown, .strongDown: return BrandColors.warning
        }
    }

    var body: some View {
        if hasTrend {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                HStack {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.info)

                        Text("Trend Analysis")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }

                    Spacer()

                    if let trend = earningsTrend {
                        HStack(spacing: 3) {
                            Image(systemName: directionIcon)
                                .font(.system(size: 11))
                            Text(trend.direction.rawValue)
                                .font(Typography.caption2)
                        }
                        .foregroundStyle(directionColor)
                    }
                }

                // Earnings trend detail
                if let trend = earningsTrend {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Weekly Change")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(CurrencyFormatter.format(trend.weeklyChange))
                                .font(Typography.moneySmall)
                                .foregroundStyle(trend.weeklyChange >= 0 ? BrandColors.success : BrandColors.destructive)
                        }

                        Spacer()

                        VStack(alignment: .center, spacing: Spacing.xxs) {
                            Text("Fit (R\u{00B2})")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(String(format: "%.0f%%", trend.strength * 100))
                                .font(Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(BrandColors.textPrimary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("Volatility")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                            Text(volatilityLabel(trend.volatility))
                                .font(Typography.caption)
                                .foregroundStyle(volatilityColor(trend.volatility))
                        }
                    }

                    // Seasonal day-of-week indicators
                    if !trend.seasonalFactors.isEmpty {
                        seasonalRow(factors: trend.seasonalFactors)
                    }

                    // Change points
                    if !trend.changePoints.isEmpty {
                        changePointRow(trend.changePoints)
                    }
                }

                // Multi-metric narrative
                if let multi = multiMetric {
                    Divider()
                        .padding(.vertical, Spacing.xxs)

                    Text(multi.narrativeSummary)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(3)

                    // Correlations
                    if !multi.correlations.isEmpty {
                        let significant = multi.correlations.filter { abs($0.correlation) > 0.5 }
                        if !significant.isEmpty {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                    .foregroundStyle(BrandColors.info)

                                Text(significant.map {
                                    "\($0.metric1)/\($0.metric2): r=\(String(format: "%.2f", $0.correlation))"
                                }.joined(separator: " | "))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(BrandColors.textTertiary)
                            }
                        }
                    }
                }
            }
            .gwCard()
        }
    }

    // MARK: - Seasonal Row

    @ViewBuilder
    private func seasonalRow(factors: [Int: Double]) -> some View {
        let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { day in
                let factor = factors[day] ?? 1.0
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(factor >= 1.1 ? BrandColors.success :
                              factor <= 0.9 ? BrandColors.destructive.opacity(0.5) :
                              BrandColors.textTertiary.opacity(0.3))
                        .frame(height: max(CGFloat(factor) * 16, 4))

                    Text(dayLabels[day - 1])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 32)
    }

    // MARK: - Change Points

    @ViewBuilder
    private func changePointRow(_ changePoints: [TrendAnalyzer.ChangePoint]) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(BrandColors.warning)

            Text("\(changePoints.count) shift\(changePoints.count == 1 ? "" : "s") detected")
                .font(Typography.caption2)
                .foregroundStyle(BrandColors.textSecondary)

            if let latest = changePoints.last {
                Text("(\(String(format: "%+.0f%%", latest.percentChange)))")
                    .font(Typography.caption2)
                    .foregroundStyle(latest.percentChange > 0 ? BrandColors.success : BrandColors.destructive)
            }
        }
    }

    // MARK: - Helpers

    private func volatilityLabel(_ cv: Double) -> String {
        if cv > 1.0 { return "High" }
        if cv > 0.5 { return "Moderate" }
        return "Low"
    }

    private func volatilityColor(_ cv: Double) -> Color {
        if cv > 1.0 { return BrandColors.destructive }
        if cv > 0.5 { return BrandColors.warning }
        return BrandColors.success
    }
}
