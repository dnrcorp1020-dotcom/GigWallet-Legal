import Foundation

extension Double {
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    var asCurrencyCompact: String {
        if self >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale(identifier: "en_US")
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: self)) ?? "$0"
        }
        return asCurrency
    }
}

extension Decimal {
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }

    var asDouble: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
