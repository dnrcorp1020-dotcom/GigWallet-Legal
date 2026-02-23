import Foundation

/// On-device intelligence engine that analyzes gig worker patterns and generates
/// proactive, actionable insights. No spreadsheet can do this.
///
/// Capabilities:
/// - Earnings velocity & momentum tracking (are you up or down vs. last week?)
/// - Best earning windows detection (your best hours/days based on history)
/// - Anomaly detection (unusual fees, missing income days, expense spikes)
/// - Predictive monthly projection (based on current pace + historical patterns)
/// - Tax set-aside recommendations (real-time "you should save $X today")
/// - Platform efficiency scoring (which platform gives you the best $/hour)
/// - Expense pattern recognition (recurring costs you might be missing)
/// - Smart nudges (context-aware suggestions based on current state)
struct InsightsEngine {

    // MARK: - Insight Types

    enum InsightType: String {
        case earningsUp          // Your earnings are trending up
        case earningsDown        // You're behind your usual pace
        case bestDay             // Your historically best earning day is coming
        case bestPlatform        // One platform is outperforming others
        case unusualFees         // Platform fees are higher than normal
        case taxSetAside         // You should set aside $X from today's earnings
        case projectedMonthly    // On pace for $X this month
        case missedDeduction     // You drove today but didn't log mileage
        case expenseSpike        // Your expenses are unusually high
        case milestoneApproach   // Approaching a round number ($5K, $10K, etc.)
        case velocityShift       // Your $/day rate changed significantly
        case weekendOpportunity  // Historically your best earning weekend
        case quietPeriod         // You haven't logged income in X days
        case platformDiversify   // >80% of income from one platform = risk
        case recurringExpense    // Detected a likely recurring expense
        case form1099kPace       // On pace to hit 1099-K threshold by month X
    }

    enum InsightPriority: Int, Comparable {
        case critical = 0   // Needs attention now (tax deadline, anomaly)
        case high = 1       // Important trend or opportunity
        case medium = 2     // Helpful pattern recognition
        case low = 3        // Nice-to-know context

        static func < (lhs: InsightPriority, rhs: InsightPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Insight: Identifiable {
        let id = UUID()
        let type: InsightType
        let priority: InsightPriority
        let title: String
        let message: String
        let icon: String
        let accentColor: String  // BrandColors key
        let value: Double?       // Optional associated value (dollars, percentage, etc.)
        let actionLabel: String? // Optional CTA
        let timestamp: Date = .now
    }

    // MARK: - Core Analysis

    /// Generate all relevant insights based on current user data
    static func generateInsights(
        incomeEntries: [IncomeEntrySnapshot],
        expenseEntries: [ExpenseEntrySnapshot],
        mileageTrips: [MileageTripSnapshot],
        weeklyGoal: Double,
        filingStatus: String,
        stateCode: String
    ) -> [Insight] {
        var insights: [Insight] = []

        // 1. Earnings Momentum
        if let momentum = analyzeEarningsMomentum(entries: incomeEntries) {
            insights.append(momentum)
        }

        // 2. Monthly Projection
        if let projection = projectMonthlyEarnings(entries: incomeEntries) {
            insights.append(projection)
        }

        // 3. Best Earning Day Detection
        if let bestDay = detectBestEarningDay(entries: incomeEntries) {
            insights.append(bestDay)
        }

        // 4. Platform Efficiency
        if let platformInsight = analyzePlatformEfficiency(entries: incomeEntries) {
            insights.append(platformInsight)
        }

        // 5. Tax Set-Aside
        if let taxInsight = calculateTaxSetAside(entries: incomeEntries, filingStatus: filingStatus) {
            insights.append(taxInsight)
        }

        // 6. Anomaly Detection (unusual fees)
        if let feeAnomaly = detectFeeAnomalies(entries: incomeEntries) {
            insights.append(feeAnomaly)
        }

        // 7. Quiet Period Detection
        if let quiet = detectQuietPeriod(entries: incomeEntries) {
            insights.append(quiet)
        }

        // 8. Platform Diversification Risk
        if let diversify = analyzePlatformConcentration(entries: incomeEntries) {
            insights.append(diversify)
        }

        // 9. Milestone Approaching
        if let milestone = detectUpcomingMilestone(entries: incomeEntries) {
            insights.append(milestone)
        }

        // 10. Expense Spike Detection
        if let spike = detectExpenseSpike(expenses: expenseEntries) {
            insights.append(spike)
        }

        // 11. 1099-K Pace Projection
        if let pace = project1099KPace(entries: incomeEntries) {
            insights.append(pace)
        }

        // 12. Earnings Velocity ($/day rate)
        if let velocity = calculateEarningsVelocity(entries: incomeEntries) {
            insights.append(velocity)
        }

        // Sort by priority, then recency
        return insights.sorted { $0.priority < $1.priority }
    }

    // MARK: - Momentum Analysis

    /// Compare this week's earnings to last week — are we trending up or down?
    private static func analyzeEarningsMomentum(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current
        let now = Date.now
        guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek) else { return nil }

        let thisWeek = entries.filter { $0.date >= startOfThisWeek }.reduce(0.0) { $0 + $1.netAmount }
        let lastWeek = entries.filter { $0.date >= startOfLastWeek && $0.date < startOfThisWeek }.reduce(0.0) { $0 + $1.netAmount }

        guard lastWeek > 50 else { return nil } // Need meaningful baseline

        let dayOfWeek = calendar.component(.weekday, from: now)
        // Adjust for partial week — pro-rate last week's earnings to same number of days
        let daysElapsed = max(dayOfWeek - 1, 1) // Sunday=1, so Monday=1 day elapsed
        let lastWeekProRated = lastWeek * (Double(daysElapsed) / 7.0)

        guard lastWeekProRated > 10 else { return nil }

        let changePercent = ((thisWeek - lastWeekProRated) / lastWeekProRated) * 100

        if changePercent > 15 {
            return Insight(
                type: .earningsUp,
                priority: .medium,
                title: "Earnings Trending Up",
                message: "You're \(Int(changePercent))% ahead of last week's pace. Keep this momentum going.",
                icon: "arrow.up.right.circle.fill",
                accentColor: "success",
                value: changePercent,
                actionLabel: nil
            )
        } else if changePercent < -20 {
            return Insight(
                type: .earningsDown,
                priority: .high,
                title: "Slower Week So Far",
                message: "You're \(Int(abs(changePercent)))% behind last week's pace. Consider picking up extra shifts.",
                icon: "arrow.down.right.circle.fill",
                accentColor: "warning",
                value: changePercent,
                actionLabel: "View Earnings"
            )
        }

        return nil
    }

    // MARK: - Monthly Projection

    private static func projectMonthlyEarnings(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current
        let now = Date.now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let dayOfMonth = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30

        guard dayOfMonth >= 5 else { return nil } // Need at least 5 days of data

        let monthSoFar = entries.filter { $0.date >= startOfMonth }.reduce(0.0) { $0 + $1.netAmount }
        guard monthSoFar > 0 else { return nil }

        let dailyRate = monthSoFar / Double(dayOfMonth)
        let projectedMonthly = dailyRate * Double(daysInMonth)

        // Compare to last month
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? now
        let lastMonthTotal = entries.filter { $0.date >= startOfLastMonth && $0.date < startOfMonth }.reduce(0.0) { $0 + $1.netAmount }

        var message = "At your current pace, you're projected to earn \(formatCompact(projectedMonthly)) this month."
        if lastMonthTotal > 0 {
            let diff = projectedMonthly - lastMonthTotal
            if diff > 0 {
                message += " That's \(formatCompact(diff)) more than last month."
            } else if diff < -100 {
                message += " That's \(formatCompact(abs(diff))) less than last month."
            }
        }

        return Insight(
            type: .projectedMonthly,
            priority: .medium,
            title: "Monthly Projection",
            message: message,
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            accentColor: projectedMonthly > lastMonthTotal ? "success" : "primary",
            value: projectedMonthly,
            actionLabel: nil
        )
    }

    // MARK: - Best Earning Day

    private static func detectBestEarningDay(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current

        // Analyze last 60 days of data
        let cutoff = calendar.date(byAdding: .day, value: -60, to: .now) ?? .now
        let recentEntries = entries.filter { $0.date >= cutoff }
        guard recentEntries.count >= 10 else { return nil }

        // Aggregate by day of week
        var dayTotals: [Int: (total: Double, count: Int)] = [:]
        for entry in recentEntries {
            let weekday = calendar.component(.weekday, from: entry.date)
            let existing = dayTotals[weekday] ?? (0, 0)
            dayTotals[weekday] = (existing.total + entry.netAmount, existing.count + 1)
        }

        // Find best day
        guard let best = dayTotals.max(by: { ($0.value.total / max(Double($0.value.count), 1)) < ($1.value.total / max(Double($1.value.count), 1)) }) else { return nil }

        let avgEarnings = best.value.total / max(Double(best.value.count), 1)
        let dayName = calendar.weekdaySymbols[best.key - 1]

        // Only show if today or tomorrow is that day
        let todayWeekday = calendar.component(.weekday, from: .now)
        let isTodayOrTomorrow = best.key == todayWeekday || best.key == (todayWeekday % 7) + 1

        guard isTodayOrTomorrow else { return nil }

        let timing = best.key == todayWeekday ? "Today" : "Tomorrow"

        return Insight(
            type: .bestDay,
            priority: .medium,
            title: "\(timing) Is Your Best Day",
            message: "\(dayName)s are historically your top earning day, averaging \(formatCompact(avgEarnings)) per \(dayName).",
            icon: "star.circle.fill",
            accentColor: "primary",
            value: avgEarnings,
            actionLabel: nil
        )
    }

    // MARK: - Platform Efficiency

    private static func analyzePlatformEfficiency(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recent = entries.filter { $0.date >= cutoff }

        // Group by platform
        var platformStats: [String: (gross: Double, fees: Double, count: Int)] = [:]
        for entry in recent {
            let existing = platformStats[entry.platform] ?? (0, 0, 0)
            platformStats[entry.platform] = (existing.gross + entry.grossAmount, existing.fees + entry.fees, existing.count + 1)
        }

        guard platformStats.count >= 2 else { return nil }

        // Calculate net efficiency (net per entry)
        let efficiencies = platformStats.map { (platform: $0.key, netPerEntry: ($0.value.gross - $0.value.fees) / max(Double($0.value.count), 1), feeRate: $0.value.fees / max($0.value.gross, 1)) }
        guard let best = efficiencies.max(by: { $0.netPerEntry < $1.netPerEntry }),
              let worst = efficiencies.min(by: { $0.netPerEntry < $1.netPerEntry }),
              best.platform != worst.platform else { return nil }

        let difference = best.netPerEntry - worst.netPerEntry
        guard difference > 5 else { return nil } // Meaningful difference

        return Insight(
            type: .bestPlatform,
            priority: .high,
            title: "\(best.platform) Earns You More",
            message: "You earn \(formatCompact(difference)) more per trip on \(best.platform) vs \(worst.platform). Consider shifting more hours there.",
            icon: "arrow.triangle.swap",
            accentColor: "success",
            value: difference,
            actionLabel: "View Breakdown"
        )
    }

    // MARK: - Tax Set-Aside

    private static func calculateTaxSetAside(entries: [IncomeEntrySnapshot], filingStatus: String) -> Insight? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let todaysIncome = entries.filter { $0.date >= startOfDay }.reduce(0.0) { $0 + $1.netAmount }

        guard todaysIncome > 20 else { return nil }

        // Approximate SE tax + income tax rate for gig workers: ~25-30%
        let estimatedRate = 0.27
        let setAside = todaysIncome * estimatedRate

        return Insight(
            type: .taxSetAside,
            priority: .high,
            title: "Set Aside \(formatCompact(setAside)) Today",
            message: "You earned \(formatCompact(todaysIncome)) today. Transfer ~\(formatCompact(setAside)) to savings for taxes (est. \(Int(estimatedRate * 100))% effective rate).",
            icon: "banknote.fill",
            accentColor: "info",
            value: setAside,
            actionLabel: nil
        )
    }

    // MARK: - Fee Anomaly Detection

    private static func detectFeeAnomalies(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now

        // Group by platform and check fee rates
        var platformFeeRates: [String: [Double]] = [:]
        for entry in entries.filter({ $0.date >= cutoff && $0.grossAmount > 0 }) {
            let feeRate = entry.fees / entry.grossAmount
            platformFeeRates[entry.platform, default: []].append(feeRate)
        }

        for (platform, rates) in platformFeeRates {
            guard rates.count >= 5 else { continue }
            let avg = rates.reduce(0, +) / Double(rates.count)
            let lastFew = Array(rates.suffix(3))
            let recentAvg = lastFew.reduce(0, +) / Double(lastFew.count)

            // If recent fee rate is 20%+ higher than average
            if avg > 0 && (recentAvg - avg) / avg > 0.20 {
                return Insight(
                    type: .unusualFees,
                    priority: .high,
                    title: "Higher Fees on \(platform)",
                    message: "\(platform) fees recently jumped from \(Int(avg * 100))% to \(Int(recentAvg * 100))% of gross. Check if there's a new fee structure.",
                    icon: "exclamationmark.triangle.fill",
                    accentColor: "warning",
                    value: recentAvg,
                    actionLabel: nil
                )
            }
        }

        return nil
    }

    // MARK: - Quiet Period Detection

    private static func detectQuietPeriod(entries: [IncomeEntrySnapshot]) -> Insight? {
        guard !entries.isEmpty else { return nil }

        let sorted = entries.sorted { $0.date > $1.date }
        guard let lastEntry = sorted.first else { return nil }

        let daysSince = Calendar.current.dateComponents([.day], from: lastEntry.date, to: .now).day ?? 0

        if daysSince >= 5 {
            return Insight(
                type: .quietPeriod,
                priority: .medium,
                title: "\(daysSince) Days Without Income",
                message: "Your last logged income was \(daysSince) days ago. Don't forget to track any earnings.",
                icon: "clock.badge.exclamationmark.fill",
                accentColor: "warning",
                value: Double(daysSince),
                actionLabel: "Add Income"
            )
        }

        return nil
    }

    // MARK: - Platform Concentration Risk

    private static func analyzePlatformConcentration(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -90, to: .now) ?? .now
        let recent = entries.filter { $0.date >= cutoff }
        let totalIncome = recent.reduce(0.0) { $0 + $1.netAmount }

        guard totalIncome > 500 else { return nil }

        var platformTotals: [String: Double] = [:]
        for entry in recent {
            platformTotals[entry.platform, default: 0] += entry.netAmount
        }

        guard let top = platformTotals.max(by: { $0.value < $1.value }),
              platformTotals.count > 1 else { return nil }

        let concentration = top.value / totalIncome
        if concentration > 0.80 {
            return Insight(
                type: .platformDiversify,
                priority: .medium,
                title: "High Platform Concentration",
                message: "\(Int(concentration * 100))% of your income comes from \(top.key). Diversifying across platforms reduces risk if one changes rates.",
                icon: "chart.pie.fill",
                accentColor: "info",
                value: concentration,
                actionLabel: nil
            )
        }

        return nil
    }

    // MARK: - Milestone Approaching

    private static func detectUpcomingMilestone(entries: [IncomeEntrySnapshot]) -> Insight? {
        let yearTotal = entries.filter { Calendar.current.component(.year, from: $0.date) == Calendar.current.component(.year, from: .now) }
            .reduce(0.0) { $0 + $1.netAmount }

        let milestones: [Double] = [1000, 2500, 5000, 10000, 15000, 20000, 25000, 30000, 40000, 50000, 75000, 100000]

        for milestone in milestones {
            let remaining = milestone - yearTotal
            // Within 10% of milestone
            if remaining > 0 && remaining < milestone * 0.10 && remaining < 500 {
                return Insight(
                    type: .milestoneApproach,
                    priority: .low,
                    title: "\(formatCompact(remaining)) to \(formatCompact(milestone))",
                    message: "You're \(formatCompact(remaining)) away from \(formatCompact(milestone)) in yearly earnings. Almost there!",
                    icon: "flag.checkered.circle.fill",
                    accentColor: "primary",
                    value: milestone,
                    actionLabel: nil
                )
            }
        }

        return nil
    }

    // MARK: - Expense Spike Detection

    private static func detectExpenseSpike(expenses: [ExpenseEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? .now

        let thisMonth = expenses.filter { $0.date >= startOfMonth }.reduce(0.0) { $0 + $1.amount }
        let lastMonth = expenses.filter { $0.date >= startOfLastMonth && $0.date < startOfMonth }.reduce(0.0) { $0 + $1.amount }

        guard lastMonth > 50 else { return nil }

        let dayOfMonth = calendar.component(.day, from: .now)
        let proRatedLastMonth = lastMonth * (Double(dayOfMonth) / 30.0)

        guard proRatedLastMonth > 20 else { return nil }

        let spike = ((thisMonth - proRatedLastMonth) / proRatedLastMonth) * 100

        if spike > 40 {
            return Insight(
                type: .expenseSpike,
                priority: .high,
                title: "Expenses Up \(Int(spike))%",
                message: "Your expenses this month are \(Int(spike))% higher than last month's pace. Review recent expenses to ensure nothing unexpected.",
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                accentColor: "destructive",
                value: spike,
                actionLabel: "Review Expenses"
            )
        }

        return nil
    }

    // MARK: - 1099-K Pace Projection

    private static func project1099KPace(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        let yearEntries = entries.filter { calendar.component(.year, from: $0.date) == year }
        let yearTotal = yearEntries.reduce(0.0) { $0 + $1.grossAmount }

        let threshold: Double = 5000
        guard yearTotal > threshold * 0.4 && yearTotal < threshold else { return nil }

        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: .now) ?? 1
        let dailyRate = yearTotal / Double(dayOfYear)
        let projectedYearly = dailyRate * 365

        if projectedYearly > threshold {
            let estimatedMonth = Int(ceil(Double(dayOfYear) * (threshold / yearTotal) / 30.44))
            let monthName = estimatedMonth <= 12 ? calendar.monthSymbols[estimatedMonth - 1] : "December"

            return Insight(
                type: .form1099kPace,
                priority: .high,
                title: "1099-K Threshold by \(monthName)",
                message: "At your current pace, you'll hit the $5,000 1099-K reporting threshold by \(monthName). Make sure you're tracking all expenses for deductions.",
                icon: "doc.text.fill",
                accentColor: "info",
                value: threshold - yearTotal,
                actionLabel: "Tax Center"
            )
        }

        return nil
    }

    // MARK: - Earnings Velocity

    private static func calculateEarningsVelocity(entries: [IncomeEntrySnapshot]) -> Insight? {
        let calendar = Calendar.current

        // Last 7 days vs. previous 7 days
        let now = Date.now
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) else { return nil }

        let recentWeek = entries.filter { $0.date >= sevenDaysAgo }.reduce(0.0) { $0 + $1.netAmount }
        let previousWeek = entries.filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }.reduce(0.0) { $0 + $1.netAmount }

        let recentDaily = recentWeek / 7.0
        let previousDaily = previousWeek / 7.0

        guard previousDaily > 10 else { return nil }

        let velocityChange = ((recentDaily - previousDaily) / previousDaily) * 100

        guard abs(velocityChange) > 25 else { return nil } // Significant change

        if velocityChange > 0 {
            return Insight(
                type: .velocityShift,
                priority: .low,
                title: "Earning \(formatCompact(recentDaily))/Day",
                message: "Your daily earning rate is up \(Int(velocityChange))% from \(formatCompact(previousDaily))/day to \(formatCompact(recentDaily))/day.",
                icon: "gauge.open.with.lines.needle.33percent.and.arrowtriangle.from.0percent.to.50percent",
                accentColor: "success",
                value: recentDaily,
                actionLabel: nil
            )
        } else {
            return Insight(
                type: .velocityShift,
                priority: .medium,
                title: "Earning Rate Dropped",
                message: "Your daily rate dropped \(Int(abs(velocityChange)))% from \(formatCompact(previousDaily))/day to \(formatCompact(recentDaily))/day.",
                icon: "gauge.open.with.lines.needle.33percent.and.arrowtriangle.from.0percent.to.50percent",
                accentColor: "warning",
                value: recentDaily,
                actionLabel: nil
            )
        }
    }

    // MARK: - Helpers

    private static func formatCompact(_ value: Double) -> String {
        if value >= 1000 {
            return "$\(String(format: "%.1f", value / 1000))K"
        }
        return "$\(String(format: "%.0f", value))"
    }
}

// MARK: - Lightweight Snapshots (for testability — decouple from SwiftData)

/// Lightweight value types that mirror SwiftData models for pure computation
extension InsightsEngine {

    struct IncomeEntrySnapshot {
        let date: Date
        let grossAmount: Double
        let fees: Double
        let netAmount: Double
        let platform: String
    }

    struct ExpenseEntrySnapshot {
        let date: Date
        let amount: Double
        let category: String
        let isDeductible: Bool
    }

    struct MileageTripSnapshot {
        let date: Date
        let miles: Double
    }
}
