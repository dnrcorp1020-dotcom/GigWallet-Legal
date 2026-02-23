import SwiftUI

struct PlatformBreakdownCard: View {
    let entries: [IncomeEntry]

    @State private var hasAppeared = false

    private var platformTotals: [(platform: GigPlatformType, total: Double)] {
        let startOfMonth = Date.now.startOfMonth
        let monthEntries = entries.filter { $0.entryDate >= startOfMonth }

        var totals: [GigPlatformType: Double] = [:]
        for entry in monthEntries {
            totals[entry.platform, default: 0] += entry.netAmount
        }

        return totals.map { (platform: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var maxTotal: Double {
        platformTotals.first?.total ?? 1
    }

    private var totalIncome: Double {
        platformTotals.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Platform Breakdown")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                if !platformTotals.isEmpty {
                    Text(CurrencyFormatter.format(totalIncome))
                        .font(Typography.moneyCaption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            if platformTotals.isEmpty {
                Text("No income recorded this month")
                    .font(Typography.subheadline)
                    .foregroundStyle(BrandColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
            } else {
                ForEach(Array(platformTotals.enumerated()), id: \.element.platform) { index, item in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: item.platform.sfSymbol)
                            .font(.system(size: 14))
                            .foregroundStyle(item.platform.brandColor)
                            .frame(width: 22)

                        Text(item.platform.displayName)
                            .font(Typography.subheadline)
                            .frame(width: 76, alignment: .leading)

                        // Animated bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Track
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(item.platform.brandColor.opacity(0.1))

                                // Fill — animates width on appear
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(
                                        LinearGradient(
                                            colors: [item.platform.brandColor.opacity(0.8), item.platform.brandColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: hasAppeared ? max(geo.size.width * (item.total / maxTotal), 6) : 0)
                            }
                        }
                        .frame(height: 22)

                        // Percentage + amount
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(CurrencyFormatter.format(item.total))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(BrandColors.textPrimary)
                            if totalIncome > 0 {
                                Text("\(String(Int(item.total / totalIncome * 100)))%")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                        }
                        .frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
        .gwCard()
        .onAppear {
            // Staggered bar animation
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                hasAppeared = true
            }
        }
    }
}
