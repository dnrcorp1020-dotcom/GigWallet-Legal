import SwiftData
import Foundation

/// A monthly budget line item — either an income source or an expense.
/// Used by the Financial Planner to track the user's full monthly financial picture.
@Model
final class BudgetItem {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var categoryRawValue: String = BudgetCategory.other.rawValue
    var typeRawValue: String = BudgetItemType.expense.rawValue
    var isFixed: Bool = true
    /// Format: "2026-02" — ties this item to a specific month
    var monthYear: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        name: String,
        amount: Double,
        category: BudgetCategory,
        type: BudgetItemType,
        isFixed: Bool = true,
        monthYear: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.categoryRawValue = category.rawValue
        self.typeRawValue = type.rawValue
        self.isFixed = isFixed
        self.monthYear = monthYear ?? Self.currentMonthYear
        self.createdAt = .now
        self.updatedAt = .now
    }

    // MARK: - Computed Properties

    var category: BudgetCategory {
        get { BudgetCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var type: BudgetItemType {
        get { BudgetItemType(rawValue: typeRawValue) ?? .expense }
        set { typeRawValue = newValue.rawValue }
    }

    // MARK: - Helpers

    static var currentMonthYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: .now)
    }

    static func monthYear(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func displayName(for monthYear: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: monthYear) else { return monthYear }
        let display = DateFormatter()
        display.dateFormat = "MMMM yyyy"
        return display.string(from: date)
    }
}

// MARK: - Budget Category

enum BudgetCategory: String, CaseIterable, Codable, Identifiable {
    case housing = "Housing"
    case transportation = "Transportation"
    case food = "Food & Groceries"
    case utilities = "Utilities"
    case insurance = "Insurance"
    case subscriptions = "Subscriptions"
    case personal = "Personal"
    case savings = "Savings"
    case debt = "Debt Payments"
    case other = "Other"
    // Income categories
    case otherIncome = "Other Income"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .housing: return "house.fill"
        case .transportation: return "car.fill"
        case .food: return "cart.fill"
        case .utilities: return "bolt.fill"
        case .insurance: return "shield.checkered"
        case .subscriptions: return "repeat"
        case .personal: return "person.fill"
        case .savings: return "banknote.fill"
        case .debt: return "creditcard.fill"
        case .other: return "ellipsis.circle.fill"
        case .otherIncome: return "dollarsign.circle.fill"
        }
    }
}

// MARK: - Budget Item Type

enum BudgetItemType: String, Codable {
    case income = "Income"
    case expense = "Expense"
}
