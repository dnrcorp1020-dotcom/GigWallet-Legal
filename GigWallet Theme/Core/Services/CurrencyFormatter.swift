import Foundation

enum CurrencyFormatter {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let compactFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func format(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    static func formatCompact(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return "$\(String(format: "%.1fM", amount / 1_000_000))"
        } else if amount >= 10_000 {
            return "$\(String(format: "%.0fK", amount / 1_000))"
        } else if amount >= 1_000 {
            return compactFormatter.string(from: NSNumber(value: amount)) ?? "$0"
        }
        return format(amount)
    }

    static func formatPercent(_ value: Double) -> String {
        percentFormatter.string(from: NSNumber(value: value)) ?? "0%"
    }
}
