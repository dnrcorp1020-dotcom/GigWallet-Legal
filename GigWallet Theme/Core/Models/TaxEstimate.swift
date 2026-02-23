import SwiftData
import Foundation

@Model
final class TaxEstimate {
    var id: UUID = UUID()
    var taxYear: Int = 2026
    var quarterRawValue: String = TaxQuarter.q1.rawValue
    var grossIncome: Double = 0
    var totalDeductions: Double = 0
    var netSelfEmploymentIncome: Double = 0
    var selfEmploymentTax: Double = 0
    var federalIncomeTax: Double = 0
    var stateIncomeTax: Double = 0
    var totalEstimatedTax: Double = 0
    var quarterlyPaymentDue: Double = 0
    var effectiveTaxRate: Double = 0
    var calculatedAt: Date = Date.now

    init(
        taxYear: Int = 2026,
        quarter: TaxQuarter = .q1,
        grossIncome: Double = 0,
        totalDeductions: Double = 0,
        netSelfEmploymentIncome: Double = 0,
        selfEmploymentTax: Double = 0,
        federalIncomeTax: Double = 0,
        stateIncomeTax: Double = 0,
        totalEstimatedTax: Double = 0,
        quarterlyPaymentDue: Double = 0,
        effectiveTaxRate: Double = 0
    ) {
        self.id = UUID()
        self.taxYear = taxYear
        self.quarterRawValue = quarter.rawValue
        self.grossIncome = grossIncome
        self.totalDeductions = totalDeductions
        self.netSelfEmploymentIncome = netSelfEmploymentIncome
        self.selfEmploymentTax = selfEmploymentTax
        self.federalIncomeTax = federalIncomeTax
        self.stateIncomeTax = stateIncomeTax
        self.totalEstimatedTax = totalEstimatedTax
        self.quarterlyPaymentDue = quarterlyPaymentDue
        self.effectiveTaxRate = effectiveTaxRate
        self.calculatedAt = .now
    }

    var quarter: TaxQuarter {
        get { TaxQuarter(rawValue: quarterRawValue) ?? .q1 }
        set { quarterRawValue = newValue.rawValue }
    }
}

enum TaxQuarter: String, Codable, CaseIterable, Identifiable {
    case q1 = "Q1"
    case q2 = "Q2"
    case q3 = "Q3"
    case q4 = "Q4"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .q1: return "Q1 (Jan-Mar)"
        case .q2: return "Q2 (Apr-Jun)"
        case .q3: return "Q3 (Jul-Sep)"
        case .q4: return "Q4 (Oct-Dec)"
        }
    }

    var shortName: String { rawValue }

    var months: String {
        switch self {
        case .q1: return "Jan - Mar"
        case .q2: return "Apr - Jun"
        case .q3: return "Jul - Sep"
        case .q4: return "Oct - Dec"
        }
    }

    var dueDescription: String {
        switch self {
        case .q1: return "Due April 15"
        case .q2: return "Due June 15"
        case .q3: return "Due September 15"
        case .q4: return "Due January 15"
        }
    }

    var dueDateComponents: DateComponents {
        switch self {
        case .q1: return DateComponents(month: 4, day: 15)
        case .q2: return DateComponents(month: 6, day: 15)
        case .q3: return DateComponents(month: 9, day: 15)
        case .q4: return DateComponents(month: 1, day: 15)
        }
    }

    static var current: TaxQuarter {
        Date.now.taxQuarter
    }
}
