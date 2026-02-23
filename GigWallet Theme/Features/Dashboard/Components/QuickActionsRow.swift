import SwiftUI

struct QuickActionsRow: View {
    let onAddIncome: () -> Void
    let onAddExpense: () -> Void
    let onAddMileage: () -> Void
    var onAddCashTip: (() -> Void)? = nil
    var onScanReceipt: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            QuickActionButton(
                icon: "dollarsign.circle.fill",
                title: L10n.quickActionIncome,
                color: BrandColors.success,
                action: onAddIncome
            )

            QuickActionButton(
                icon: "creditcard.fill",
                title: L10n.quickActionExpense,
                color: BrandColors.destructive,
                action: onAddExpense
            )

            QuickActionButton(
                icon: "car.fill",
                title: L10n.quickActionMileage,
                color: BrandColors.info,
                action: onAddMileage
            )

            if let onAddCashTip {
                QuickActionButton(
                    icon: "banknote.fill",
                    title: L10n.quickActionCashTip,
                    color: BrandColors.warning,
                    action: onAddCashTip
                )
            }

            if let onScanReceipt {
                QuickActionButton(
                    icon: "camera.viewfinder",
                    title: L10n.quickActionScan,
                    color: BrandColors.secondary,
                    action: onScanReceipt
                )
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.action()
            action()
        } label: {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(color)
                }

                Text("+ \(title)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .shadow(color: BrandColors.cardShadow.opacity(0.5), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(GWButtonPressStyle())
        .accessibilityLabel("Add \(title)")
        .accessibilityAddTraits(.isButton)
    }
}
