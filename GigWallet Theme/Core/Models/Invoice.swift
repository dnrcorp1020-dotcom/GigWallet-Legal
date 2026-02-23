import SwiftData
import Foundation

/// A professional invoice for freelance gig work.
/// PDF invoicing included as a premium feature.
@Model
final class Invoice {
    var id: UUID = UUID()
    var invoiceNumber: String = ""
    var clientName: String = ""
    var clientEmail: String = ""
    var clientAddress: String = ""

    var issueDate: Date = Date.now
    var dueDate: Date = Date.now

    /// JSON-encoded array of InvoiceLineItem
    var lineItemsJSON: String = "[]"

    var subtotal: Double = 0
    var taxRate: Double = 0 // e.g. 0.0825 for 8.25%
    var taxAmount: Double = 0
    var total: Double = 0

    var notes: String = ""
    var statusRawValue: String = InvoiceStatus.draft.rawValue
    var platformRawValue: String = GigPlatformType.other.rawValue

    /// Cached PDF data for sharing
    var pdfData: Data?

    var taxYear: Int = 2026
    var createdAt: Date = Date.now

    init(
        invoiceNumber: String,
        clientName: String,
        clientEmail: String = "",
        clientAddress: String = "",
        issueDate: Date = .now,
        dueDate: Date? = nil,
        lineItems: [InvoiceLineItem] = [],
        taxRate: Double = 0,
        notes: String = "",
        platform: GigPlatformType = .other
    ) {
        self.id = UUID()
        self.invoiceNumber = invoiceNumber
        self.clientName = clientName
        self.clientEmail = clientEmail
        self.clientAddress = clientAddress
        self.issueDate = issueDate
        self.dueDate = dueDate ?? Calendar.current.date(byAdding: .day, value: 30, to: issueDate) ?? issueDate
        self.taxRate = taxRate
        self.notes = notes
        self.platformRawValue = platform.rawValue
        self.statusRawValue = InvoiceStatus.draft.rawValue
        self.taxYear = issueDate.taxYear
        self.createdAt = .now

        // Encode line items
        if let data = try? JSONEncoder().encode(lineItems),
           let json = String(data: data, encoding: .utf8) {
            self.lineItemsJSON = json
        }

        recalculateTotals()
    }

    // MARK: - Computed Properties

    var status: InvoiceStatus {
        get { InvoiceStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }

    var platform: GigPlatformType {
        get { GigPlatformType(rawValue: platformRawValue) ?? .other }
        set { platformRawValue = newValue.rawValue }
    }

    var lineItems: [InvoiceLineItem] {
        get {
            guard let data = lineItemsJSON.data(using: .utf8),
                  let items = try? JSONDecoder().decode([InvoiceLineItem].self, from: data) else {
                return []
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                lineItemsJSON = json
            }
            recalculateTotals()
        }
    }

    var isOverdue: Bool {
        status == .sent && dueDate < .now
    }

    // MARK: - Methods

    func recalculateTotals() {
        subtotal = lineItems.reduce(0) { $0 + $1.total }
        taxAmount = subtotal * taxRate
        total = subtotal + taxAmount
    }
}

// MARK: - Invoice Line Item

struct InvoiceLineItem: Codable, Identifiable {
    let id: UUID
    var description: String
    var quantity: Double
    var rate: Double

    var total: Double { quantity * rate }

    init(description: String = "", quantity: Double = 1, rate: Double = 0) {
        self.id = UUID()
        self.description = description
        self.quantity = quantity
        self.rate = rate
    }
}

// MARK: - Invoice Status

enum InvoiceStatus: String, CaseIterable {
    case draft = "Draft"
    case sent = "Sent"
    case paid = "Paid"
    case overdue = "Overdue"

    var sfSymbol: String {
        switch self {
        case .draft: return "doc.fill"
        case .sent: return "paperplane.fill"
        case .paid: return "checkmark.circle.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .draft: return BrandColors.textTertiary
        case .sent: return BrandColors.info
        case .paid: return BrandColors.success
        case .overdue: return BrandColors.destructive
        }
    }
}

import SwiftUI
