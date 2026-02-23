import SwiftUI
import SwiftData

/// Modal view for quickly setting aside a custom amount for taxes.
struct QuickSetAsideView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let suggestedAmount: Double
    let effectiveTaxRate: Double

    @State private var amount: Double = 0
    @State private var note: String = ""

    private let presets: [Double] = [25, 50, 100, 200, 500]

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                // Header
                VStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.success.opacity(0.1))
                            .frame(width: 64, height: 64)

                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(BrandColors.success)
                    }

                    Text("Set Aside for Taxes")
                        .font(Typography.title)

                    Text("Based on your \(Int(effectiveTaxRate * 100))% effective tax rate")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .padding(.top, Spacing.lg)

                // Amount display
                Text(CurrencyFormatter.format(amount))
                    .font(Typography.moneyMedium)
                    .foregroundStyle(amount > 0 ? BrandColors.success : BrandColors.textTertiary)
                    .contentTransition(.numericText())

                // Preset buttons
                VStack(spacing: Spacing.md) {
                    // Suggested amount (if > 0)
                    if suggestedAmount > 5 {
                        Button {
                            amount = suggestedAmount
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 14))
                                Text("Suggested: \(CurrencyFormatter.format(suggestedAmount))")
                                    .font(Typography.bodyMedium)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(BrandColors.success)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                        }
                    }

                    // Quick presets
                    HStack(spacing: Spacing.sm) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                amount = preset
                            } label: {
                                Text("$\(Int(preset))")
                                    .font(Typography.caption)
                                    .foregroundStyle(amount == preset ? .white : BrandColors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.sm)
                                    .background(amount == preset ? BrandColors.success : BrandColors.tertiaryBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                            }
                        }
                    }

                    // Custom amount field
                    GWAmountField(title: "Custom Amount", amount: $amount, placeholder: "0.00")
                }
                .padding(.horizontal, Spacing.lg)

                // Note field
                TextField("Note (optional)", text: $note)
                    .padding(Spacing.md)
                    .background(BrandColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                    .padding(.horizontal, Spacing.lg)

                Spacer()

                // Save button
                GWButton("Set Aside \(CurrencyFormatter.format(amount))", icon: "lock.shield.fill") {
                    guard amount > 0 else { return }
                    let entry = TaxVaultEntry(
                        amount: amount,
                        type: .setAside,
                        note: note.isEmpty ? "Manual set-aside" : note
                    )
                    modelContext.insert(entry)
                    HapticManager.shared.success()
                    dismiss()
                }
                .disabled(amount <= 0)
                .opacity(amount > 0 ? 1.0 : 0.5)
                .padding(.horizontal, Spacing.lg)

                Text("This doesn't move real money \u{2014} it just tracks what you should save.")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.bottom, Spacing.lg)
            }
            .background(BrandColors.groupedBackground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
