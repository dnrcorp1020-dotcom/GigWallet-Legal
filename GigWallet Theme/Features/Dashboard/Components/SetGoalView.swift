import SwiftUI
import SwiftData

/// Sheet for setting weekly/monthly earnings goals
struct SetGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var weeklyGoalText = ""
    @State private var monthlyGoalText = ""

    private var profile: UserProfile? { profiles.first }

    private let quickGoals: [(label: String, weekly: Double)] = [
        ("$500/wk", 500),
        ("$750/wk", 750),
        ("$1,000/wk", 1000),
        ("$1,500/wk", 1500),
        ("$2,000/wk", 2000),
    ]

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            // Header
            VStack(spacing: Spacing.sm) {
                Image(systemName: "target")
                    .font(.system(size: 40))
                    .foregroundStyle(BrandColors.primary)
                    .padding(.bottom, Spacing.sm)

                Text("Set Your Earnings Goal")
                    .font(Typography.title)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("Stay on track by setting a weekly target")
                    .font(Typography.callout)
                    .foregroundStyle(BrandColors.textSecondary)
            }
            .padding(.top, Spacing.lg)

            // Quick presets
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Quick Set")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
                    .padding(.leading, Spacing.xs)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.sm) {
                    ForEach(quickGoals, id: \.weekly) { goal in
                        Button {
                            weeklyGoalText = String(Int(goal.weekly))
                            monthlyGoalText = String(Int(goal.weekly * 4.33))
                        } label: {
                            Text(goal.label)
                                .font(Typography.bodyMedium)
                                .foregroundStyle(
                                    weeklyGoalText == String(Int(goal.weekly))
                                        ? .white
                                        : BrandColors.textPrimary
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    weeklyGoalText == String(Int(goal.weekly))
                                        ? BrandColors.primary
                                        : BrandColors.primary.opacity(0.08)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                        }
                    }
                }
            }

            // Custom amount input
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Or enter a custom amount")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
                    .padding(.leading, Spacing.xs)

                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Weekly")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        HStack(spacing: Spacing.xs) {
                            Text("$")
                                .font(Typography.moneySmall)
                                .foregroundStyle(BrandColors.textTertiary)
                            TextField("0", text: $weeklyGoalText)
                                .font(Typography.moneySmall)
                                .keyboardType(.numberPad)
                                .onChange(of: weeklyGoalText) { _, newValue in
                                    if let weekly = Double(newValue) {
                                        monthlyGoalText = String(Int(weekly * 4.33))
                                    }
                                }
                        }
                        .padding(Spacing.md)
                        .background(BrandColors.groupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Monthly")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        HStack(spacing: Spacing.xs) {
                            Text("$")
                                .font(Typography.moneySmall)
                                .foregroundStyle(BrandColors.textTertiary)
                            TextField("0", text: $monthlyGoalText)
                                .font(Typography.moneySmall)
                                .keyboardType(.numberPad)
                                .onChange(of: monthlyGoalText) { _, newValue in
                                    if let monthly = Double(newValue) {
                                        weeklyGoalText = String(Int(monthly / 4.33))
                                    }
                                }
                        }
                        .padding(Spacing.md)
                        .background(BrandColors.groupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    }
                }
            }

            Spacer()

            // Save button
            Button {
                saveGoal()
            } label: {
                Text("Set Goal")
                    .font(Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                    .background(
                        (Double(weeklyGoalText) ?? 0) > 0
                            ? BrandColors.primary
                            : BrandColors.primary.opacity(0.4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            }
            .disabled((Double(weeklyGoalText) ?? 0) <= 0)

            if (profile?.weeklyEarningsGoal ?? 0) > 0 {
                Button {
                    clearGoal()
                } label: {
                    Text("Remove Goal")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.destructive)
                }
                .padding(.bottom, Spacing.sm)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .navigationTitle("Earnings Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if let profile, profile.weeklyEarningsGoal > 0 {
                weeklyGoalText = String(Int(profile.weeklyEarningsGoal))
                monthlyGoalText = String(Int(profile.monthlyEarningsGoal))
            }
        }
    }

    private func saveGoal() {
        guard let weekly = Double(weeklyGoalText), weekly > 0 else { return }
        let monthly = Double(monthlyGoalText) ?? (weekly * 4.33)

        if let profile {
            profile.weeklyEarningsGoal = weekly
            profile.monthlyEarningsGoal = monthly
            profile.updatedAt = .now
        }
        dismiss()
    }

    private func clearGoal() {
        if let profile {
            profile.weeklyEarningsGoal = 0
            profile.monthlyEarningsGoal = 0
            profile.updatedAt = .now
        }
        dismiss()
    }
}
