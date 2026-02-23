import SwiftUI

/// Visual 7x4 heatmap showing earning intensity by day-of-week x time-of-day.
///
/// This answers the #1 gig worker question: "When should I work?"
/// Color intensity maps to average net earnings: darker = more profitable.
/// Tapping a cell shows the exact $/hr for that slot.
struct EarningsHeatmapCard: View {
    let heatmapData: [[Double]]  // 7 rows (Sun-Sat) x 4 cols (Morning/Afternoon/Evening/Night)
    let bestSlot: (day: Int, block: Int)?  // Indices of the highest-earning cell

    @State private var hasAppeared = false
    @State private var selectedCell: (day: Int, block: Int)? = nil

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let blockLabels = ["AM", "PM", "Eve", "Nit"]
    private let blockFullNames = ["Morning", "Afternoon", "Evening", "Night"]

    /// Maximum value across the entire heatmap (for normalization)
    private var maxValue: Double {
        heatmapData.flatMap { $0 }.max() ?? 1
    }

    /// Whether there's enough data to show the heatmap
    private var hasData: Bool {
        heatmapData.flatMap { $0 }.contains(where: { $0 > 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandColors.primary)

                    Text("When to Work")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()

                if hasData, let best = bestSlot {
                    Text("\(dayName(best.day)) \(blockFullNames[best.block])")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BrandColors.success.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if hasData {
                // Block column headers
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 18)

                    ForEach(0..<4, id: \.self) { col in
                        Text(blockLabels[col])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(BrandColors.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Heatmap grid
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { row in
                        HStack(spacing: 3) {
                            // Day label
                            Text(dayLabels[row])
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(BrandColors.textTertiary)
                                .frame(width: 14)

                            // Time block cells
                            ForEach(0..<4, id: \.self) { col in
                                let value = row < heatmapData.count && col < heatmapData[row].count
                                    ? heatmapData[row][col] : 0
                                let intensity = maxValue > 0 ? value / maxValue : 0
                                let isSelected = selectedCell?.day == row && selectedCell?.block == col
                                let isBest = bestSlot?.day == row && bestSlot?.block == col

                                ZStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(cellColor(intensity: intensity))
                                        .frame(height: hasAppeared ? 22 : 0)
                                        .animation(
                                            .easeOut(duration: 0.5)
                                                .delay(Double(row * 4 + col) * 0.02),
                                            value: hasAppeared
                                        )

                                    if isBest {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 7))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(isSelected ? BrandColors.primary : .clear, lineWidth: 1.5)
                                )
                                .onTapGesture {
                                    HapticManager.shared.select()
                                    withAnimation(AnimationConstants.smooth) {
                                        if isSelected {
                                            selectedCell = nil
                                        } else {
                                            selectedCell = (row, col)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Selected cell detail
                if let cell = selectedCell {
                    let value = cell.day < heatmapData.count && cell.block < heatmapData[cell.day].count
                        ? heatmapData[cell.day][cell.block] : 0

                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColors.textTertiary)

                        Text("\(dayName(cell.day)) \(blockFullNames[cell.block]): avg \(CurrencyFormatter.format(value))/gig")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Legend
                HStack(spacing: Spacing.xs) {
                    Text("Low")
                        .font(.system(size: 10))
                        .foregroundStyle(BrandColors.textTertiary)

                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(cellColor(intensity: Double(i) / 4.0))
                                .frame(width: 12, height: 6)
                        }
                    }

                    Text("High")
                        .font(.system(size: 10))
                        .foregroundStyle(BrandColors.textTertiary)

                    Spacer()
                }
            } else {
                // Insufficient data
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.textTertiary)

                    Text("Log gigs at different times to see your earnings heatmap.")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .gwCard()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Helpers

    private func cellColor(intensity: Double) -> Color {
        // Gradient from light orange to deep brand orange
        let clamped = min(max(intensity, 0), 1)
        if clamped < 0.01 {
            return BrandColors.textTertiary.opacity(0.08)
        }
        return BrandColors.primary.opacity(0.15 + clamped * 0.85)
    }

    private func dayName(_ index: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return index < names.count ? names[index] : ""
    }
}
