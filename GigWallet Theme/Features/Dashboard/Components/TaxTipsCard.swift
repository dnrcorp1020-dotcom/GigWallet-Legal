import SwiftUI

/// Displays personalized tax savings tips on the dashboard
struct TaxTipsCard: View {
    let tips: [TaxTipsEngine.TaxTip]
    @State private var showingAllTips = false

    private var visibleTips: [TaxTipsEngine.TaxTip] {
        Array(tips.prefix(2))
    }

    var body: some View {
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "lightbulb.max.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(BrandColors.primary)

                    Text("Savings Tips")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    if tips.count > 2 {
                        Button {
                            showingAllTips = true
                        } label: {
                            Text("See All (\(String(tips.count)))")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.primary)
                        }
                    }
                }

                ForEach(visibleTips) { tip in
                    TaxTipRow(tip: tip)
                }
            }
            .gwCard()
            .sheet(isPresented: $showingAllTips) {
                NavigationStack {
                    AllTaxTipsView(tips: tips)
                }
            }
        }
    }
}

struct TaxTipRow: View {
    let tip: TaxTipsEngine.TaxTip

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: tip.icon)
                .font(.system(size: 16))
                .foregroundStyle(priorityColor)
                .frame(width: 28, height: 28)
                .background(priorityColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(tip.title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.textPrimary)

                Text(tip.detail)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(3)

                if let savings = tip.potentialSavings, savings > 0 {
                    Text("Potential: \(CurrencyFormatter.format(savings))")
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColors.success)
                }
            }
        }
    }

    private var priorityColor: Color {
        switch tip.priority {
        case .critical: return BrandColors.destructive
        case .high: return BrandColors.warning
        case .medium: return BrandColors.primary
        case .low: return BrandColors.info
        }
    }
}

struct AllTaxTipsView: View {
    @Environment(\.dismiss) private var dismiss
    let tips: [TaxTipsEngine.TaxTip]

    private var totalPotentialSavings: Double {
        tips.compactMap(\.potentialSavings).reduce(0, +)
    }

    var body: some View {
        List {
            if totalPotentialSavings > 0 {
                Section {
                    VStack(spacing: Spacing.sm) {
                        Text("Total Potential Savings")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text(CurrencyFormatter.format(totalPotentialSavings))
                            .font(Typography.moneyLarge)
                            .foregroundStyle(BrandColors.success)
                        Text("per year if you act on all tips")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                }
            }

            ForEach(tips) { tip in
                Section {
                    TaxTipRow(tip: tip)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tax Savings Tips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
