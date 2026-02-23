import SwiftUI
import SwiftData

struct AddBudgetItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let monthYear: String
    var editingItem: BudgetItem?

    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var selectedCategory: BudgetCategory = .other
    @State private var selectedType: BudgetItemType = .expense
    @State private var isFixed: Bool = true

    private var isEditing: Bool { editingItem != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Double(amount) ?? 0) > 0
    }

    // Categories filtered by type
    private var availableCategories: [BudgetCategory] {
        if selectedType == .income {
            return [.otherIncome]
        } else {
            return BudgetCategory.allCases.filter { $0 != .otherIncome }
        }
    }

    init(monthYear: String, editingItem: BudgetItem? = nil) {
        self.monthYear = monthYear
        self.editingItem = editingItem
    }

    var body: some View {
        Form {
            // Type picker
            Section {
                Picker("Type", selection: $selectedType) {
                    Text("Expense").tag(BudgetItemType.expense)
                    Text("Income").tag(BudgetItemType.income)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .onChange(of: selectedType) { _, newType in
                    if newType == .income {
                        selectedCategory = .otherIncome
                        isFixed = true
                    } else {
                        if selectedCategory == .otherIncome {
                            selectedCategory = .other
                        }
                    }
                    HapticManager.shared.select()
                }
            }

            // Details
            Section("Details") {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundStyle(BrandColors.primary)
                        .frame(width: 24)
                    TextField("Name (e.g. Rent, Car Payment)", text: $name)
                }

                HStack {
                    Image(systemName: "dollarsign.circle")
                        .foregroundStyle(BrandColors.primary)
                        .frame(width: 24)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }
            }

            // Category
            if selectedType == .expense {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(availableCategories) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                // Fixed / Variable toggle
                Section {
                    Picker("Expense Type", selection: $isFixed) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12))
                            Text("Fixed")
                        }
                        .tag(true)

                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12))
                            Text("Variable")
                        }
                        .tag(false)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Expense Type")
                } footer: {
                    Text(isFixed
                         ? "Fixed expenses stay the same each month (rent, car payment, insurance)"
                         : "Variable expenses change month to month (groceries, gas, entertainment)")
                }
            }

            // Month
            Section {
                HStack {
                    Label("Month", systemImage: "calendar")
                    Spacer()
                    Text(BudgetItem.displayName(for: monthYear))
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            // Quick presets (for expenses only, when name is empty)
            if selectedType == .expense && name.isEmpty && !isEditing {
                Section("Quick Add") {
                    ForEach(quickPresets, id: \.name) { preset in
                        Button {
                            name = preset.name
                            selectedCategory = preset.category
                            isFixed = preset.isFixed
                            HapticManager.shared.select()
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: preset.category.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(BrandColors.primary)
                                    .frame(width: 24)

                                Text(preset.name)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                Spacer()

                                Text(preset.isFixed ? "Fixed" : "Variable")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .tint(BrandColors.primary)
        .navigationTitle(isEditing ? "Edit Item" : "Add Budget Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Save" : "Add") {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let item = editingItem {
                name = item.name
                amount = String(format: "%.2f", item.amount)
                selectedCategory = item.category
                selectedType = item.type
                isFixed = item.isFixed
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard let amountValue = Double(amount), amountValue > 0 else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let item = editingItem {
            // Update existing
            item.name = trimmedName
            item.amount = amountValue
            item.category = selectedCategory
            item.type = selectedType
            item.isFixed = selectedType == .income ? true : isFixed
            item.updatedAt = .now
        } else {
            // Create new
            let item = BudgetItem(
                name: trimmedName,
                amount: amountValue,
                category: selectedType == .income ? .otherIncome : selectedCategory,
                type: selectedType,
                isFixed: selectedType == .income ? true : isFixed,
                monthYear: monthYear
            )
            modelContext.insert(item)
        }

        HapticManager.shared.success()
        dismiss()
    }

    // MARK: - Quick Presets

    private struct QuickPreset {
        let name: String
        let category: BudgetCategory
        let isFixed: Bool
    }

    private let quickPresets: [QuickPreset] = [
        QuickPreset(name: "Rent / Mortgage", category: .housing, isFixed: true),
        QuickPreset(name: "Car Payment", category: .transportation, isFixed: true),
        QuickPreset(name: "Car Insurance", category: .insurance, isFixed: true),
        QuickPreset(name: "Health Insurance", category: .insurance, isFixed: true),
        QuickPreset(name: "Phone Bill", category: .utilities, isFixed: true),
        QuickPreset(name: "Internet", category: .utilities, isFixed: true),
        QuickPreset(name: "Groceries", category: .food, isFixed: false),
        QuickPreset(name: "Gas", category: .transportation, isFixed: false),
        QuickPreset(name: "Streaming Services", category: .subscriptions, isFixed: true),
        QuickPreset(name: "Gym Membership", category: .personal, isFixed: true),
        QuickPreset(name: "Student Loans", category: .debt, isFixed: true),
        QuickPreset(name: "Credit Card Payment", category: .debt, isFixed: false),
        QuickPreset(name: "Savings Transfer", category: .savings, isFixed: true),
    ]
}
