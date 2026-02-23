import SwiftUI

/// Welcome card for new users with quick-start checklist.
/// Shows only when experienceLevel == .newcomer AND total entries < 3.
struct DashboardWelcomeCard: View {
    let hasIncome: Bool
    let hasExpense: Bool
    let hasGoal: Bool
    let onAddIncome: () -> Void
    let onAddExpense: () -> Void
    let onSetGoal: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Welcome to GigWallet!")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(BrandColors.textPrimary)

                    Text("Get started in 3 quick steps")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }

            // Checklist
            VStack(spacing: Spacing.md) {
                welcomeStep(
                    number: 1,
                    title: "Log your first earnings",
                    subtitle: "Record a gig payment",
                    isComplete: hasIncome,
                    action: onAddIncome
                )

                welcomeStep(
                    number: 2,
                    title: "Track a business expense",
                    subtitle: "Deduct mileage, supplies, etc.",
                    isComplete: hasExpense,
                    action: onAddExpense
                )

                welcomeStep(
                    number: 3,
                    title: "Set your weekly goal",
                    subtitle: "Stay motivated and on track",
                    isComplete: hasGoal,
                    action: onSetGoal
                )
            }

            // Progress
            let completedCount = [hasIncome, hasExpense, hasGoal].filter { $0 }.count
            HStack(spacing: Spacing.sm) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < completedCount ? BrandColors.success : BrandColors.textTertiary.opacity(0.2))
                        .frame(height: 4)
                }
            }

            if completedCount == 3 {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BrandColors.success)
                    Text("All set! You're ready to go.")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.success)
                }
            }
        }
        .padding(Spacing.lg)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
    }

    private func welcomeStep(number: Int, title: String, subtitle: String, isComplete: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // Checkmark or number
                ZStack {
                    Circle()
                        .fill(isComplete ? BrandColors.success : BrandColors.primary.opacity(0.12))
                        .frame(width: 32, height: 32)

                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(BrandColors.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(isComplete ? BrandColors.textTertiary : BrandColors.textPrimary)
                        .strikethrough(isComplete)

                    Text(subtitle)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                Spacer()

                if !isComplete {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
        }
        .disabled(isComplete)
    }
}
