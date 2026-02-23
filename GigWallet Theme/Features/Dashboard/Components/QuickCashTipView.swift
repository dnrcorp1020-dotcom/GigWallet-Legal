import SwiftUI
import SwiftData

/// Quick cash tip logger — one-tap entry for the cash tips gig workers forget to track.
/// ~$20B/year in unreported cash tips in gig economy. This keeps them IRS-compliant
/// and ensures quarterly tax estimates are accurate.
struct QuickCashTipView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var selectedPlatform: GigPlatformType = .uber
    @State private var selectedPreset: Double? = nil

    let platforms: [GigPlatformType]

    private let presets: [Double] = [5, 10, 15, 20, 25, 50]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            // Header
            VStack(spacing: Spacing.sm) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(BrandColors.success)

                Text("Log Cash Tips")
                    .font(Typography.title)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("Cash tips are taxable income. Logging them keeps your tax estimate accurate.")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            // Quick presets
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3), spacing: Spacing.md) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        selectedPreset = preset
                        amount = String(format: "%.0f", preset)
                        HapticManager.shared.select()
                    } label: {
                        Text("$\(String(Int(preset)))")
                            .font(Typography.moneySmall)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(selectedPreset == preset ? BrandColors.success.opacity(0.15) : BrandColors.secondaryBackground)
                            .foregroundStyle(selectedPreset == preset ? BrandColors.success : BrandColors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm)
                                    .stroke(selectedPreset == preset ? BrandColors.success : .clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(GWButtonPressStyle())
                }
            }
            .padding(.horizontal, Spacing.lg)

            // Custom amount
            HStack {
                Text("$")
                    .font(Typography.moneyMedium)
                    .foregroundStyle(BrandColors.textSecondary)
                TextField("Custom amount", text: $amount)
                    .font(Typography.moneyMedium)
                    .keyboardType(.decimalPad)
                    .onChange(of: amount) { _, _ in
                        selectedPreset = nil
                    }
            }
            .padding(Spacing.lg)
            .background(BrandColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .padding(.horizontal, Spacing.lg)

            // Platform picker (horizontal scroll)
            if platforms.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(platforms, id: \.self) { platform in
                            Button {
                                selectedPlatform = platform
                                HapticManager.shared.select()
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: platform.sfSymbol)
                                        .font(.system(size: 12))
                                    Text(platform.displayName)
                                        .font(Typography.caption)
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(selectedPlatform == platform ? platform.brandColor.opacity(0.15) : BrandColors.secondaryBackground)
                                .foregroundStyle(selectedPlatform == platform ? platform.brandColor : BrandColors.textSecondary)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }

            Spacer()

            // Save button
            GWButton("Log \(amount.isEmpty ? "Cash Tips" : "$\(amount) Cash Tips")", icon: "plus.circle.fill") {
                saveTip()
            }
            .padding(.horizontal, Spacing.lg)
            .disabled(amount.isEmpty || (Double(amount) ?? 0) <= 0)
            .opacity(amount.isEmpty || (Double(amount) ?? 0) <= 0 ? 0.5 : 1)
        }
        .padding(.top, Spacing.xxl)
        .navigationTitle("Cash Tips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func saveTip() {
        guard let tipAmount = Double(amount), tipAmount > 0 else { return }

        // Create income entry with tips only (no base amount — pure cash tip)
        let entry = IncomeEntry(
            amount: 0,
            tips: tipAmount,
            platformFees: 0,
            platform: selectedPlatform,
            entryMethod: .manual,
            entryDate: .now,
            notes: "Cash tip"
        )

        modelContext.insert(entry)
        HapticManager.shared.success()
        dismiss()
    }
}
