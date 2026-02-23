import SwiftData
import Foundation

@Model
final class IncomeEntry {
    var id: UUID = UUID()
    var amount: Double = 0
    var tips: Double = 0
    var platformFees: Double = 0
    var platformRawValue: String = GigPlatformType.other.rawValue
    var entryMethodRawValue: String = EntryMethod.manual.rawValue
    var entryDate: Date = Date.now
    var notes: String = ""
    var taxYear: Int = 2026
    var quarterRawValue: String = TaxQuarter.q1.rawValue
    /// State where this income was earned. nil = use profile default stateCode.
    var stateCode: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        amount: Double,
        tips: Double = 0,
        platformFees: Double = 0,
        platform: GigPlatformType,
        entryMethod: EntryMethod = .manual,
        entryDate: Date = .now,
        notes: String = "",
        stateCode: String? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.tips = tips
        self.platformFees = platformFees
        self.platformRawValue = platform.rawValue
        self.entryMethodRawValue = entryMethod.rawValue
        self.entryDate = entryDate
        self.notes = notes
        self.stateCode = stateCode
        self.taxYear = entryDate.taxYear
        self.quarterRawValue = entryDate.taxQuarter.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var platform: GigPlatformType {
        get { GigPlatformType(rawValue: platformRawValue) ?? .other }
        set { platformRawValue = newValue.rawValue }
    }

    var entryMethod: EntryMethod {
        get { EntryMethod(rawValue: entryMethodRawValue) ?? .manual }
        set { entryMethodRawValue = newValue.rawValue }
    }

    var quarter: TaxQuarter {
        get { TaxQuarter(rawValue: quarterRawValue) ?? .q1 }
        set { quarterRawValue = newValue.rawValue }
    }

    var grossAmount: Double {
        amount + tips
    }

    var netAmount: Double {
        grossAmount - platformFees
    }
}
