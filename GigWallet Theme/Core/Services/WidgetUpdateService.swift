import Foundation
import WidgetKit

/// Pushes app data to the shared App Group UserDefaults so widgets can display it.
/// Keys match `WidgetDataProvider.loadSnapshot()` in the widget extension exactly.
enum WidgetUpdateService {

    private static let suiteName = "group.com.dnrcorp.gigwallet"

    /// Call from DashboardView's `.task` to push fresh data to widgets.
    static func pushUpdate(
        incomeEntries: [IncomeEntry],
        expenseEntries: [ExpenseEntry],
        taxPayments: [TaxPayment],
        profile: UserProfile?,
        taxEstimate: TaxCalculationResult
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let startOfWeek = Date.now.startOfWeek

        // Today's income
        let todaysIncome = incomeEntries
            .filter { $0.entryDate >= startOfDay }
            .reduce(0.0) { $0 + $1.netAmount }

        // Weekly income
        let weeklyIncome = incomeEntries
            .filter { $0.entryDate >= startOfWeek }
            .reduce(0.0) { $0 + $1.netAmount }

        // Weekly goal
        let weeklyGoal = profile?.weeklyEarningsGoal ?? 0

        // Tax estimate + paid
        let yearlyTaxPaid = taxPayments
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0.0) { $0 + $1.amount }

        // Days until deadline
        let daysUntilDeadline = DateHelper.daysUntilDue(
            quarter: .current,
            year: DateHelper.currentTaxYear
        )

        // Quarter name
        let quarterName = TaxQuarter.current.shortName + " " + String(DateHelper.currentTaxYear)

        // Top platform (most entries this week)
        let weeklyEntries = incomeEntries.filter { $0.entryDate >= startOfWeek }
        let platformCounts = Dictionary(grouping: weeklyEntries, by: { $0.platform.displayName })
            .mapValues { $0.count }
        let topPlatform = platformCounts.max(by: { $0.value < $1.value })?.key ?? "—"

        // Weekly by day (Mon=0 through Sun=6)
        var weeklyByDay = [Double](repeating: 0, count: 7)
        for entry in weeklyEntries {
            let weekday = calendar.component(.weekday, from: entry.entryDate)
            // Calendar weekday: 1=Sun, 2=Mon...7=Sat → convert to Mon=0...Sun=6
            let index = weekday == 1 ? 6 : weekday - 2
            if index >= 0 && index < 7 {
                weeklyByDay[index] += entry.netAmount
            }
        }

        // Display name
        let displayName = profile?.displayName ?? ""

        // Write all values
        defaults.set(todaysIncome, forKey: "widget.todaysIncome")
        defaults.set(weeklyIncome, forKey: "widget.weeklyIncome")
        defaults.set(weeklyGoal, forKey: "widget.weeklyGoal")
        defaults.set(taxEstimate.totalEstimatedTax, forKey: "widget.taxEstimate")
        defaults.set(yearlyTaxPaid, forKey: "widget.taxPaid")
        defaults.set(daysUntilDeadline, forKey: "widget.daysUntilDeadline")
        defaults.set(quarterName, forKey: "widget.quarterName")
        defaults.set(topPlatform, forKey: "widget.topPlatform")
        for (i, value) in weeklyByDay.enumerated() {
            defaults.set(value, forKey: "widget.day\(i)")
        }
        defaults.set(taxEstimate.effectiveTaxRate, forKey: "widget.effectiveTaxRate")
        defaults.set(displayName, forKey: "widget.displayName")

        // Tell WidgetKit to refresh all timelines
        WidgetCenter.shared.reloadAllTimelines()
    }
}
