import SwiftData
import SwiftUI
import Foundation

@Model
final class ExpenseEntry {
    var id: UUID = UUID()
    var amount: Double = 0
    var categoryRawValue: String = ExpenseCategory.other.rawValue
    var vendor: String = ""
    var expenseDescription: String = ""
    var expenseDate: Date = Date.now
    var isDeductible: Bool = true
    var deductionPercentage: Double = 100
    var mileage: Double?
    var taxYear: Int = 2026
    var quarterRawValue: String = TaxQuarter.q1.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: - Receipt Photo Storage
    // Stored as raw JPEG data so it survives iCloud sync and device transfers
    // without any external file-system dependency.
    var receiptImageData: Data?

    /// `true` when a receipt photo has been attached to this expense.
    var hasReceipt: Bool { receiptImageData != nil }

    init(
        amount: Double,
        category: ExpenseCategory,
        vendor: String = "",
        description: String = "",
        expenseDate: Date = .now,
        isDeductible: Bool = true,
        deductionPercentage: Double = 100,
        mileage: Double? = nil,
        receiptImageData: Data? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.categoryRawValue = category.rawValue
        self.vendor = vendor
        self.expenseDescription = description
        self.expenseDate = expenseDate
        self.isDeductible = isDeductible
        self.deductionPercentage = deductionPercentage
        self.mileage = mileage
        self.receiptImageData = receiptImageData
        self.taxYear = expenseDate.taxYear
        self.quarterRawValue = expenseDate.taxQuarter.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var quarter: TaxQuarter {
        get { TaxQuarter(rawValue: quarterRawValue) ?? .q1 }
        set { quarterRawValue = newValue.rawValue }
    }

    var deductibleAmount: Double {
        guard isDeductible else { return 0 }
        let clampedPercentage = min(max(deductionPercentage, 0), 100)
        return max(amount, 0) * (clampedPercentage / 100)
    }
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case mileage = "Mileage"
    case gas = "Gas & Fuel"
    case vehicleMaintenance = "Vehicle Maintenance"
    case insurance = "Insurance"
    case phoneAndInternet = "Phone & Internet"
    case supplies = "Supplies"
    case equipment = "Equipment"
    case meals = "Meals (Business)"
    case homeOffice = "Home Office"
    case software = "Software & Apps"
    case advertising = "Advertising"
    case professionalServices = "Professional Services"
    case healthInsurance = "Health Insurance"
    case retirement = "Retirement Contributions"
    case parking = "Parking & Tolls"
    case other = "Other"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .mileage: return "car.fill"
        case .gas: return "fuelpump.fill"
        case .vehicleMaintenance: return "wrench.fill"
        case .insurance: return "shield.fill"
        case .phoneAndInternet: return "iphone"
        case .supplies: return "bag.fill"
        case .equipment: return "desktopcomputer"
        case .meals: return "fork.knife"
        case .homeOffice: return "house.fill"
        case .software: return "app.fill"
        case .advertising: return "megaphone.fill"
        case .professionalServices: return "person.crop.rectangle.fill"
        case .healthInsurance: return "heart.fill"
        case .retirement: return "banknote.fill"
        case .parking: return "parkingsign"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .mileage: return .teal
        case .gas: return .orange
        case .vehicleMaintenance: return .gray
        case .insurance: return .purple
        case .phoneAndInternet: return .cyan
        case .supplies: return .brown
        case .equipment: return .indigo
        case .meals: return .red
        case .homeOffice: return .green
        case .software: return .pink
        case .advertising: return .yellow
        case .professionalServices: return .teal
        case .healthInsurance: return Color(hex: "FF3B30")
        case .retirement: return Color(hex: "34C759")
        case .parking: return .mint
        case .other: return .secondary
        }
    }
}
