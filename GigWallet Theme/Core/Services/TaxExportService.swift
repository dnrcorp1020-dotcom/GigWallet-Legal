import Foundation
import SwiftUI

/// Generates tax export files for Schedule C, TurboTax (.txf), and CSV formats
/// This is a premium feature that drives subscriptions
enum TaxExportService {

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV Spreadsheet"
        case txf = "TurboTax (TXF)"
        case scheduleC = "Schedule C Summary"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .txf: return "txf"
            case .scheduleC: return "txt"
            }
        }

        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .txf: return "doc.text.fill"
            case .scheduleC: return "building.columns.fill"
            }
        }

        var description: String {
            switch self {
            case .csv: return "Import into Excel, Google Sheets, or any spreadsheet"
            case .txf: return "Direct import into TurboTax, H&R Block, TaxAct"
            case .scheduleC: return "Pre-filled Schedule C summary for your tax preparer"
            }
        }
    }

    struct TaxExportData {
        let taxYear: Int
        let filingStatus: FilingStatus
        let income: [IncomeEntry]
        let expenses: [ExpenseEntry]
        let mileageTrips: [MileageTrip]

        var totalGrossIncome: Double {
            income.reduce(0) { $0 + $1.grossAmount }
        }

        var totalFees: Double {
            income.reduce(0) { $0 + $1.platformFees }
        }

        var totalNetIncome: Double {
            income.reduce(0) { $0 + $1.netAmount }
        }

        var totalExpenses: Double {
            expenses.reduce(0) { $0 + $1.deductibleAmount }
        }

        var totalMileage: Double {
            mileageTrips.reduce(0) { $0 + $1.miles }
        }

        var mileageDeduction: Double {
            totalMileage * TaxEngine.TaxConstants.mileageRate
        }

        var netProfit: Double {
            totalNetIncome - totalExpenses
        }
    }

    // MARK: - CSV Export

    static func generateCSV(from data: TaxExportData) -> String {
        var lines: [String] = []

        // Header
        lines.append("GigWallet Tax Export - \(data.taxYear)")
        lines.append("")

        // Income section
        lines.append("=== INCOME ===")
        lines.append("Date,Platform,Description,Gross Amount,Fees,Net Amount")
        for entry in data.income.sorted(by: { $0.entryDate < $1.entryDate }) {
            let date = formatDate(entry.entryDate)
            let platform = entry.platform.displayName
            let desc = escapeCSV(entry.notes)
            lines.append("\(date),\(platform),\(desc),\(f(entry.grossAmount)),\(f(entry.platformFees)),\(f(entry.netAmount))")
        }
        lines.append("")
        lines.append("Total Gross Income,,,,\(f(data.totalGrossIncome))")
        lines.append("Total Platform Fees,,,,\(f(data.totalFees))")
        lines.append("Total Net Income,,,,\(f(data.totalNetIncome))")

        lines.append("")

        // Expense section
        lines.append("=== EXPENSES ===")
        lines.append("Date,Category,Vendor,Description,Amount,Deductible %,Deductible Amount")
        for entry in data.expenses.sorted(by: { $0.expenseDate < $1.expenseDate }) {
            let date = formatDate(entry.expenseDate)
            let cat = entry.category.rawValue
            let vendor = escapeCSV(entry.vendor)
            let desc = escapeCSV(entry.expenseDescription)
            lines.append("\(date),\(cat),\(vendor),\(desc),\(f(entry.amount)),\(Int(entry.deductionPercentage))%,\(f(entry.deductibleAmount))")
        }
        lines.append("")
        lines.append("Total Deductible Expenses,,,,,\(f(data.totalExpenses))")

        lines.append("")

        // Mileage section
        lines.append("=== MILEAGE ===")
        lines.append("Date,Miles,Purpose,Platform,Deduction")
        for trip in data.mileageTrips.sorted(by: { $0.tripDate < $1.tripDate }) {
            let date = formatDate(trip.tripDate)
            let purpose = escapeCSV(trip.purpose)
            let platform = trip.platform.displayName
            lines.append("\(date),\(String(format: "%.1f", trip.miles)),\(purpose),\(platform),\(f(trip.deductionAmount))")
        }
        lines.append("")
        lines.append("Total Miles,\(String(format: "%.1f", data.totalMileage))")
        lines.append("Mileage Deduction (@ $\(String(format: "%.2f", TaxEngine.TaxConstants.mileageRate))/mi),\(f(data.mileageDeduction))")

        lines.append("")

        // Summary
        lines.append("=== SCHEDULE C SUMMARY ===")
        lines.append("Line 1 - Gross Income,\(f(data.totalGrossIncome))")
        lines.append("Line 10 - Commissions/Fees,\(f(data.totalFees))")
        lines.append("Line 9 - Vehicle Expenses (Mileage),\(f(data.mileageDeduction))")
        let nonMileageExpenses = data.expenses.filter { $0.category != .mileage }.reduce(0) { $0 + $1.deductibleAmount }
        lines.append("Line 27a - Other Expenses,\(f(nonMileageExpenses))")
        lines.append("Line 28 - Total Expenses,\(f(nonMileageExpenses + data.mileageDeduction + data.totalFees))")
        lines.append("Line 31 - Net Profit,\(f(data.totalGrossIncome - nonMileageExpenses - data.mileageDeduction - data.totalFees))")

        return lines.joined(separator: "\n")
    }

    // MARK: - TXF Export (TurboTax/H&R Block)

    static func generateTXF(from data: TaxExportData) -> String {
        var lines: [String] = []

        // TXF header
        lines.append("V042")  // TXF version
        lines.append("AGigWallet")  // Application name
        lines.append("D\(formatDateTXF(.now))")  // Export date
        lines.append("^")  // Record separator

        // Schedule C: Gross Receipts (Line 1)
        lines.append("TD")
        lines.append("N547")  // TXF code for Schedule C Line 1
        lines.append("C1")
        lines.append("L1")
        lines.append("$\(String(format: "%.2f", data.totalGrossIncome))")
        lines.append("^")

        // Schedule C: Commissions & Fees (Line 10)
        if data.totalFees > 0 {
            lines.append("TD")
            lines.append("N556")  // Schedule C Line 10
            lines.append("C1")
            lines.append("L1")
            lines.append("$\(String(format: "%.2f", data.totalFees))")
            lines.append("^")
        }

        // Schedule C: Car & Truck Expenses (Line 9)
        if data.mileageDeduction > 0 {
            lines.append("TD")
            lines.append("N555")  // Schedule C Line 9
            lines.append("C1")
            lines.append("L1")
            lines.append("$\(String(format: "%.2f", data.mileageDeduction))")
            lines.append("^")
        }

        // Expense categories mapped to Schedule C lines
        let categoryTotals = Dictionary(grouping: data.expenses) { $0.category }
            .mapValues { entries in entries.reduce(0) { $0 + $1.deductibleAmount } }

        // Office expenses (Line 18)
        let officeTotal = (categoryTotals[.supplies] ?? 0) + (categoryTotals[.equipment] ?? 0)
        if officeTotal > 0 {
            lines.append("TD")
            lines.append("N564")  // Schedule C Line 18
            lines.append("C1")
            lines.append("L1")
            lines.append("$\(String(format: "%.2f", officeTotal))")
            lines.append("^")
        }

        // Insurance (Line 15)
        let insuranceTotal = categoryTotals[.insurance] ?? 0
        if insuranceTotal > 0 {
            lines.append("TD")
            lines.append("N561")  // Schedule C Line 15
            lines.append("C1")
            lines.append("L1")
            lines.append("$\(String(format: "%.2f", insuranceTotal))")
            lines.append("^")
        }

        // Utilities (Line 25) - Phone & Internet
        let utilityTotal = categoryTotals[.phoneAndInternet] ?? 0
        if utilityTotal > 0 {
            lines.append("TD")
            lines.append("N571")  // Schedule C Line 25
            lines.append("C1")
            lines.append("L1")
            lines.append("$\(String(format: "%.2f", utilityTotal))")
            lines.append("^")
        }

        // Other expenses (Line 27a)
        let mappedCategories: Set<ExpenseCategory> = [.supplies, .equipment, .insurance, .phoneAndInternet, .mileage]
        let otherTotal = data.expenses
            .filter { !mappedCategories.contains($0.category) }
            .reduce(0) { $0 + $1.deductibleAmount }
        if otherTotal > 0 {
            lines.append("TD")
            lines.append("N575")  // Schedule C Line 27a
            lines.append("C1")
            lines.append("L1")
            lines.append("$\(String(format: "%.2f", otherTotal))")
            lines.append("^")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Schedule C Summary

    static func generateScheduleCSummary(from data: TaxExportData) -> String {
        var lines: [String] = []

        lines.append("═══════════════════════════════════════════════")
        lines.append("  SCHEDULE C (Form 1040) SUMMARY")
        lines.append("  Profit or Loss From Business")
        lines.append("  Tax Year \(data.taxYear)")
        lines.append("  Generated by GigWallet")
        lines.append("═══════════════════════════════════════════════")
        lines.append("")
        lines.append("PART I - INCOME")
        lines.append("───────────────────────────────────────────────")
        lines.append(String(format: "  Line 1  Gross receipts        %@", padLeft(f(data.totalGrossIncome))))
        lines.append(String(format: "  Line 7  Gross income           %@", padLeft(f(data.totalGrossIncome))))
        lines.append("")
        lines.append("PART II - EXPENSES")
        lines.append("───────────────────────────────────────────────")

        // Group expenses by Schedule C line
        let categoryTotals = Dictionary(grouping: data.expenses) { $0.category }
            .mapValues { $0.reduce(0) { $0 + $1.deductibleAmount } }

        lines.append(String(format: "  Line 9  Car & truck expenses   %@", padLeft(f(data.mileageDeduction))))
        lines.append(String(format: "           (%@ miles @ $%.2f/mi)", String(format: "%.0f", data.totalMileage), TaxEngine.TaxConstants.mileageRate))

        if let fees = categoryTotals[.insurance], fees > 0 {
            lines.append(String(format: "  Line 15 Insurance              %@", padLeft(f(fees))))
        }

        let officeTotal = (categoryTotals[.supplies] ?? 0) + (categoryTotals[.equipment] ?? 0)
        if officeTotal > 0 {
            lines.append(String(format: "  Line 18 Office expense         %@", padLeft(f(officeTotal))))
        }

        if let phone = categoryTotals[.phoneAndInternet], phone > 0 {
            lines.append(String(format: "  Line 25 Utilities              %@", padLeft(f(phone))))
        }

        if data.totalFees > 0 {
            lines.append(String(format: "  Line 10 Commissions & fees     %@", padLeft(f(data.totalFees))))
        }

        // Other expenses
        let mappedCategories: Set<ExpenseCategory> = [.supplies, .equipment, .insurance, .phoneAndInternet, .mileage]
        let otherExpenses = data.expenses
            .filter { !mappedCategories.contains($0.category) }

        if !otherExpenses.isEmpty {
            let otherTotal = otherExpenses.reduce(0) { $0 + $1.deductibleAmount }
            lines.append(String(format: "  Line 27a Other expenses        %@", padLeft(f(otherTotal))))
            lines.append("           Detail:")
            let grouped = Dictionary(grouping: otherExpenses) { $0.category.rawValue }
            for (cat, entries) in grouped.sorted(by: { $0.key < $1.key }) {
                let catTotal = entries.reduce(0) { $0 + $1.deductibleAmount }
                lines.append(String(format: "             %-20s %@", (cat as NSString).utf8String ?? "", padLeft(f(catTotal))))
            }
        }

        lines.append("───────────────────────────────────────────────")
        lines.append(String(format: "  Line 28 Total expenses         %@", padLeft(f(data.totalExpenses))))
        lines.append("")
        lines.append(String(format: "  Line 31 NET PROFIT (LOSS)      %@", padLeft(f(data.netProfit))))
        lines.append("═══════════════════════════════════════════════")
        lines.append("")
        lines.append("MILEAGE SUMMARY")
        lines.append("───────────────────────────────────────────────")
        lines.append(String(format: "  Total business miles:           %.0f", data.totalMileage))
        lines.append(String(format: "  Standard mileage rate:          $%.2f", TaxEngine.TaxConstants.mileageRate))
        lines.append(String(format: "  Mileage deduction:              %@", f(data.mileageDeduction)))
        lines.append("")
        lines.append("PLATFORM BREAKDOWN")
        lines.append("───────────────────────────────────────────────")
        let platformTotals = Dictionary(grouping: data.income) { $0.platform.displayName }
            .mapValues { $0.reduce(0) { $0 + $1.netAmount } }
        for (platform, total) in platformTotals.sorted(by: { $0.value > $1.value }) {
            lines.append(String(format: "  %-24s %@", (platform as NSString).utf8String ?? "", padLeft(f(total))))
        }
        lines.append("───────────────────────────────────────────────")
        lines.append("")
        lines.append("⚠️  This is a summary for reference only.")
        lines.append("    Consult a tax professional for actual filing.")
        lines.append("    Generated \(formatDate(.now))")

        return lines.joined(separator: "\n")
    }

    // MARK: - File Export

    static func exportToFile(data: TaxExportData, format: ExportFormat) -> URL? {
        let content: String
        switch format {
        case .csv:
            content = generateCSV(from: data)
        case .txf:
            content = generateTXF(from: data)
        case .scheduleC:
            content = generateScheduleCSummary(from: data)
        }

        let fileName = "GigWallet_\(data.taxYear).\(format.fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            #if DEBUG
            print("Export error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Helpers

    private static func f(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }

    private static func formatDateTXF(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }

    private static func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }

    private static func padLeft(_ string: String, width: Int = 12) -> String {
        if string.count >= width { return string }
        return String(repeating: " ", count: width - string.count) + string
    }
}
