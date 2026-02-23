import Foundation

/// On-device statistical engine that analyzes the user's earning history to find
/// patterns they can exploit: best days, best times, highest-yield platforms,
/// current streaks, and projected optimal earnings.
///
/// Entirely client-side — no server calls, no ML models. Pure arithmetic on SwiftData.
/// This gives gig workers something even Uber/DoorDash don't: a cross-platform view
/// of when they actually make the most money.
enum EarningsPatternEngine {

    // MARK: - Snapshot (decoupled from SwiftData)

    struct IncomeSnapshot {
        let date: Date
        let grossAmount: Double
        let netAmount: Double
        let platform: String
    }

    // MARK: - Output Types

    struct DayEarnings: Identifiable {
        let dayOfWeek: Int          // 1=Sun, 7=Sat
        let avgEarnings: Double
        let entryCount: Int
        var id: Int { dayOfWeek }
    }

    enum TimeBlock: String, CaseIterable {
        case morning   = "Morning"      // 5-12
        case afternoon = "Afternoon"    // 12-17
        case evening   = "Evening"      // 17-21
        case night     = "Night"        // 21-5

        static func from(hour: Int) -> TimeBlock {
            switch hour {
            case 5..<12:  return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default:      return .night
            }
        }
    }

    struct TimeBlockEarnings: Identifiable {
        let timeBlock: TimeBlock
        let avgEarnings: Double
        let entryCount: Int
        var id: String { timeBlock.rawValue }
    }

    struct PlatformDayPerformance: Identifiable {
        let platform: String
        let dayOfWeek: Int
        let avgEarnings: Double
        var id: String { "\(platform)-\(dayOfWeek)" }
    }

    struct WeeklyInsight {
        let bestDays: [DayEarnings]                     // Sorted desc by avg
        let bestTimeBlocks: [TimeBlockEarnings]          // Sorted desc by avg
        let bestPlatformByDay: [PlatformDayPerformance]  // Best platform for each day
        let currentStreak: Int                           // Consecutive earning days
        let avgActiveDaysPerWeek: Double
        let avgIncomePerActiveDay: Double
        let projectedWeeklyIfOptimal: Double             // If they worked their top 3-5 days
        let recommendation: String
    }

    // MARK: - Analysis

    /// Full analysis — requires >= 7 entries spanning >= 3 different days
    static func analyze(entries: [IncomeSnapshot]) -> WeeklyInsight? {
        guard entries.count >= 7 else { return nil }

        let calendar = Calendar.current

        // --- Day-of-week analysis ---
        var dayTotals: [Int: (total: Double, count: Int)] = [:]
        for entry in entries {
            let dow = calendar.component(.weekday, from: entry.date)
            let existing = dayTotals[dow] ?? (0, 0)
            dayTotals[dow] = (existing.total + entry.netAmount, existing.count + 1)
        }

        let dayEarnings = dayTotals.map {
            DayEarnings(
                dayOfWeek: $0.key,
                avgEarnings: $0.value.total / Double(max($0.value.count, 1)),
                entryCount: $0.value.count
            )
        }.sorted { $0.avgEarnings > $1.avgEarnings }

        guard dayEarnings.count >= 3 else { return nil }

        // --- Time block analysis ---
        var timeTotals: [TimeBlock: (total: Double, count: Int)] = [:]
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.date)
            let block = TimeBlock.from(hour: hour)
            let existing = timeTotals[block] ?? (0, 0)
            timeTotals[block] = (existing.total + entry.netAmount, existing.count + 1)
        }

        let timeEarnings = timeTotals.map {
            TimeBlockEarnings(
                timeBlock: $0.key,
                avgEarnings: $0.value.total / Double(max($0.value.count, 1)),
                entryCount: $0.value.count
            )
        }.sorted { $0.avgEarnings > $1.avgEarnings }

        // --- Platform by day ---
        var platformDayData: [String: [Int: (total: Double, count: Int)]] = [:]
        for entry in entries {
            let dow = calendar.component(.weekday, from: entry.date)
            var platformMap = platformDayData[entry.platform] ?? [:]
            let existing = platformMap[dow] ?? (0, 0)
            platformMap[dow] = (existing.total + entry.netAmount, existing.count + 1)
            platformDayData[entry.platform] = platformMap
        }

        // Find best platform for each day
        var bestByDay: [PlatformDayPerformance] = []
        for dow in 1...7 {
            var bestPlatform = ""
            var bestAvg = 0.0
            for (platform, dayMap) in platformDayData {
                if let data = dayMap[dow] {
                    let avg = data.total / Double(max(data.count, 1))
                    if avg > bestAvg {
                        bestAvg = avg
                        bestPlatform = platform
                    }
                }
            }
            if !bestPlatform.isEmpty {
                bestByDay.append(PlatformDayPerformance(
                    platform: bestPlatform,
                    dayOfWeek: dow,
                    avgEarnings: bestAvg
                ))
            }
        }

        // --- Streak calculation ---
        let sortedDates = Set(entries.map { calendar.startOfDay(for: $0.date) }).sorted(by: >)
        var streak = 0
        var checkDate = calendar.startOfDay(for: .now)
        for date in sortedDates {
            if date == checkDate {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if date < checkDate {
                break
            }
        }

        // --- Weekly activity stats ---
        let uniqueDates = Set(entries.map { calendar.startOfDay(for: $0.date) })
        let dateRange = entries.map(\.date)
        let firstDate = dateRange.min() ?? .now
        let lastDate = dateRange.max() ?? .now
        let totalWeeks = max(calendar.dateComponents([.weekOfYear], from: firstDate, to: lastDate).weekOfYear ?? 1, 1)
        let avgActiveDays = Double(uniqueDates.count) / Double(totalWeeks)

        let totalNet = entries.reduce(0.0) { $0 + $1.netAmount }
        let avgPerActiveDay = totalNet / Double(max(uniqueDates.count, 1))

        // --- Projected optimal ---
        // Top N days (where N = their avg active days rounded up)
        let optimalDayCount = min(Int(ceil(avgActiveDays)), dayEarnings.count)
        let projectedOptimal = dayEarnings.prefix(optimalDayCount).reduce(0.0) { $0 + $1.avgEarnings }

        // --- Smart recommendation ---
        let recommendation = generateRecommendation(
            dayEarnings: dayEarnings,
            timeEarnings: timeEarnings,
            avgActiveDays: avgActiveDays,
            projectedOptimal: projectedOptimal,
            streak: streak
        )

        return WeeklyInsight(
            bestDays: dayEarnings,
            bestTimeBlocks: timeEarnings,
            bestPlatformByDay: bestByDay,
            currentStreak: streak,
            avgActiveDaysPerWeek: avgActiveDays,
            avgIncomePerActiveDay: avgPerActiveDay,
            projectedWeeklyIfOptimal: projectedOptimal,
            recommendation: recommendation
        )
    }

    /// Quick stats for the dashboard card — lighter weight, returns raw tuples
    static func quickDayStats(entries: [IncomeSnapshot]) -> [(dayOfWeek: Int, avgEarnings: Double, entryCount: Int)] {
        let calendar = Calendar.current
        var dayTotals: [Int: (total: Double, count: Int)] = [:]

        for entry in entries {
            let dow = calendar.component(.weekday, from: entry.date)
            let existing = dayTotals[dow] ?? (0, 0)
            dayTotals[dow] = (existing.total + entry.netAmount, existing.count + 1)
        }

        return dayTotals.map { (dayOfWeek: $0.key, avgEarnings: $0.value.total / Double(max($0.value.count, 1)), entryCount: $0.value.count) }
            .sorted { $0.avgEarnings > $1.avgEarnings }
    }

    // MARK: - Private

    private static func generateRecommendation(
        dayEarnings: [DayEarnings],
        timeEarnings: [TimeBlockEarnings],
        avgActiveDays: Double,
        projectedOptimal: Double,
        streak: Int
    ) -> String {
        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        // Get top 3 day names
        let top3 = dayEarnings.prefix(3).compactMap { day -> String? in
            guard day.dayOfWeek >= 1 && day.dayOfWeek <= 7 else { return nil }
            return dayNames[day.dayOfWeek]
        }

        let top3Str = top3.joined(separator: ", ")

        if projectedOptimal > 0 && avgActiveDays > 1 {
            return "Focus on \(top3Str) for ~\(CurrencyFormatter.format(projectedOptimal))/week"
        }

        if let bestTime = timeEarnings.first {
            return "\(bestTime.timeBlock.rawValue)s on \(top3Str) are your sweet spot"
        }

        return "Keep logging to unlock your earning patterns"
    }
}
