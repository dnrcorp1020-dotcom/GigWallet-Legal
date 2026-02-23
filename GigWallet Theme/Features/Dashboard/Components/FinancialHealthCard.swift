import SwiftUI

/// Dashboard card showing the Financial Health Score — a single 0-100 number
/// that answers "Am I on track?" instantly.
///
/// Displays the composite score as a large circular gauge with letter grade,
/// plus the top recommendation for improvement. Tappable for full breakdown.
struct FinancialHealthCard: View {
    let healthScore: FinancialHealthEngine.HealthScore?

    @State private var hasAppeared = false
    @State private var showingDetail = false
    @State private var animatedScore: Double = 0

    private var score: FinancialHealthEngine.HealthScore {
        healthScore ?? FinancialHealthEngine.HealthScore(
            score: 0, grade: "--", status: "Analyzing...",
            accentColor: "primary", dimensions: [], recommendations: [], trend: nil
        )
    }

    private var accentColor: Color {
        switch score.accentColor {
        case "success": return BrandColors.success
        case "warning": return BrandColors.warning
        case "destructive": return BrandColors.destructive
        case "info": return BrandColors.info
        default: return BrandColors.primary
        }
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Header
            HStack {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)

                    Text("Financial Health")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()

                if healthScore != nil {
                    Text(score.status)
                        .font(Typography.caption2)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if healthScore != nil {
                HStack(spacing: Spacing.lg) {
                    // Score ring
                    ZStack {
                        // Background ring
                        Circle()
                            .stroke(accentColor.opacity(0.12), lineWidth: 6)
                            .frame(width: 72, height: 72)

                        // Animated progress ring
                        Circle()
                            .trim(from: 0, to: hasAppeared ? animatedScore / 100.0 : 0)
                            .stroke(
                                accentColor,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))

                        // Score + grade
                        VStack(spacing: 0) {
                            Text("\(score.score)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(BrandColors.textPrimary)

                            Text(score.grade)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accentColor)
                        }
                    }

                    // Dimension mini-bars
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(score.dimensions.prefix(4)) { dim in
                            HStack(spacing: 6) {
                                Image(systemName: dim.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(BrandColors.textTertiary)
                                    .frame(width: 14)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(BrandColors.textTertiary.opacity(0.1))
                                            .frame(height: 4)

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(colorForDimScore(dim.score))
                                            .frame(
                                                width: hasAppeared ? geo.size.width * min(dim.score / 100, 1) : 0,
                                                height: 4
                                            )
                                    }
                                }
                                .frame(height: 4)

                                Text("\(Int(dim.score))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(BrandColors.textTertiary)
                                    .frame(width: 20, alignment: .trailing)
                            }
                        }
                    }
                }

                // Top recommendation
                if let topRec = score.recommendations.first {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: topRec.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(recColor(topRec.accentColor))

                        Text(topRec.title)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        Text(topRec.impact.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(recColor(topRec.accentColor))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(recColor(topRec.accentColor).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            } else {
                // Loading / insufficient data state
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing your financial data...")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .gwCard()
        .onAppear {
            guard healthScore != nil else { return }
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                hasAppeared = true
                animatedScore = Double(score.score)
            }
        }
    }

    private func colorForDimScore(_ score: Double) -> Color {
        switch score {
        case 75...: return BrandColors.success
        case 60..<75: return BrandColors.primary
        case 40..<60: return BrandColors.warning
        default: return BrandColors.destructive
        }
    }

    private func recColor(_ name: String) -> Color {
        switch name {
        case "success": return BrandColors.success
        case "warning": return BrandColors.warning
        case "destructive": return BrandColors.destructive
        case "info": return BrandColors.info
        default: return BrandColors.primary
        }
    }
}
