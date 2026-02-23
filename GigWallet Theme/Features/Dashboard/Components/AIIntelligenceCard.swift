import SwiftUI

/// Unified AI Intelligence card — a swipeable horizontal carousel that surfaces the
/// single most important finding from each AI engine.
///
/// Instead of 4 separate cards (InsightsCard, MLForecastCard, AnomalyAlertCard,
/// TrendInsightCard), this single card uses progressive disclosure: show a one-line
/// summary, swipe for next insight. Based on Copilot/YNAB "one insight at a time" pattern.
///
/// Uses TabView with .page style for native iOS swipe behavior.
struct AIIntelligenceCard: View {
    // Rule-based insights (from InsightsEngine)
    let insights: [InsightsEngine.Insight]

    // ML-powered data (from GigIntelligenceCoordinator)
    let report: GigIntelligenceCoordinator.IntelligenceReport?

    @State private var currentPage = 0
    @State private var hasAppeared = false

    // MARK: - Build unified intelligence items

    private var intelligenceItems: [IntelligenceItem] {
        var items: [IntelligenceItem] = []

        // 1. ML Forecast (highest priority if available)
        if let forecast = report?.earningsForecast, forecast.confidence > 0.2 {
            let trendEmoji: String
            let color: Color
            switch forecast.trend {
            case .accelerating:
                trendEmoji = "chart.line.uptrend.xyaxis"
                color = BrandColors.success
            case .decelerating:
                trendEmoji = "chart.line.downtrend.xyaxis"
                color = BrandColors.warning
            case .steady:
                trendEmoji = "chart.line.flattrend.xyaxis"
                color = BrandColors.primary
            case .volatile:
                trendEmoji = "waveform.path.ecg"
                color = BrandColors.info
            case .insufficient:
                trendEmoji = "chart.line.flattrend.xyaxis"
                color = BrandColors.textTertiary
            }

            items.append(IntelligenceItem(
                id: "ml_forecast",
                icon: "brain.head.profile.fill",
                iconColor: BrandColors.primary,
                title: "ML Forecast",
                headline: "\(CurrencyFormatter.format(forecast.predictedNextWeek)) next week",
                detail: "\(forecast.trend.rawValue) trend \u{00B7} \(Int(forecast.confidence * 100))% confidence",
                accentColor: color,
                badge: trendEmoji
            ))
        }

        // 2. Critical anomalies (only if something unusual)
        let criticalAnomalies = report?.anomalies.filter { $0.severity == .critical || $0.severity == .warning } ?? []
        if let topAnomaly = criticalAnomalies.first {
            items.append(IntelligenceItem(
                id: "anomaly_\(topAnomaly.type.rawValue)",
                icon: "exclamationmark.shield.fill",
                iconColor: topAnomaly.severity == .critical ? BrandColors.destructive : BrandColors.warning,
                title: "Anomaly Detected",
                headline: topAnomaly.type.rawValue,
                detail: topAnomaly.description,
                accentColor: topAnomaly.severity == .critical ? BrandColors.destructive : BrandColors.warning,
                badge: "z=\(String(format: "%.1f", abs(topAnomaly.zScore)))"
            ))
        }

        // 3. Trend analysis
        if let trend = report?.earningsTrend {
            let directionIcon: String
            let color: Color
            switch trend.direction {
            case .strongUp:
                directionIcon = "arrow.up.right.circle.fill"
                color = BrandColors.success
            case .moderateUp:
                directionIcon = "arrow.up.right"
                color = BrandColors.success
            case .flat:
                directionIcon = "arrow.right"
                color = BrandColors.primary
            case .moderateDown:
                directionIcon = "arrow.down.right"
                color = BrandColors.warning
            case .strongDown:
                directionIcon = "arrow.down.right.circle.fill"
                color = BrandColors.destructive
            }

            items.append(IntelligenceItem(
                id: "trend_analysis",
                icon: "waveform.path.ecg",
                iconColor: BrandColors.info,
                title: "Trend Analysis",
                headline: "Earnings \(trend.direction.rawValue)",
                detail: "\(CurrencyFormatter.format(trend.weeklyChange))/week \u{00B7} R\u{00B2}=\(String(format: "%.0f%%", trend.strength * 100))",
                accentColor: color,
                badge: directionIcon
            ))
        }

        // 4. Top rule-based insight (always available even without ML data)
        if let topInsight = insights.first {
            items.append(IntelligenceItem(
                id: "insight_\(topInsight.title.hashValue)",
                icon: topInsight.icon,
                iconColor: insightColor(topInsight.accentColor),
                title: "Smart Insight",
                headline: topInsight.title,
                detail: topInsight.message,
                accentColor: insightColor(topInsight.accentColor),
                badge: nil
            ))
        }

        // 5. Narrative summary (if available and we have room)
        if let narrative = report?.narrativeSummary, !narrative.contains("Collecting data"), items.count < 4 {
            items.append(IntelligenceItem(
                id: "narrative_summary",
                icon: "text.bubble.fill",
                iconColor: BrandColors.primary,
                title: "AI Summary",
                headline: "Your Financial Pulse",
                detail: narrative,
                accentColor: BrandColors.primary,
                badge: nil
            ))
        }

        return items
    }

    // MARK: - Body

    var body: some View {
        let items = intelligenceItems
        if !items.isEmpty {
            VStack(spacing: Spacing.sm) {
                // Header
                HStack {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BrandColors.primary)

                        Text("AI Intelligence")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        if items.count > 1 {
                            Text("\u{00B7} \(currentPage + 1)/\(items.count)")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }

                    Spacer()

                    if items.count > 1 {
                        Button {
                            withAnimation(AnimationConstants.spring) {
                                currentPage = (currentPage + 1) % items.count
                            }
                            HapticManager.shared.select()
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(BrandColors.textTertiary.opacity(0.4))
                        }
                    }
                }

                // Swipeable carousel — native iOS page swipe via TabView
                TabView(selection: $currentPage) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemView(item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 56)

                // Custom page dots (we hide the built-in ones above)
                if items.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<items.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? BrandColors.primary : BrandColors.textTertiary.opacity(0.3))
                                .frame(width: index == currentPage ? 6 : 4, height: index == currentPage ? 6 : 4)
                                .animation(AnimationConstants.smooth, value: currentPage)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .gwCard()
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .onAppear {
                withAnimation(AnimationConstants.smooth.delay(0.15)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Item View

    @ViewBuilder
    private func itemView(_ item: IntelligenceItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(item.iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.headline)
                        .font(Typography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    if let badge = item.badge {
                        if badge.starts(with: "z=") {
                            // Z-score badge
                            Text(badge)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(item.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(item.accentColor.opacity(0.12))
                                )
                        } else {
                            // SF Symbol badge
                            Image(systemName: badge)
                                .font(.system(size: 12))
                                .foregroundStyle(item.accentColor)
                        }
                    }
                }

                Text(item.detail)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Types

    private struct IntelligenceItem: Identifiable {
        let id: String
        let icon: String
        let iconColor: Color
        let title: String
        let headline: String
        let detail: String
        let accentColor: Color
        let badge: String?
    }

    private func insightColor(_ colorName: String) -> Color {
        switch colorName {
        case "success": return BrandColors.success
        case "warning": return BrandColors.warning
        case "destructive": return BrandColors.destructive
        case "info": return BrandColors.info
        default: return BrandColors.primary
        }
    }
}
