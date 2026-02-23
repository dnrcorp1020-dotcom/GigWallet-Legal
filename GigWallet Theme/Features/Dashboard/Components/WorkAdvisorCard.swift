import SwiftUI

/// "Should I work right now?" card — the Waze for income.
///
/// Shows projected $/hr net, best platform, time-block analysis, and
/// goal impact. This is the single most behavior-changing feature in the app:
/// it turns GigWallet from a tracker into an advisor.
struct WorkAdvisorCard: View {
    let recommendation: GigDecisionEngine.WorkRecommendation?
    var weatherNote: String? = nil
    var weatherIcon: String = "cloud.sun.fill"
    var topEventName: String? = nil

    @State private var hasAppeared = false

    private var rec: GigDecisionEngine.WorkRecommendation? {
        recommendation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "brain.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandColors.primary)

                    Text("Work Advisor")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()

                if let r = rec {
                    // Status badge
                    HStack(spacing: 3) {
                        Circle()
                            .fill(r.shouldWork ? BrandColors.success : BrandColors.warning)
                            .frame(width: 6, height: 6)

                        Text(r.shouldWork ? "Good Time" : "Wait")
                            .font(Typography.caption2)
                            .foregroundStyle(r.shouldWork ? BrandColors.success : BrandColors.warning)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((r.shouldWork ? BrandColors.success : BrandColors.warning).opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            if let r = rec {
                // Projected rate — the big number
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    if r.projectedHourlyRate > 0 {
                        Text(CurrencyFormatter.format(r.projectedHourlyRate))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(r.shouldWork ? BrandColors.success : BrandColors.warning)

                        Text("/hr net")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                    }

                    Spacer()

                    // Time block indicator
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r.timeBlockAnalysis.currentBlock)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        // Block quality bar
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Double(i) < r.timeBlockAnalysis.currentBlockScore / 20
                                          ? BrandColors.primary
                                          : BrandColors.textTertiary.opacity(0.15))
                                    .frame(width: 8, height: 4)
                            }
                        }
                    }
                }

                // Recommendation text
                Text(r.recommendation)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineLimit(2)

                // Platform ranking (top 2)
                if r.platformRanking.count > 1 {
                    HStack(spacing: Spacing.md) {
                        ForEach(r.platformRanking.prefix(3)) { platform in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(platform.id == r.bestPlatform?.id ? BrandColors.success : BrandColors.textTertiary)
                                    .frame(width: 5, height: 5)

                                Text(platform.platform)
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textSecondary)

                                Text("$\(Int(platform.projectedNetPerHour))/hr")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(platform.id == r.bestPlatform?.id ? BrandColors.success : BrandColors.textTertiary)
                            }
                        }
                        Spacer()
                    }
                }

                // Goal impact
                if let goal = r.goalImpact, goal.weeklyGoal > 0 {
                    Divider()

                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "target")
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColors.textTertiary)

                        Text(goal.onTrackMessage)
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)

                        Spacer()
                    }
                }

                // Weather + Event context for enhanced recommendations
                if weatherNote != nil || topEventName != nil {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        if let weather = weatherNote {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: weatherIcon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(BrandColors.info)

                                Text(weather)
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.info)
                                    .lineLimit(1)

                                Spacer()
                            }
                        }

                        if let event = topEventName {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(BrandColors.warning)

                                Text(event)
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.warning)
                                    .lineLimit(1)

                                Spacer()
                            }
                        }
                    }
                }
            } else {
                // Loading state
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing earning patterns...")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .gwCard()
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .onAppear {
            withAnimation(AnimationConstants.smooth.delay(0.2)) {
                hasAppeared = true
            }
        }
    }
}
