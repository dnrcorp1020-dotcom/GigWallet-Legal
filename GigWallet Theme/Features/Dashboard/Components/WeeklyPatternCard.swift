import SwiftUI

/// Shows the user's earning pattern by day of week — which days make the most money.
/// This turns their own data into an actionable work schedule.
///
/// Layout:
///  ┌────────────────────────────────────┐
///  │  Your Best Days                    │
///  │  ■■■■■■■■■■  Mon  $187            │
///  │  ■■■■■■■■    Thu  $156            │
///  │  ■■■■■■      Sat  $142            │
///  │  ■■■■        Tue  $98             │
///  │  ■■■         Fri  $72             │
///  │  ■■          Wed  $54             │
///  │  ■           Sun  $31             │
///  │                                    │
///  │  💡 Working Mon-Thu-Sat would      │
///  │     net you ~$485/week             │
///  └────────────────────────────────────┘
struct WeeklyPatternCard: View {
    let dayEarnings: [(dayOfWeek: Int, avgEarnings: Double, entryCount: Int)]
    let projectedOptimal: Double
    let avgActiveDays: Double
    let recommendation: String

    @State private var hasAppeared = false

    private let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let dayColors: [Color] = [
        .clear,
        BrandColors.info,           // Sun
        BrandColors.primary,        // Mon
        BrandColors.success,        // Tue
        BrandColors.warning,        // Wed
        BrandColors.primaryLight,   // Thu
        BrandColors.destructive,    // Fri
        BrandColors.info            // Sat
    ]

    private var maxAvg: Double {
        dayEarnings.first?.avgEarnings ?? 1
    }

    var body: some View {
        if dayEarnings.count >= 3 {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Your Best Days")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    Text("\(String(format: "%.1f", avgActiveDays)) days/wk avg")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                // Day bars
                ForEach(Array(dayEarnings.prefix(7).enumerated()), id: \.offset) { index, day in
                    let dayName = day.dayOfWeek >= 1 && day.dayOfWeek <= 7 ? dayNames[day.dayOfWeek] : "?"
                    let color = day.dayOfWeek >= 1 && day.dayOfWeek <= 7 ? dayColors[day.dayOfWeek] : BrandColors.textTertiary

                    HStack(spacing: Spacing.sm) {
                        Text(dayName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(BrandColors.textSecondary)
                            .frame(width: 32, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color.opacity(0.08))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [color.opacity(0.6), color],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: hasAppeared ? max(geo.size.width * (day.avgEarnings / maxAvg), 4) : 0)
                            }
                        }
                        .frame(height: 16)

                        Text(CurrencyFormatter.format(day.avgEarnings))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(index < 3 ? BrandColors.textPrimary : BrandColors.textTertiary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                // Smart recommendation
                if projectedOptimal > 100 {
                    Divider()

                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.warning)

                        Text(recommendation)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineSpacing(2)
                    }
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
}
