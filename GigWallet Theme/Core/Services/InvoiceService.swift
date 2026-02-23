import UIKit
import Foundation

/// Generates professional PDF invoices using UIGraphicsPDFRenderer.
/// US Letter size (612x792 points). Orange accent header with "INVOICE" title.
///
/// Included in GigWallet premium for freelance gig workers.
enum InvoiceService {

    // MARK: - PDF Generation

    /// Generate a professional PDF invoice.
    static func generatePDF(for invoice: Invoice, profile: UserProfileSnapshot) -> Data {
        let pageWidth: CGFloat = 612 // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()

            var yOffset: CGFloat = margin

            // ═══════════════════════════════════════════════
            // HEADER — Orange accent bar + INVOICE title
            // ═══════════════════════════════════════════════

            let accentColor = UIColor(red: 255/255, green: 107/255, blue: 53/255, alpha: 1) // #FF6B35
            let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 80)
            context.cgContext.setFillColor(accentColor.cgColor)
            context.cgContext.fill(headerRect)

            // "INVOICE" title
            let invoiceTitle = "INVOICE"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            invoiceTitle.draw(at: CGPoint(x: margin, y: 22), withAttributes: titleAttrs)

            // Invoice number on right side of header
            let numberAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            let numberStr = "#\(invoice.invoiceNumber)"
            let numberSize = numberStr.size(withAttributes: numberAttrs)
            numberStr.draw(at: CGPoint(x: pageWidth - margin - numberSize.width, y: 34), withAttributes: numberAttrs)

            yOffset = 100

            // ═══════════════════════════════════════════════
            // FROM / TO sections side by side
            // ═══════════════════════════════════════════════

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.gray
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            let boldValueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.black
            ]

            let halfWidth = contentWidth / 2

            // FROM (left)
            "FROM".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: labelAttrs)
            yOffset += 18
            profile.displayName.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: boldValueAttrs)
            yOffset += 16
            if !profile.email.isEmpty {
                profile.email.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: valueAttrs)
            }

            // TO (right, same row)
            var toY = yOffset - 34
            "BILL TO".draw(at: CGPoint(x: margin + halfWidth, y: toY), withAttributes: labelAttrs)
            toY += 18
            invoice.clientName.draw(at: CGPoint(x: margin + halfWidth, y: toY), withAttributes: boldValueAttrs)
            toY += 16
            if !invoice.clientEmail.isEmpty {
                invoice.clientEmail.draw(at: CGPoint(x: margin + halfWidth, y: toY), withAttributes: valueAttrs)
                toY += 14
            }
            if !invoice.clientAddress.isEmpty {
                let addressRect = CGRect(x: margin + halfWidth, y: toY, width: halfWidth - 10, height: 40)
                invoice.clientAddress.draw(in: addressRect, withAttributes: valueAttrs)
            }

            yOffset += 30

            // Dates
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium

            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.gray
            ]
            let dateValueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.black
            ]

            yOffset += 10
            "Issue Date".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: dateAttrs)
            "Due Date".draw(at: CGPoint(x: margin + 150, y: yOffset), withAttributes: dateAttrs)
            yOffset += 14
            dateFormatter.string(from: invoice.issueDate).draw(at: CGPoint(x: margin, y: yOffset), withAttributes: dateValueAttrs)
            dateFormatter.string(from: invoice.dueDate).draw(at: CGPoint(x: margin + 150, y: yOffset), withAttributes: dateValueAttrs)

            yOffset += 30

            // ═══════════════════════════════════════════════
            // LINE ITEMS TABLE
            // ═══════════════════════════════════════════════

            // Table header
            let tableHeaderRect = CGRect(x: margin, y: yOffset, width: contentWidth, height: 25)
            context.cgContext.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
            context.cgContext.fill(tableHeaderRect)

            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.darkGray
            ]

            let colDescription: CGFloat = margin + 8
            let colQty: CGFloat = margin + contentWidth * 0.55
            let colRate: CGFloat = margin + contentWidth * 0.70
            let colTotal: CGFloat = margin + contentWidth * 0.85

            "DESCRIPTION".draw(at: CGPoint(x: colDescription, y: yOffset + 6), withAttributes: headerAttrs)
            "QTY".draw(at: CGPoint(x: colQty, y: yOffset + 6), withAttributes: headerAttrs)
            "RATE".draw(at: CGPoint(x: colRate, y: yOffset + 6), withAttributes: headerAttrs)
            "TOTAL".draw(at: CGPoint(x: colTotal, y: yOffset + 6), withAttributes: headerAttrs)

            yOffset += 30

            // Line items
            let rowAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.black
            ]

            for item in invoice.lineItems {
                item.description.draw(at: CGPoint(x: colDescription, y: yOffset), withAttributes: rowAttrs)
                formatNumber(item.quantity).draw(at: CGPoint(x: colQty, y: yOffset), withAttributes: rowAttrs)
                formatCurrency(item.rate).draw(at: CGPoint(x: colRate, y: yOffset), withAttributes: rowAttrs)
                formatCurrency(item.total).draw(at: CGPoint(x: colTotal, y: yOffset), withAttributes: rowAttrs)

                yOffset += 22

                // Separator line
                context.cgContext.setStrokeColor(UIColor(white: 0.9, alpha: 1).cgColor)
                context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: margin, y: yOffset))
                context.cgContext.addLine(to: CGPoint(x: margin + contentWidth, y: yOffset))
                context.cgContext.strokePath()

                yOffset += 5
            }

            yOffset += 15

            // ═══════════════════════════════════════════════
            // TOTALS
            // ═══════════════════════════════════════════════

            let totalsX = margin + contentWidth * 0.55
            let totalsValueX = margin + contentWidth * 0.85

            let subtotalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            let totalLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let totalValueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: accentColor
            ]

            // Subtotal
            "Subtotal".draw(at: CGPoint(x: totalsX, y: yOffset), withAttributes: subtotalAttrs)
            formatCurrency(invoice.subtotal).draw(at: CGPoint(x: totalsValueX, y: yOffset), withAttributes: subtotalAttrs)
            yOffset += 20

            // Tax (if applicable)
            if invoice.taxRate > 0 {
                let taxLabel = "Tax (\(String(format: "%.1f", invoice.taxRate * 100))%)"
                taxLabel.draw(at: CGPoint(x: totalsX, y: yOffset), withAttributes: subtotalAttrs)
                formatCurrency(invoice.taxAmount).draw(at: CGPoint(x: totalsValueX, y: yOffset), withAttributes: subtotalAttrs)
                yOffset += 20
            }

            // Separator
            context.cgContext.setStrokeColor(accentColor.cgColor)
            context.cgContext.setLineWidth(1.5)
            context.cgContext.move(to: CGPoint(x: totalsX, y: yOffset))
            context.cgContext.addLine(to: CGPoint(x: margin + contentWidth, y: yOffset))
            context.cgContext.strokePath()
            yOffset += 8

            // Total
            "TOTAL".draw(at: CGPoint(x: totalsX, y: yOffset), withAttributes: totalLabelAttrs)
            formatCurrency(invoice.total).draw(at: CGPoint(x: totalsValueX, y: yOffset), withAttributes: totalValueAttrs)
            yOffset += 35

            // ═══════════════════════════════════════════════
            // NOTES
            // ═══════════════════════════════════════════════

            if !invoice.notes.isEmpty {
                "NOTES".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: labelAttrs)
                yOffset += 16
                let notesRect = CGRect(x: margin, y: yOffset, width: contentWidth, height: 60)
                invoice.notes.draw(in: notesRect, withAttributes: valueAttrs)
                yOffset += 65
            }

            // ═══════════════════════════════════════════════
            // FOOTER
            // ═══════════════════════════════════════════════

            let footerY = pageHeight - margin - 20
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.lightGray
            ]
            let footerText = "Generated by GigWallet"
            let footerSize = footerText.size(withAttributes: footerAttrs)
            footerText.draw(
                at: CGPoint(x: (pageWidth - footerSize.width) / 2, y: footerY),
                withAttributes: footerAttrs
            )
        }

        return data
    }

    // MARK: - Invoice Number Generation

    /// Generate the next sequential invoice number.
    /// Format: INV-YYYY-NNN (e.g., INV-2026-001)
    static func nextInvoiceNumber(existingInvoices: [Invoice]) -> String {
        let year = Calendar.current.component(.year, from: .now)
        let prefix = "INV-\(year)-"

        let maxNumber = existingInvoices
            .filter { $0.invoiceNumber.hasPrefix(prefix) }
            .compactMap { inv -> Int? in
                let suffix = inv.invoiceNumber.replacingOccurrences(of: prefix, with: "")
                return Int(suffix)
            }
            .max() ?? 0

        return String(format: "%@%03d", prefix, maxNumber + 1)
    }

    // MARK: - Helpers

    /// Snapshot of UserProfile data needed for PDF generation.
    /// Avoids passing SwiftData model across isolation boundaries.
    struct UserProfileSnapshot {
        let displayName: String
        let email: String
    }

    private static func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
