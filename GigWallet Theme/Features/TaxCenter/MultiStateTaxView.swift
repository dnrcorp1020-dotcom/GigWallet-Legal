import SwiftUI
import SwiftData

/// Shows per-state income breakdown and multi-state tax estimates.
/// Allows adding additional states and viewing tax implications.
struct MultiStateTaxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \IncomeEntry.entryDate, order: .reverse) private var incomeEntries: [IncomeEntry]
    @Query private var profiles: [UserProfile]

    @State private var showingAddState = false
    @State private var selectedNewState = "NY"

    private var profile: UserProfile? { profiles.first }
    private let taxEngine = TaxEngine()

    /// All US state codes with income tax support in TaxEngine.
    private static let allStateCodes = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]

    /// States the user has configured (primary + additional).
    private var configuredStates: [String] {
        var states = [profile?.stateCode ?? "CA"]
        states.append(contentsOf: profile?.additionalStates ?? [])
        return states
    }

    /// Income entries for the current tax year.
    private var yearlyEntries: [IncomeEntry] {
        incomeEntries.filter { $0.taxYear == DateHelper.currentTaxYear }
    }

    /// Total yearly income.
    private var yearlyIncome: Double {
        yearlyEntries.reduce(0) { $0 + $1.netAmount }
    }

    /// Per-state income breakdown (entries with stateCode or defaulting to profile state).
    private var stateIncomeBreakdown: [(stateCode: String, income: Double, entryCount: Int)] {
        let defaultState = profile?.stateCode ?? "CA"
        var stateMap: [String: (income: Double, count: Int)] = [:]

        for entry in yearlyEntries {
            let state = entry.stateCode ?? defaultState
            let existing = stateMap[state] ?? (income: 0, count: 0)
            stateMap[state] = (income: existing.income + entry.netAmount, count: existing.count + 1)
        }

        return stateMap.map { (stateCode: $0.key, income: $0.value.income, entryCount: $0.value.count) }
            .sorted { $0.income > $1.income }
    }

    /// Multi-state tax calculation using TaxEngine.
    private var multiStateTaxResult: (federal: TaxCalculationResult, state: TaxEngine.MultiStateResult)? {
        guard yearlyIncome > 0 else { return nil }
        let allocations = stateIncomeBreakdown.map { breakdown in
            TaxEngine.StateAllocation(
                stateCode: breakdown.stateCode,
                incomeShare: yearlyIncome > 0 ? breakdown.income / yearlyIncome : 0
            )
        }
        guard !allocations.isEmpty else { return nil }

        let yearlyDeductions = 0.0 // Deductions handled separately
        return taxEngine.calculateMultiStateEstimate(
            grossIncome: yearlyIncome,
            totalDeductions: yearlyDeductions,
            filingStatus: profile?.filingStatus ?? .single,
            stateAllocations: allocations
        )
    }

    var body: some View {
        List {
            // Summary header
            Section {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(BrandColors.info)

                    Text("Multi-State Tax")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text("\(configuredStates.count) state\(configuredStates.count == 1 ? "" : "s") configured")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
            }

            // Per-state breakdown
            if !stateIncomeBreakdown.isEmpty {
                Section("Income by State") {
                    ForEach(stateIncomeBreakdown, id: \.stateCode) { breakdown in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(breakdown.stateCode)
                                    .font(Typography.headline)
                                    .foregroundStyle(BrandColors.textPrimary)

                                Text("\(breakdown.entryCount) entr\(breakdown.entryCount == 1 ? "y" : "ies")")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyFormatter.format(breakdown.income))
                                    .font(Typography.moneySmall)
                                    .foregroundStyle(BrandColors.textPrimary)

                                if yearlyIncome > 0 {
                                    let share = breakdown.income / yearlyIncome * 100
                                    Text("\(String(format: "%.0f", share))%")
                                        .font(Typography.caption2)
                                        .foregroundStyle(BrandColors.textSecondary)
                                }
                            }
                        }
                    }
                }
            }

            // State tax estimates
            if let result = multiStateTaxResult {
                Section("State Tax Estimates") {
                    ForEach(result.state.details, id: \.stateCode) { detail in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.stateCode)
                                    .font(Typography.headline)
                                    .foregroundStyle(BrandColors.textPrimary)

                                let rate = taxEngine.stateEffectiveTaxRate(for: detail.stateCode)
                                Text(rate == 0 ? "No state income tax" : "\(String(format: "%.2f", rate * 100))% rate")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }

                            Spacer()

                            Text(CurrencyFormatter.format(detail.stateTax))
                                .font(Typography.moneySmall)
                                .foregroundStyle(detail.stateTax > 0 ? BrandColors.destructive : BrandColors.success)
                        }
                    }

                    // Total
                    HStack {
                        Text("Total State Tax")
                            .font(Typography.headline)
                            .foregroundStyle(BrandColors.textPrimary)
                        Spacer()
                        Text(CurrencyFormatter.format(result.state.totalStateTax))
                            .font(Typography.moneySmall)
                            .foregroundStyle(BrandColors.destructive)
                    }
                }
            }

            // Manage states
            Section("Manage States") {
                ForEach(profile?.additionalStates ?? [], id: \.self) { state in
                    HStack {
                        Text(state)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                        Spacer()
                        Button {
                            removeState(state)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(BrandColors.destructive)
                        }
                    }
                }

                Button {
                    showingAddState = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(BrandColors.primary)
                        Text("Add State")
                            .foregroundStyle(BrandColors.primary)
                    }
                }
            }

            // Info
            Section {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.info)

                    Text("Set per-entry states when adding income. Entries without a state use your primary state (\(profile?.stateCode ?? "CA")).")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .navigationTitle("Multi-State Taxes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Add State", isPresented: $showingAddState) {
            Picker("State", selection: $selectedNewState) {
                ForEach(availableStates, id: \.self) { state in
                    Text(state).tag(state)
                }
            }
            Button("Add") { addState(selectedNewState) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Select a state where you earn gig income.")
        }
    }

    /// States not yet configured.
    private var availableStates: [String] {
        let configured = Set(configuredStates)
        return Self.allStateCodes.filter { !configured.contains($0) }
    }

    private func addState(_ state: String) {
        guard let profile else { return }
        if !profile.additionalStates.contains(state) {
            profile.additionalStates.append(state)
            profile.updatedAt = .now
        }
    }

    private func removeState(_ state: String) {
        guard let profile else { return }
        profile.additionalStates.removeAll { $0 == state }
        profile.updatedAt = .now
    }
}
