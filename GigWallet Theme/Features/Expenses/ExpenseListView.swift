import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseEntry.expenseDate, order: .reverse) private var expenses: [ExpenseEntry]
    @State private var showingAddExpense = false
    @State private var expenseToEdit: ExpenseEntry?

    private var groupedByCategory: [(ExpenseCategory, [ExpenseEntry])] {
        let grouped = Dictionary(grouping: expenses) { $0.category }
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.1.reduce(0) { $0 + $1.amount } > $1.1.reduce(0) { $0 + $1.amount } }
    }

    private var totalMonthlyExpenses: Double {
        let startOfMonth = Date.now.startOfMonth
        return expenses
            .filter { $0.expenseDate >= startOfMonth }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalDeductible: Double {
        let startOfMonth = Date.now.startOfMonth
        return expenses
            .filter { $0.expenseDate >= startOfMonth }
            .reduce(0) { $0 + $1.deductibleAmount }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: Spacing.xxl) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Total Expenses")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text(CurrencyFormatter.format(totalMonthlyExpenses))
                            .font(Typography.moneyMedium)
                            .foregroundStyle(BrandColors.destructive)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Deductible")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text(CurrencyFormatter.format(totalDeductible))
                            .font(Typography.moneyMedium)
                            .foregroundStyle(BrandColors.success)
                    }
                }
                .listRowBackground(BrandColors.cardBackground)
            }

            if expenses.isEmpty {
                Section {
                    GWEmptyState(
                        icon: "creditcard",
                        title: "No Expenses Yet",
                        message: "Track business expenses to maximize your deductions.",
                        buttonTitle: "Add Expense"
                    ) {
                        showingAddExpense = true
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(expenses) { expense in
                    ExpenseRowView(expense: expense)
                        .swipeActions(edge: .leading) {
                            Button {
                                expenseToEdit = expense
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(BrandColors.info)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(expense)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            expenseToEdit = expense
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .gwNavigationTitle("Write-", accent: "Offs", icon: "creditcard.fill")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddExpense = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(BrandColors.primary)
                }
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            NavigationStack {
                AddExpenseView()
            }
        }
        .sheet(item: $expenseToEdit) { expense in
            NavigationStack {
                EditExpenseView(expense: expense)
            }
        }
    }
}
