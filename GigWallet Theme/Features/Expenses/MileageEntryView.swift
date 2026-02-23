import SwiftUI
import SwiftData

struct MileageEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var miles: String = ""
    @State private var purpose: String = ""
    @State private var startLocation: String = ""
    @State private var endLocation: String = ""
    @State private var tripDate: Date = .now
    @State private var selectedPlatform: GigPlatformType = .other
    @State private var isBusinessMiles: Bool = true
    @State private var showingTripReview = false
    @State private var trackingService = MileageTrackingService.shared

    private var mileageRate: Double {
        TaxEngine.TaxConstants.mileageRate
    }

    private var estimatedDeduction: Double {
        isBusinessMiles ? (Double(miles) ?? 0) * mileageRate : 0
    }

    private var isValid: Bool {
        guard let milesValue = Double(miles), milesValue > 0 else { return false }
        return true
    }

    var body: some View {
        Form {
            // Auto GPS Tracking
            Section {
                MileageTrackingToggleView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Pending auto-detected trips
            if !trackingService.pendingTrips.isEmpty {
                Section {
                    Button {
                        showingTripReview = true
                    } label: {
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(BrandColors.primary.opacity(0.12))
                                    .frame(width: 36, height: 36)

                                Image(systemName: "clock.badge.checkmark")
                                    .font(.system(size: 14))
                                    .foregroundStyle(BrandColors.primary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(trackingService.pendingTrips.count) pending trip\(trackingService.pendingTrips.count == 1 ? "" : "s")")
                                    .font(Typography.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BrandColors.textPrimary)

                                let totalMiles = trackingService.pendingTrips.reduce(0) { $0 + $1.distanceMiles }
                                Text("\(String(format: "%.1f", totalMiles)) miles to review")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textSecondary)
                            }

                            Spacer()

                            Text("Review")
                                .font(Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 6)
                                .background(BrandColors.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Deduction Preview
            Section {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(BrandColors.info)

                    Text(CurrencyFormatter.format(estimatedDeduction))
                        .font(Typography.moneyLarge)
                        .foregroundStyle(BrandColors.success)

                    Text("estimated deduction")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)

                    Text("IRS Rate: $\(String(format: "%.3f", mileageRate))/mile (\(String(DateHelper.currentTaxYear)))")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .listRowBackground(BrandColors.cardBackground)
            }

            // Miles
            Section("Trip Details") {
                HStack {
                    Text("Miles")
                    Spacer()
                    TextField("0", text: $miles)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }

                DatePicker("Date", selection: $tripDate, displayedComponents: .date)

                Picker("Platform", selection: $selectedPlatform) {
                    ForEach(GigPlatformType.allCases) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }

                // Business vs Commute toggle — IRS distinction
                Picker("Trip Type", selection: $isBusinessMiles) {
                    Text("Business").tag(true)
                    Text("Commute").tag(false)
                }
                .pickerStyle(.segmented)

                if !isBusinessMiles {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.warning)
                        Text("Commute miles (home → first stop) are not deductible per IRS rules.")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }

            // Locations (optional)
            Section("Route (Optional)") {
                TextField("Start location", text: $startLocation)
                TextField("End location", text: $endLocation)
                TextField("Purpose (e.g., deliveries, rideshare)", text: $purpose)
            }

            // Common Presets
            Section("Quick Entry") {
                HStack(spacing: Spacing.md) {
                    MileagePresetButton(label: "5 mi", miles: "5", selectedMiles: $miles)
                    MileagePresetButton(label: "10 mi", miles: "10", selectedMiles: $miles)
                    MileagePresetButton(label: "25 mi", miles: "25", selectedMiles: $miles)
                    MileagePresetButton(label: "50 mi", miles: "50", selectedMiles: $miles)
                    MileagePresetButton(label: "100 mi", miles: "100", selectedMiles: $miles)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .tint(BrandColors.primary)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showingTripReview) {
            NavigationStack {
                TripReviewView()
            }
        }
        .navigationTitle("Log Mileage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveMileage()
                }
                .fontWeight(.semibold)
                .disabled(!isValid)
            }
        }
    }

    private func saveMileage() {
        guard let milesValue = Double(miles), milesValue > 0 else { return }

        let trip = MileageTrip(
            miles: milesValue,
            purpose: purpose,
            startLocation: startLocation,
            endLocation: endLocation,
            tripDate: tripDate,
            platform: selectedPlatform,
            isBusinessMiles: isBusinessMiles
        )
        modelContext.insert(trip)

        // Only create deduction expense for business miles (commute is NOT deductible)
        if isBusinessMiles {
            let expense = ExpenseEntry(
                amount: estimatedDeduction,
                category: .mileage,
                vendor: "Mileage - \(String(format: "%.1f", milesValue)) mi",
                description: purpose.isEmpty ? "Mileage deduction" : purpose,
                expenseDate: tripDate,
                deductionPercentage: 100,
                mileage: milesValue
            )
            modelContext.insert(expense)
        }

        HapticManager.shared.success()
        dismiss()
    }
}

struct MileagePresetButton: View {
    let label: String
    let miles: String
    @Binding var selectedMiles: String

    var isSelected: Bool { selectedMiles == miles }

    var body: some View {
        Button {
            selectedMiles = miles
        } label: {
            Text(label)
                .font(Typography.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? BrandColors.info : BrandColors.info.opacity(0.1))
                .foregroundStyle(isSelected ? .white : BrandColors.info)
                .clipShape(Capsule())
        }
    }
}
