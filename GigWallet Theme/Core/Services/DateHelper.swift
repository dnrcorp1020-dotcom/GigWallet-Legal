import Foundation

enum DateHelper {
    static func quarterDateRange(quarter: TaxQuarter, year: Int) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let startMonth: Int
        let endMonth: Int

        switch quarter {
        case .q1: startMonth = 1; endMonth = 3
        case .q2: startMonth = 4; endMonth = 6
        case .q3: startMonth = 7; endMonth = 9
        case .q4: startMonth = 10; endMonth = 12
        }

        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? .now
        let endOfMonthStart = calendar.date(from: DateComponents(year: year, month: endMonth, day: 1))!
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: endOfMonthStart) ?? .now

        return (start, end)
    }

    static func quarterDueDate(quarter: TaxQuarter, year: Int) -> Date {
        let calendar = Calendar.current
        switch quarter {
        case .q1:
            return calendar.date(from: DateComponents(year: year, month: 4, day: 15)) ?? .now
        case .q2:
            return calendar.date(from: DateComponents(year: year, month: 6, day: 15)) ?? .now
        case .q3:
            return calendar.date(from: DateComponents(year: year, month: 9, day: 15)) ?? .now
        case .q4:
            return calendar.date(from: DateComponents(year: year + 1, month: 1, day: 15)) ?? .now
        }
    }

    static func daysUntilDue(quarter: TaxQuarter, year: Int) -> Int {
        let dueDate = quarterDueDate(quarter: quarter, year: year)
        let days = Calendar.current.dateComponents([.day], from: .now, to: dueDate).day ?? 0
        return max(days, 0)
    }

    static func isCurrentQuarter(_ quarter: TaxQuarter) -> Bool {
        quarter == TaxQuarter.current
    }

    static var currentTaxYear: Int {
        Calendar.current.component(.year, from: .now)
    }
}
