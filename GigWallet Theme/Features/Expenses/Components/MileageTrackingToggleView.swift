import SwiftUI

/// Toggle control for auto GPS mileage tracking.
/// Shows current tracking status and handles permission flow.
struct MileageTrackingToggleView: View {
    @State private var trackingService = MileageTrackingService.shared
    @State private var showingPermissionAlert = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Toggle row
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(trackingService.trackingState.color.opacity(0.12))
                        .frame(width: 40, height: 40)

                    Image(systemName: trackingService.trackingState.sfSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(trackingService.trackingState.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Track Mileage")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text(statusText)
                        .font(Typography.caption2)
                        .foregroundStyle(trackingService.trackingState.color)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { trackingService.isEnabled },
                    set: { newValue in
                        if newValue {
                            UserDefaults.standard.set(true, forKey: "mileageAutoTrackingEnabled")
                            if trackingService.hasLocationPermission {
                                trackingService.startTracking()
                            } else {
                                showingPermissionAlert = true
                            }
                        } else {
                            UserDefaults.standard.set(false, forKey: "mileageAutoTrackingEnabled")
                            trackingService.stopTracking()
                        }
                    }
                ))
                .tint(BrandColors.primary)
                .labelsHidden()
            }

            // Tracking status detail
            if trackingService.isEnabled {
                HStack(spacing: Spacing.sm) {
                    if trackingService.trackingState == .tracking {
                        // Live distance counter
                        HStack(spacing: 4) {
                            Circle()
                                .fill(BrandColors.success)
                                .frame(width: 6, height: 6)

                            Text("Driving — \(String(format: "%.1f", trackingService.currentTripDistance)) mi")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.success)
                        }
                    } else {
                        Image(systemName: "battery.100percent")
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColors.textTertiary)

                        Text("Uses minimal battery with smart detection")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }

                    Spacer()

                    // Pending trips count
                    if !trackingService.pendingTrips.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 11))

                            Text("\(trackingService.pendingTrips.count) pending")
                                .font(Typography.caption2)
                        }
                        .foregroundStyle(BrandColors.primary)
                    }
                }
            }

            // Pro badge
            HStack(spacing: Spacing.xs) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(BrandColors.primary)

                Text("Pro Feature")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrandColors.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(BrandColors.primary.opacity(0.08))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.lg)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
        .alert("Location Permission", isPresented: $showingPermissionAlert) {
            Button("Enable") {
                trackingService.requestPermission()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("GigWallet needs location access to automatically track your driving mileage for tax deductions.")
        }
        .onChange(of: trackingService.locationAuthStatus) { _, newStatus in
            // Auto-start tracking once permission is granted
            if (newStatus == .authorizedAlways || newStatus == .authorizedWhenInUse) && !trackingService.isEnabled {
                trackingService.startTracking()
            }
        }
    }

    private var statusText: String {
        switch trackingService.trackingState {
        case .idle:
            return "Not tracking"
        case .detecting:
            return "Waiting for driving activity..."
        case .tracking:
            return "Recording trip"
        case .stopped:
            return "Trip recorded"
        }
    }
}
