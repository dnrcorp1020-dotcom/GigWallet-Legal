import SwiftUI

/// AI-powered insights card — the centerpiece feature that no spreadsheet can replicate.
/// Shows proactive, context-aware intelligence about the user's gig work.
///
/// This card dynamically shows the most relevant insight: earnings momentum,
/// tax set-aside recommendation, platform efficiency analysis, anomaly alerts, etc.
struct InsightsCard: View {
    let insights: [InsightsEngine.Insight]

    @State private var currentIndex = 0
    @State private var hasAppeared = false

    private var currentInsight: InsightsEngine.Insight? {
        guard !insights.isEmpty else { return nil }
        return insights[min(currentIndex, insights.count - 1)]
    }

    var body: some View {
        if let insight = currentInsight {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header with AI indicator
                HStack(spacing: Spacing.sm) {
                    // Animated AI pulse dot
                    ZStack {
                        Circle()
                            .fill(accentColor(for: insight).opacity(0.2))
                            .frame(width: 32, height: 32)

                        Image(systemName: insight.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accentColor(for: insight))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: Spacing.xs) {
                            Text("Smart Insight")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)

                            if insights.count > 1 {
                                Text("\u{00B7} \(String(currentIndex + 1))/\(String(insights.count))")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                        }

                        Text(insight.title)
                            .font(Typography.headline)
                            .foregroundStyle(BrandColors.textPrimary)
                    }

                    Spacer()

                    if insights.count > 1 {
                        Button {
                            withAnimation(AnimationConstants.spring) {
                                currentIndex = (currentIndex + 1) % insights.count
                            }
                            HapticManager.shared.select()
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(BrandColors.textTertiary.opacity(0.5))
                        }
                    }
                }

                // Insight message
                Text(insight.message)
                    .font(Typography.subheadline)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Optional value callout
                if let value = insight.value, insight.type == .projectedMonthly || insight.type == .taxSetAside {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentColor(for: insight))
                            .frame(width: 3, height: 28)

                        Text(CurrencyFormatter.format(value))
                            .font(Typography.moneyMedium)
                            .foregroundStyle(accentColor(for: insight))
                    }
                }

                // Optional CTA
                if let action = insight.actionLabel {
                    HStack {
                        Spacer()
                        Text(action)
                            .font(Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(accentColor(for: insight))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accentColor(for: insight))
                    }
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
                                    colors: [accentColor(for: insight).opacity(0.06), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                    .stroke(accentColor(for: insight).opacity(0.15), lineWidth: 1)
            )
            .shadow(color: BrandColors.cardShadow, radius: 8, x: 0, y: 2)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .onAppear {
                withAnimation(AnimationConstants.smooth.delay(0.2)) {
                    hasAppeared = true
                }
            }
        }
    }

    private func accentColor(for insight: InsightsEngine.Insight) -> Color {
        switch insight.accentColor {
        case "success": return BrandColors.success
        case "warning": return BrandColors.warning
        case "destructive": return BrandColors.destructive
        case "info": return BrandColors.info
        case "primary": return BrandColors.primary
        default: return BrandColors.primary
        }
    }
}
