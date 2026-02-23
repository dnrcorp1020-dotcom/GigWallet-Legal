import SwiftUI
import SwiftData

/// Quick form to log an actual quarterly tax payment to the IRS or state.
/// This closes the critical gap: the app estimates what to pay, and now tracks IF you paid.
struct LogTaxPaymentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var quarter: TaxQuarter = .current
    @State private var paymentType: PaymentType = .federal
    @State private var paymentDate: Date = .now
    @State private var confirmationNumber: String = ""

    let suggestedAmount: Double

    var body: some View {
        Form {
            Section("Payment Details") {
                // Amount
                HStack {
                    Text("$")
                        .font(Typography.moneyMedium)
                        .foregroundStyle(BrandColors.textSecondary)
                    TextField("Amount", text: $amount)
                        .font(Typography.moneyMedium)
                        .keyboardType(.decimalPad)
                }

                if suggestedAmount > 0 {
                    Button {
                        amount = String(format: "%.0f", suggestedAmount)
                        HapticManager.shared.select()
                    } label: {
                        HStack {
                            Text("Use suggested amount")
                                .font(Typography.caption)
                            Spacer()
                            Text(CurrencyFormatter.format(suggestedAmount))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(BrandColors.primary)
                        }
                    }
                }

                // Quarter
                Picker("Quarter", selection: $quarter) {
                    ForEach(TaxQuarter.allCases) { q in
                        Text(q.displayName).tag(q)
                    }
                }

                // Federal vs State
                Picker("Payment To", selection: $paymentType) {
                    ForEach(PaymentType.allCases) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.rawValue)
                        }
                        .tag(type)
                    }
                }

                // Date
                DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)
            }

            Section("Optional") {
                TextField("Confirmation #", text: $confirmationNumber)
                    .textInputAutocapitalization(.characters)
            }

            if let irsURL = URL(string: "https://directpay.irs.gov") {
                Section {
                    // IRS Direct Pay link
                    Link(destination: irsURL) {
                        HStack {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(BrandColors.success)
                            Text("Pay IRS via Direct Pay")
                                .foregroundStyle(BrandColors.success)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
            }
        }
        .tint(BrandColors.primary)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Log Tax Payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    savePayment()
                }
                .disabled(amount.isEmpty || (Double(amount) ?? 0) <= 0 || !(Double(amount) ?? 0).isFinite)
                .fontWeight(.semibold)
            }
        }
    }

    private func savePayment() {
        guard let amountValue = Double(amount), amountValue > 0, amountValue.isFinite else { return }

        let payment = TaxPayment(
            taxYear: DateHelper.currentTaxYear,
            quarter: quarter,
            amount: amountValue,
            paymentDate: paymentDate,
            paymentType: paymentType,
            confirmationNumber: confirmationNumber
        )
        modelContext.insert(payment)

        // Also record in Tax Vault ledger so vault balance stays in sync
        let vaultEntry = TaxVaultEntry(
            amount: amountValue,
            type: .taxPayment,
            note: "\(paymentType.rawValue) payment — \(quarter.shortName)"
        )
        modelContext.insert(vaultEntry)

        HapticManager.shared.success()
        dismiss()
    }
}
