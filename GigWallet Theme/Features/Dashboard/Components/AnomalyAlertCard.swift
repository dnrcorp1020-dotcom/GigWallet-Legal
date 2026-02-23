import SwiftUI

/// Dashboard card that displays statistically significant anomalies detected
/// by the AnomalyDetectionEngine (z-scores, IQR, modified z-scores, Grubbs' test).
///
/// Only shows when real anomalies are detected. Color-coded by severity:
/// - Critical (red): |z| > 3 standard deviations
/// - Warning (orange): |z| > 2 standard deviations
/// - Info (blue): |z| > 1.5 standard deviations
struct AnomalyAlertCard: View {
    let anomalies: [AnomalyDetectionEngine.Anomaly]

    @State private var showingAll = false

    private var visibleAnomalies: [AnomalyDetectionEngine.Anomaly] {
        showingAll ? anomalies : Array(anomalies.prefix(2))
    }

    private var hasCritical: Bool {
        anomalies.contains { $0.severity == .critical }
    }

    var body: some View {
        if !anomalies.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                HStack {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: hasCritical ? "exclamationmark.shield.fill" : "magnifyingglass.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(hasCritical ? BrandColors.destructive : BrandColors.warning)

                        Text("Anomaly Detection")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }

                    Spacer()

                    Text("\(anomalies.count) detected")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                // Anomaly list
                ForEach(visibleAnomalies) { anomaly in
                    anomalyRow(anomaly)
                }

                // Show more / less
                if anomalies.count > 2 {
                    Button {
                        withAnimation(AnimationConstants.smooth) {
                            showingAll.toggle()
                        }
                    } label: {
                        Text(showingAll ? "Show less" : "Show all \(anomalies.count) anomalies")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.primary)
                    }
                }
            }
            .gwCard()
        }
    }

    @ViewBuilder
    private func anomalyRow(_ anomaly: AnomalyDetectionEngine.Anomaly) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Severity indicator
            Circle()
                .fill(severityColor(anomaly.severity))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(anomaly.type.rawValue)
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    // Z-score badge
                    Text("z=\(String(format: "%.1f", abs(anomaly.zScore)))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(severityColor(anomaly.severity))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(severityColor(anomaly.severity).opacity(0.12))
                        )
                }

                Text(anomaly.description)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineLimit(2)

                if !anomaly.recommendation.isEmpty {
                    Text(anomaly.recommendation)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.primary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func severityColor(_ severity: AnomalyDetectionEngine.Severity) -> Color {
        switch severity {
        case .critical: return BrandColors.destructive
        case .warning: return BrandColors.warning
        case .info: return BrandColors.info
        }
    }
}
