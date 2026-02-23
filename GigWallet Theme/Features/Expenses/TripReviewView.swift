import SwiftUI
import SwiftData

/// Review and confirm auto-detected mileage trips.
/// Users can adjust platform, trip type (business/commute), then confirm or dismiss.
struct TripReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var trackingService = MileageTrackingService.shared

    var body: some View {
        List {
            // Summary header
            Section {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(BrandColors.info)

                    Text("\(trackingService.pendingTrips.count) Pending Trip\(trackingService.pendingTrips.count == 1 ? "" : "s")")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    let totalMiles = trackingService.pendingTrips.reduce(0) { $0 + $1.distanceMiles }
                    let totalDeduction = totalMiles * TaxEngine.TaxConstants.mileageRate

                    Text("\(String(format: "%.1f", totalMiles)) miles \u{00B7} \(CurrencyFormatter.format(totalDeduction)) potential deduction")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .listRowBackground(BrandColors.cardBackground)
            }

            // Pending trips
            if trackingService.pendingTrips.isEmpty {
                Section {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(BrandColors.success)

                        Text("All trips reviewed!")
                            .font(Typography.headline)
                            .foregroundStyle(BrandColors.textPrimary)

                        Text("Auto-tracked trips will appear here when detected.")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                }
            } else {
                Section("Trips to Review") {
                    ForEach(Array(trackingService.pendingTrips.enumerated()), id: \.element.id) { index, trip in
                        TripReviewRow(
                            trip: Binding(
                                get: { trackingService.pendingTrips[index] },
                                set: { trackingService.pendingTrips[index] = $0 }
                            ),
                            onConfirm: { confirmTrip(trip) },
                            onDismiss: { trackingService.dismissTrip(trip) }
                        )
                    }
                }

                // Bulk action
                Section {
                    Button {
                        confirmAllTrips()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Confirm All as Business Miles")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        .foregroundStyle(BrandColors.success)
                        .font(Typography.body)
                        .fontWeight(.semibold)
                    }
                }
            }

            // IRS info
            Section {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.info)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("IRS Mileage Rate: $\(String(format: "%.3f", TaxEngine.TaxConstants.mileageRate))/mile")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textPrimary)

                        Text("Business miles are deductible. Commute miles (home \u{2192} first stop) are not.")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Review Trips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Actions

    private func confirmTrip(_ trip: MileageTrackingService.PendingTrip) {
        let (mileageTrip, expense) = trackingService.confirmTrip(trip)
        modelContext.insert(mileageTrip)
        if let expense {
            modelContext.insert(expense)
        }
        HapticManager.shared.success()
    }

    private func confirmAllTrips() {
        let results = trackingService.confirmAllAsBusinessTrips()
        for (mileageTrip, expense) in results {
            modelContext.insert(mileageTrip)
            if let expense {
                modelContext.insert(expense)
            }
        }
        HapticManager.shared.confirm()
    }
}

// MARK: - Trip Review Row

struct TripReviewRow: View {
    @Binding var trip: MileageTrackingService.PendingTrip
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Route map (when GPS data is available)
            if !trip.routeLocations.isEmpty {
                TripRouteMapView(routeCoordinates: trip.routeLocations)
            }

            // Route
            HStack(spacing: Spacing.sm) {
                VStack(spacing: 2) {
                    Circle()
                        .fill(BrandColors.success)
                        .frame(width: 8, height: 8)

                    Rectangle()
                        .fill(BrandColors.textTertiary.opacity(0.3))
                        .frame(width: 2, height: 20)

                    Circle()
                        .fill(BrandColors.destructive)
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(trip.startAddress)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)

                    Text(trip.endAddress)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                // Distance + time
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(String(format: "%.1f", trip.distanceMiles)) mi")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColors.primary)

                    Text(formatDuration(from: trip.startTime, to: trip.endTime))
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }

            // Platform + Trip Type pickers
            HStack(spacing: Spacing.md) {
                // Platform picker
                HStack(spacing: 4) {
                    Image(systemName: trip.platform.sfSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(trip.platform.brandColor)

                    Picker("Platform", selection: $trip.platform) {
                        ForEach(GigPlatformType.allCases) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(Typography.caption2)
                }

                Spacer()

                // Business / Commute toggle
                Picker("Type", selection: $trip.isBusinessMiles) {
                    Text("Business").tag(true)
                    Text("Commute").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            // Deduction estimate
            if trip.isBusinessMiles {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(BrandColors.success)

                    Text(CurrencyFormatter.format(trip.distanceMiles * TaxEngine.TaxConstants.mileageRate) + " deduction")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.success)
                }
            } else {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(BrandColors.warning)

                    Text("Commute \u{2014} not deductible")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.warning)
                }
            }

            // Action buttons
            HStack(spacing: Spacing.md) {
                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Confirm")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 8)
                    .background(BrandColors.success)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Dismiss")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrandColors.textTertiary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 8)
                    .background(BrandColors.textTertiary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func formatDuration(from start: Date, to end: Date) -> String {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMin = minutes % 60
        return "\(hours)h \(remainingMin)m"
    }
}
