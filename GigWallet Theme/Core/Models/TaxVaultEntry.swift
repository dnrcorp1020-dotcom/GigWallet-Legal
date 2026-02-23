import SwiftData
import Foundation

/// Tracks money mentally "set aside" for taxes.
/// This is NOT a real bank account — it's a psychological commitment tracker
/// that helps gig workers visualize what they should save for quarterly payments.
@Model
final class TaxVaultEntry {
    var id: UUID = UUID()
    var amount: Double = 0
    var typeRawValue: String = TaxVaultEntryType.setAside.rawValue
    var note: String = ""
    var entryDate: Date = Date.now
    var taxYear: Int = 2026
    var createdAt: Date = Date.now

    var type: TaxVaultEntryType {
        get { TaxVaultEntryType(rawValue: typeRawValue) ?? .setAside }
        set { typeRawValue = newValue.rawValue }
    }

    init(
        amount: Double,
        type: TaxVaultEntryType = .setAside,
        note: String = "",
        taxYear: Int = DateHelper.currentTaxYear
    ) {
        self.id = UUID()
        self.amount = amount
        self.typeRawValue = type.rawValue
        self.note = note
        self.entryDate = .now
        self.taxYear = taxYear
        self.createdAt = .now
    }
}

/// Types of Tax Vault ledger entries.
enum TaxVaultEntryType: String, Codable, CaseIterable, Identifiable {
    case setAside = "Set Aside"          // User marks money as reserved for taxes
    case taxPayment = "Tax Payment"       // Linked to actual IRS/state payment
    case adjustment = "Adjustment"        // Manual correction

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .setAside: return "arrow.up.circle.fill"
        case .taxPayment: return "arrow.down.circle.fill"
        case .adjustment: return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .setAside: return BrandColors.success
        case .taxPayment: return BrandColors.destructive
        case .adjustment: return BrandColors.info
        }
    }

    /// Whether this entry type adds to the vault (positive) or subtracts (negative).
    var isCredit: Bool {
        switch self {
        case .setAside: return true
        case .taxPayment: return false
        case .adjustment: return true // Could be either, but tracked as positive
        }
    }
}

import SwiftUI
