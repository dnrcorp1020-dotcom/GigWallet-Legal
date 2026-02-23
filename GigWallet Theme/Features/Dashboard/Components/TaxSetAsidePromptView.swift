import SwiftUI
import SwiftData

/// Compact sheet shown after saving income — prompts user to set aside tax money.
/// "Set aside $XX for taxes?" with one-tap confirmation.
struct TaxSetAsidePromptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let incomeAmount: Double
    let effectiveTaxRate: Double

    @State private var didSetAside = false

    private var suggestedAmount: Double {
        round(incomeAmount * effectiveTaxRate * 100) / 100
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            if didSetAside {
                // Success state
                VStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(BrandColors.success)

                    Text("Set Aside!")
                        .font(Typography.title)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text("\(CurrencyFormatter.format(suggestedAmount)) moved to your Tax Vault")
                        .font(Typography.subheadline)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                // Prompt state
                VStack(spacing: Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.primary.opacity(0.12))
                            .frame(width: 72, height: 72)

                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(BrandColors.primary)
                    }

                    Text("Set aside for taxes?")
                        .font(Typography.title)
                        .foregroundStyle(BrandColors.textPrimary)

                    VStack(spacing: Spacing.xs) {
                        Text("You just earned \(CurrencyFormatter.format(incomeAmount))")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)

                        HStack(spacing: Spacing.xs) {
                            Text("Suggested:")
                                .font(Typography.body)
                                .foregroundStyle(BrandColors.textSecondary)

                            Text(CurrencyFormatter.format(suggestedAmount))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(BrandColors.primary)
                        }

                        Text("Based on your \(String(Int(effectiveTaxRate * 100)))% effective tax rate")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                VStack(spacing: Spacing.md) {
                    GWButton("Set Aside", icon: "lock.shield.fill") {
                        setAside()
                    }

                    Button("Not Now") {
                        dismiss()
                    }
                    .font(Typography.subheadline)
                    .foregroundStyle(BrandColors.textSecondary)
                }
                .padding(.horizontal, Spacing.xxl)
            }
        }
        .padding(.vertical, Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func setAside() {
        let entry = TaxVaultEntry(
            amount: suggestedAmount,
            type: .setAside,
            note: "Auto-prompted after \(CurrencyFormatter.format(incomeAmount)) income"
        )
        modelContext.insert(entry)
        HapticManager.shared.success()

        withAnimation(AnimationConstants.spring) {
            didSetAside = true
        }

        // Auto-dismiss after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}
