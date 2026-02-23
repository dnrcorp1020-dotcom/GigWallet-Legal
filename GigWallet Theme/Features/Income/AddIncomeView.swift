import SwiftUI
import SwiftData

struct AddIncomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var amount: Double = 0
    @State private var tips: Double = 0
    @State private var platformFees: Double = 0
    @State private var selectedPlatform: GigPlatformType = .uber
    @State private var entryDate: Date = .now
    @State private var notes: String = ""
    @State private var selectedState: String = ""

    private var profile: UserProfile? { profiles.first }

    /// Whether user has multiple states configured (show state picker).
    private var hasMultipleStates: Bool {
        guard let profile else { return false }
        return !profile.additionalStates.isEmpty
    }

    /// All states to choose from: primary + additional.
    private var availableStates: [String] {
        guard let profile else { return [] }
        var states = [profile.stateCode]
        states.append(contentsOf: profile.additionalStates)
        return states
    }

    var body: some View {
        Form {
            Section("Platform") {
                Picker("Platform", selection: $selectedPlatform) {
                    ForEach(GigPlatformType.allCases) { platform in
                        HStack {
                            Image(systemName: platform.sfSymbol)
                            Text(platform.displayName)
                        }
                        .tag(platform)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Earnings") {
                GWAmountField(title: "Amount Earned", amount: $amount, placeholder: "0.00")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                GWAmountField(title: "Tips", amount: $tips, placeholder: "0.00")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                GWAmountField(title: "Platform Fees", amount: $platformFees, placeholder: "0.00")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("Details") {
                DatePicker("Date", selection: $entryDate, displayedComponents: .date)

                // State picker — only visible when user has multi-state setup
                if hasMultipleStates {
                    Picker("State", selection: $selectedState) {
                        ForEach(availableStates, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }
                }

                TextField("Notes (optional)", text: $notes)
            }

            Section {
                HStack {
                    Text("Net Amount")
                        .font(Typography.headline)
                    Spacer()
                    let netAmount = amount + tips - platformFees
                    Text(CurrencyFormatter.format(netAmount))
                        .font(Typography.moneySmall)
                        .foregroundStyle(netAmount >= 0 ? BrandColors.success : BrandColors.destructive)
                }
            }
        }
        .tint(BrandColors.primary)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Add Income")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveEntry()
                }
                .fontWeight(.semibold)
                .disabled(amount <= 0 || tips < 0 || platformFees < 0)
            }
        }
        .onAppear {
            // Default to profile's primary state
            if selectedState.isEmpty {
                selectedState = profile?.stateCode ?? "CA"
            }
        }
    }

    private func saveEntry() {
        // Only set stateCode on entry if user has multi-state; otherwise nil (uses profile default)
        let entryState: String? = hasMultipleStates ? selectedState : nil

        let entry = IncomeEntry(
            amount: amount,
            tips: tips,
            platformFees: platformFees,
            platform: selectedPlatform,
            entryMethod: .manual,
            entryDate: entryDate,
            notes: notes,
            stateCode: entryState
        )
        modelContext.insert(entry)
        dismiss()
    }
}
