import SwiftUI
import SwiftData

// MARK: - Financial Planner View

struct FinancialPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IncomeEntry.entryDate, order: .reverse) private var incomeEntries: [IncomeEntry]
    @Query(sort: \ExpenseEntry.expenseDate, order: .reverse) private var expenseEntries: [ExpenseEntry]
    @Query private var budgetItems: [BudgetItem]

    @State private var selectedMonthYear: String = BudgetItem.currentMonthYear
    @State private var showingAddItem = false
    @State private var editingItem: BudgetItem?

    // MARK: - Filtered Data

    private var monthBudgetItems: [BudgetItem] {
        budgetItems.filter { $0.monthYear == selectedMonthYear }
    }

    private var incomeItems: [BudgetItem] {
        monthBudgetItems.filter { $0.type == .income }
    }

    private var fixedExpenses: [BudgetItem] {
        monthBudgetItems.filter { $0.type == .expense && $0.isFixed }
    }

    private var variableExpenses: [BudgetItem] {
        monthBudgetItems.filter { $0.type == .expense && !$0.isFixed }
    }

    // MARK: - Gig Income (auto-calculated from IncomeEntry after deductions)

    private var gigIncomeForMonth: Double {
        let components = selectedMonthYear.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]) else { return 0 }

        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else { return 0 }

        return incomeEntries
            .filter { $0.entryDate >= startOfMonth && $0.entryDate < endOfMonth }
            .reduce(0) { $0 + $1.netAmount }
    }

    // MARK: - Gig Expenses (auto-calculated from ExpenseEntry for month)

    private var gigExpensesForMonth: Double {
        let components = selectedMonthYear.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]) else { return 0 }

        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else { return 0 }

        return expenseEntries
            .filter { $0.expenseDate >= startOfMonth && $0.expenseDate < endOfMonth }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Totals

    private var totalOtherIncome: Double {
        incomeItems.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        gigIncomeForMonth + totalOtherIncome
    }

    private var totalFixedExpenses: Double {
        fixedExpenses.reduce(0) { $0 + $1.amount }
    }

    private var totalVariableExpenses: Double {
        variableExpenses.reduce(0) { $0 + $1.amount }
    }

    private var totalBudgetExpenses: Double {
        totalFixedExpenses + totalVariableExpenses
    }

    private var totalExpenses: Double {
        totalBudgetExpenses + gigExpensesForMonth
    }

    private var surplus: Double {
        totalIncome - totalExpenses
    }

    // MARK: - Month Navigation

    private var availableMonths: [String] {
        var months = Set<String>()
        months.insert(BudgetItem.currentMonthYear)
        for item in budgetItems {
            months.insert(item.monthYear)
        }
        // Also include previous and next month
        let calendar = Calendar.current
        if let prev = calendar.date(byAdding: .month, value: -1, to: .now) {
            months.insert(BudgetItem.monthYear(for: prev))
        }
        if let next = calendar.date(byAdding: .month, value: 1, to: .now) {
            months.insert(BudgetItem.monthYear(for: next))
        }
        return months.sorted()
    }

    private func navigateMonth(by offset: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let current = formatter.date(from: selectedMonthYear),
              let newDate = Calendar.current.date(byAdding: .month, value: offset, to: current) else { return }
        selectedMonthYear = formatter.string(from: newDate)
        HapticManager.shared.select()
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {

                // Month navigator
                monthNavigator
                    .staggeredEntry(index: 0)

                // Monthly Summary Card
                summaryCard
                    .staggeredEntry(index: 1)

                // Income Section
                incomeSection
                    .staggeredEntry(index: 2)

                // Expenses Section
                expensesSection
                    .staggeredEntry(index: 3)

                // Bottom Line
                bottomLineCard
                    .staggeredEntry(index: 4)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BrandColors.groupedBackground)
        .gwNavigationTitle("Financial ", accent: "Planner", icon: "chart.pie.fill")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.shared.tap()
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(BrandColors.primary)
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            NavigationStack {
                AddBudgetItemView(monthYear: selectedMonthYear)
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                AddBudgetItemView(monthYear: selectedMonthYear, editingItem: item)
            }
        }
    }

    // MARK: - Month Navigator

    private var monthNavigator: some View {
        HStack {
            Button {
                navigateMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(BrandColors.cardBackground)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: Spacing.xxs) {
                Text(BudgetItem.displayName(for: selectedMonthYear))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(BrandColors.textPrimary)

                if selectedMonthYear == BudgetItem.currentMonthYear {
                    Text("Current Month")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.primary)
                }
            }

            Spacer()

            Button {
                navigateMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(BrandColors.cardBackground)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Spacing.sm)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: Spacing.lg) {
            HStack(spacing: 0) {
                // Total Income
                VStack(spacing: Spacing.xs) {
                    Text("Income")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(CurrencyFormatter.format(totalIncome))
                        .font(Typography.moneySmall)
                        .foregroundStyle(BrandColors.success)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(BrandColors.textTertiary.opacity(0.2))
                    .frame(width: 1, height: 40)

                // Total Expenses
                VStack(spacing: Spacing.xs) {
                    Text("Expenses")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(CurrencyFormatter.format(totalExpenses))
                        .font(Typography.moneySmall)
                        .foregroundStyle(BrandColors.destructive)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(BrandColors.textTertiary.opacity(0.2))
                    .frame(width: 1, height: 40)

                // Surplus/Deficit
                VStack(spacing: Spacing.xs) {
                    Text(surplus >= 0 ? "Surplus" : "Deficit")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(CurrencyFormatter.format(abs(surplus)))
                        .font(Typography.moneySmall)
                        .foregroundStyle(surplus >= 0 ? BrandColors.success : BrandColors.destructive)
                }
                .frame(maxWidth: .infinity)
            }

            // Visual split bar
            if totalIncome > 0 || totalExpenses > 0 {
                let total = max(totalIncome, totalExpenses)
                let incomeRatio = total > 0 ? totalIncome / total : 0.5
                let expenseRatio = total > 0 ? totalExpenses / total : 0.5

                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrandColors.success)
                            .frame(width: max(geo.size.width * incomeRatio - 1, 0))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrandColors.destructive)
                            .frame(width: max(geo.size.width * expenseRatio - 1, 0))
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(Spacing.lg)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
    }

    // MARK: - Income Section

    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(BrandColors.success)
                Text("Income")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Text(CurrencyFormatter.format(totalIncome))
                    .font(Typography.moneyCaption)
                    .foregroundStyle(BrandColors.success)
            }
            .padding(.horizontal, Spacing.lg)

            VStack(spacing: 0) {
                // Gig Income (auto-calculated, not editable)
                HStack {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.primary)
                            .frame(width: 28, height: 28)
                            .background(BrandColors.primary.opacity(0.1))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Gig Income")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(BrandColors.textPrimary)
                            Text("After platform fees")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Text(CurrencyFormatter.format(gigIncomeForMonth))
                            .font(Typography.moneyCaption)
                            .foregroundStyle(BrandColors.textPrimary)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
                .padding(Spacing.lg)

                if !incomeItems.isEmpty {
                    Divider()
                        .padding(.leading, Spacing.lg + 28 + Spacing.md)
                }

                // Other Income items (editable)
                ForEach(incomeItems) { item in
                    budgetItemRow(item)

                    if item.id != incomeItems.last?.id {
                        Divider()
                            .padding(.leading, Spacing.lg + 28 + Spacing.md)
                    }
                }

                // Add Other Income button
                Divider()
                    .padding(.leading, Spacing.lg + 28 + Spacing.md)

                Button {
                    HapticManager.shared.tap()
                    showingAddItem = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.primary)
                            .frame(width: 28, height: 28)

                        Text("Add Other Income")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.primary)

                        Spacer()
                    }
                    .padding(Spacing.lg)
                }
            }
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
        }
    }

    // MARK: - Expenses Section

    private var expensesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(BrandColors.destructive)
                Text("Expenses")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Text(CurrencyFormatter.format(totalExpenses))
                    .font(Typography.moneyCaption)
                    .foregroundStyle(BrandColors.destructive)
            }
            .padding(.horizontal, Spacing.lg)

            VStack(spacing: 0) {
                // Gig Expenses (auto-calculated)
                if gigExpensesForMonth > 0 {
                    HStack {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "briefcase.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(BrandColors.warning)
                                .frame(width: 28, height: 28)
                                .background(BrandColors.warning.opacity(0.1))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Gig Expenses")
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(BrandColors.textPrimary)
                                Text("From expense tracker")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                        }

                        Spacer()

                        HStack(spacing: Spacing.xs) {
                            Text(CurrencyFormatter.format(gigExpensesForMonth))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(BrandColors.textPrimary)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                    .padding(Spacing.lg)

                    if !fixedExpenses.isEmpty || !variableExpenses.isEmpty {
                        Divider()
                            .padding(.leading, Spacing.lg + 28 + Spacing.md)
                    }
                }

                // Fixed Expenses header
                if !fixedExpenses.isEmpty {
                    HStack {
                        Text("FIXED")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BrandColors.textTertiary)
                        Spacer()
                        Text(CurrencyFormatter.format(totalFixedExpenses))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(BrandColors.groupedBackground.opacity(0.5))
                }

                ForEach(fixedExpenses) { item in
                    budgetItemRow(item)

                    if item.id != fixedExpenses.last?.id {
                        Divider()
                            .padding(.leading, Spacing.lg + 28 + Spacing.md)
                    }
                }

                // Variable Expenses header
                if !variableExpenses.isEmpty {
                    if !fixedExpenses.isEmpty {
                        Divider()
                    }
                    HStack {
                        Text("VARIABLE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BrandColors.textTertiary)
                        Spacer()
                        Text(CurrencyFormatter.format(totalVariableExpenses))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(BrandColors.groupedBackground.opacity(0.5))
                }

                ForEach(variableExpenses) { item in
                    budgetItemRow(item)

                    if item.id != variableExpenses.last?.id {
                        Divider()
                            .padding(.leading, Spacing.lg + 28 + Spacing.md)
                    }
                }

                // Add Expense button
                Divider()
                    .padding(.leading, Spacing.lg + 28 + Spacing.md)

                Button {
                    HapticManager.shared.tap()
                    showingAddItem = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.primary)
                            .frame(width: 28, height: 28)

                        Text("Add Budget Item")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.primary)

                        Spacer()
                    }
                    .padding(Spacing.lg)
                }
            }
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
        }
    }

    // MARK: - Bottom Line Card

    private var bottomLineCard: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Monthly Bottom Line")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text(surplus >= 0
                         ? "You have money left over this month"
                         : "You're spending more than you earn")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: surplus >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(surplus >= 0 ? BrandColors.success : BrandColors.destructive)

                Text(surplus >= 0 ? "+" : "-")
                    .font(Typography.moneyLarge)
                    .foregroundStyle(surplus >= 0 ? BrandColors.success : BrandColors.destructive)
                + Text(CurrencyFormatter.format(abs(surplus)).replacingOccurrences(of: "$", with: ""))
                    .font(Typography.moneyLarge)
                    .foregroundStyle(surplus >= 0 ? BrandColors.success : BrandColors.destructive)

                Spacer()
            }

            // Breakdown summary
            VStack(spacing: Spacing.xs) {
                breakdownRow(label: "Gig Income (net)", amount: gigIncomeForMonth, isIncome: true)
                breakdownRow(label: "Other Income", amount: totalOtherIncome, isIncome: true)
                breakdownRow(label: "Gig Expenses", amount: gigExpensesForMonth, isIncome: false)
                breakdownRow(label: "Fixed Expenses", amount: totalFixedExpenses, isIncome: false)
                breakdownRow(label: "Variable Expenses", amount: totalVariableExpenses, isIncome: false)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                .fill(BrandColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                        .stroke(
                            surplus >= 0 ? BrandColors.success.opacity(0.3) : BrandColors.destructive.opacity(0.3),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
    }

    // MARK: - Reusable Row Components

    @ViewBuilder
    private func budgetItemRow(_ item: BudgetItem) -> some View {
        Button {
            HapticManager.shared.tap()
            editingItem = item
        } label: {
            HStack {
                HStack(spacing: Spacing.md) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.primary)
                        .frame(width: 28, height: 28)
                        .background(BrandColors.primary.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(item.name)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.textPrimary)
                        Text(item.category.rawValue)
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                Spacer()

                Text(CurrencyFormatter.format(item.amount))
                    .font(Typography.moneyCaption)
                    .foregroundStyle(BrandColors.textPrimary)
            }
            .padding(Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation {
                    modelContext.delete(item)
                    HapticManager.shared.warning()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func breakdownRow(label: String, amount: Double, isIncome: Bool) -> some View {
        if amount > 0 {
            HStack {
                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                Spacer()
                Text("\(isIncome ? "+" : "-")\(CurrencyFormatter.format(amount))")
                    .font(Typography.moneyCaption)
                    .foregroundStyle(isIncome ? BrandColors.success : BrandColors.textSecondary)
            }
        }
    }
}
