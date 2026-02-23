import SwiftData
import Foundation

/// Tracks actual quarterly tax payments made to the IRS and state.
/// This is the critical gap: the app tells you what to pay, but never tracks IF you paid.
/// Without this, gig workers think they're compliant when they're actually accumulating penalties.
@Model
final class TaxPayment {
    var id: UUID = UUID()
    var taxYear: Int = 2026
    var quarterRawValue: String = TaxQuarter.q1.rawValue
    var amount: Double = 0
    var paymentDate: Date = Date.now
    var paymentTypeRawValue: String = PaymentType.federal.rawValue
    var confirmationNumber: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    init(
        taxYear: Int,
        quarter: TaxQuarter,
        amount: Double,
        paymentDate: Date = .now,
        paymentType: PaymentType = .federal,
        confirmationNumber: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.taxYear = taxYear
        self.quarterRawValue = quarter.rawValue
        self.amount = amount
        self.paymentDate = paymentDate
        self.paymentTypeRawValue = paymentType.rawValue
        self.confirmationNumber = confirmationNumber
        self.notes = notes
        self.createdAt = .now
    }

    var quarter: TaxQuarter {
        get { TaxQuarter(rawValue: quarterRawValue) ?? .q1 }
        set { quarterRawValue = newValue.rawValue }
    }

    var paymentType: PaymentType {
        get { PaymentType(rawValue: paymentTypeRawValue) ?? .federal }
        set { paymentTypeRawValue = newValue.rawValue }
    }
}

enum PaymentType: String, Codable, CaseIterable, Identifiable {
    case federal = "Federal"
    case state = "State"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .federal: return "building.columns.fill"
        case .state: return "map.fill"
        }
    }
}
