import SwiftUI

/// Compares platform-level efficiency so gig workers can see which platform
/// gives them the best return after fees. Only renders when at least two
/// platforms have data — a single platform has nothing to compare against.
struct PlatformEfficiencyCard: View {
    let platforms: [PlatformMetric]

    @State private var hasAppeared = false

    // MARK: - Derived Data

    private var sortedPlatforms: [PlatformMetric] {
        platforms.sorted { $0.totalEarnings > $1.totalEarnings }
    }

    private var bestPlatform: PlatformMetric? {
        platforms.max(by: { $0.netPercentage < $1.netPercentage })
    }

    private var worstPlatform: PlatformMetric? {
        platforms.min(by: { $0.netPercentage < $1.netPercentage })
    }

    private var insightText: String? {
        guard let best = bestPlatform, let worst = worstPlatform,
              best.id != worst.id else { return nil }
        let difference = Int(best.netPercentage - worst.netPercentage)
        guard difference > 0 else { return nil }
        return "\(best.platformName) keeps you \(difference)% more per gig"
    }

    // MARK: - Body

    var body: some View {
        if platforms.count >= 2 {
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerRow

                ForEach(Array(sortedPlatforms.enumerated()), id: \.element.id) { index, platform in
                    platformRow(platform, index: index)
                }

                if let insight = insightText {
                    insightBanner(insight)
                }
            }
            .gwCard()
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        Text("Platform Efficiency")
            .font(Typography.headline)
            .foregroundStyle(BrandColors.textPrimary)
    }

    // MARK: - Platform Row

    private func platformRow(_ platform: PlatformMetric, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Top line: icon, name, earnings, kept badge
            HStack(spacing: Spacing.sm) {
                Image(systemName: platform.platformIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(platform.platformColor)
                    .frame(width: 20)

                Text(platform.platformName)
                    .font(Typography.subheadline)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                Text(CurrencyFormatter.format(platform.totalEarnings))
                    .font(Typography.moneyCaption)
                    .foregroundStyle(BrandColors.textPrimary)

                keptBadge(platform.netPercentage)
            }

            // Net percentage bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track (unfilled = fees)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(platform.platformColor.opacity(0.12))

                    // Fill (net kept)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    platform.platformColor.opacity(0.7),
                                    platform.platformColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: hasAppeared
                                ? max(geo.size.width * (platform.netPercentage / 100.0), 4)
                                : 0
                        )
                }
            }
            .frame(height: 10)

            // Detail line below bar
            HStack(spacing: 0) {
                Text("Avg \(CurrencyFormatter.format(platform.avgPerEntry)) per gig")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)

                Text(" \u{00B7} ")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)

                Text("\(formattedPercent(platform.feePercentage))% in fees")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
    }

    // MARK: - Kept Badge

    private func keptBadge(_ netPct: Double) -> some View {
        let badgeColor = badgeColor(for: netPct)
        return Text("\(formattedPercent(netPct))% kept")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Insight Banner

    private func insightBanner(_ text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BrandColors.primary)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColors.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
    }

    // MARK: - Helpers

    private func badgeColor(for netPct: Double) -> Color {
        if netPct >= 85 { return BrandColors.success }
        if netPct >= 75 { return BrandColors.warning }
        return BrandColors.destructive
    }

    private func formattedPercent(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Platform Metric Model

struct PlatformMetric: Identifiable {
    let id = UUID()
    let platformName: String
    let platformColor: Color
    let platformIcon: String
    let totalEarnings: Double
    let entryCount: Int
    let avgPerEntry: Double
    let feePercentage: Double
    let netPercentage: Double
}
