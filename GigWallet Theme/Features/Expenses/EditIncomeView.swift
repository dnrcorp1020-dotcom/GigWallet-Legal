import SwiftUI
import SwiftData

struct EditIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: IncomeEntry

    // Local editable copies — we only write back on Save
    @State private var amount: Double
    @State private var tips: Double
    @State private var platformFees: Double
    @State private var selectedPlatform: GigPlatformType
    @State private var entryDate: Date
    @State private var notes: String

    init(entry: IncomeEntry) {
        self.entry = entry
        _amount          = State(initialValue: entry.amount)
        _tips            = State(initialValue: entry.tips)
        _platformFees    = State(initialValue: entry.platformFees)
        _selectedPlatform = State(initialValue: entry.platform)
        _entryDate       = State(initialValue: entry.entryDate)
        _notes           = State(initialValue: entry.notes)
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
                TextField("Notes (optional)", text: $notes)
            }

            Section {
                HStack {
                    Text("Net Amount")
                        .font(Typography.headline)
                    Spacer()
                    Text(CurrencyFormatter.format(amount + tips - platformFees))
                        .font(Typography.moneySmall)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(BrandColors.success)
                }
            }
        }
        .tint(BrandColors.primary)
        .navigationTitle("Edit Income")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { saveChanges() }
                    .fontWeight(.semibold)
                    .disabled(amount <= 0)
            }
        }
    }

    private func saveChanges() {
        entry.amount       = amount
        entry.tips         = tips
        entry.platformFees = platformFees
        entry.platform     = selectedPlatform
        entry.entryDate    = entryDate
        entry.notes        = notes
        // Re-derive tax year and quarter from the (potentially new) date
        entry.taxYear        = entryDate.taxYear
        entry.quarterRawValue = entryDate.taxQuarter.rawValue
        entry.updatedAt      = .now
        dismiss()
    }
}
