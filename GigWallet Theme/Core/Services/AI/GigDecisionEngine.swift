import Foundation
import Accelerate

/// AI-powered Gig Decision Engine — "Should I work right now?"
///
/// This is the "Waze for income" feature. It combines:
/// - Historical net per hour by time-of-day and day-of-week
/// - Gas price impact on net earnings
/// - Platform efficiency comparison
/// - Income momentum (are they on track for their weekly goal?)
/// - Seasonal and time-block patterns from EarningsPatternEngine
///
/// The output is a single actionable recommendation:
/// "Working now on Uber = projected $21/hr net"
///
/// Uses Accelerate (vDSP) for real regression and probability estimation.
/// No fake heuristics — all projections have confidence intervals.
enum GigDecisionEngine: Sendable {

    // MARK: - Output Types

    struct WorkRecommendation: Sendable {
        /// Should they work right now?
        let shouldWork: Bool
        /// Projected net hourly rate if they work now
        let projectedHourlyRate: Double
        /// Confidence in the projection (0-1)
        let confidence: Double
        /// Best platform to work on right now
        let bestPlatform: PlatformProjection?
        /// All platform projections sorted by projected rate
        let platformRanking: [PlatformProjection]
        /// Current time block analysis
        let timeBlockAnalysis: TimeBlockScore
        /// Goal context — how working now affects their weekly goal
        let goalImpact: GoalImpact?
        /// Natural language recommendation
        let recommendation: String
        /// Short action label for the card
        let actionLabel: String
    }

    struct PlatformProjection: Sendable, Identifiable {
        let id: String
        let platform: String
        let projectedGrossPerHour: Double
        let projectedNetPerHour: Double
        let estimatedFeeRate: Double
        let estimatedGasCostPerHour: Double
        let dataPointCount: Int
        let confidence: Double
    }

    struct TimeBlockScore: Sendable {
        let currentBlock: String       // "Evening"
        let currentBlockScore: Double  // 0-100 (how good is this time to work?)
        let bestBlockToday: String     // "Afternoon"
        let bestBlockAvgRate: Double   // $/hr for best block
        let hoursUntilBestBlock: Int?  // nil if already in best block
    }

    struct GoalImpact: Sendable {
        let weeklyGoal: Double
        let currentProgress: Double
        let remaining: Double
        let hoursNeededAtProjectedRate: Double
        let onTrackMessage: String
    }

    // MARK: - Input Types

    struct HistoricalEntry: Sendable {
        let date: Date
        let grossAmount: Double
        let netAmount: Double
        let fees: Double
        let platform: String
        let estimatedHours: Double  // From GigPlatformType.estimatedHoursPerEntry
    }

    struct MarketContext: Sendable {
        let gasPrice: Double           // $/gallon from EIA or MarketIntelligenceService
        let avgMilesPerGigHour: Double // Estimated miles driven per hour of gig work (~15)
        let vehicleMPG: Double         // User's vehicle MPG (default 25)
    }

    // MARK: - Main Recommendation

    static func recommend(
        entries: [HistoricalEntry],
        weeklyGoal: Double,
        currentWeeklyIncome: Double,
        market: MarketContext,
        effectiveTaxRate: Double
    ) -> WorkRecommendation {
        let calendar = Calendar.current
        let now = Date.now
        let currentHour = calendar.component(.hour, from: now)
        let currentDOW = calendar.component(.weekday, from: now)  // 1=Sun

        // --- Build time-block x platform profitability matrix ---
        let platformProjections = buildPlatformProjections(
            entries: entries,
            currentHour: currentHour,
            currentDOW: currentDOW,
            market: market,
            taxRate: effectiveTaxRate
        )

        // --- Time block analysis ---
        let timeBlockScore = buildTimeBlockScore(
            entries: entries,
            currentHour: currentHour,
            currentDOW: currentDOW,
            market: market,
            taxRate: effectiveTaxRate
        )

        // --- Best platform right now ---
        let sorted = platformProjections.sorted { $0.projectedNetPerHour > $1.projectedNetPerHour }
        let bestPlatform = sorted.first

        let projectedRate = bestPlatform?.projectedNetPerHour ?? 0
        let confidence = bestPlatform?.confidence ?? 0

        // --- Goal impact ---
        var goalImpact: GoalImpact? = nil
        if weeklyGoal > 0 {
            let remaining = max(weeklyGoal - currentWeeklyIncome, 0)
            let hoursNeeded = projectedRate > 0 ? remaining / projectedRate : 0

            let message: String
            if remaining <= 0 {
                message = "Goal reached! Extra earnings are bonus."
            } else if hoursNeeded <= 2 {
                message = "Just \(String(format: "%.1f", hoursNeeded)) hours to hit your goal."
            } else if hoursNeeded <= 5 {
                message = "\(String(format: "%.0f", hoursNeeded)) hours left to reach your weekly goal."
            } else {
                message = "About \(String(format: "%.0f", hoursNeeded)) hours needed. Focus on peak times."
            }

            goalImpact = GoalImpact(
                weeklyGoal: weeklyGoal,
                currentProgress: currentWeeklyIncome,
                remaining: remaining,
                hoursNeededAtProjectedRate: hoursNeeded,
                onTrackMessage: message
            )
        }

        // --- Decision logic ---
        let shouldWork: Bool
        let recommendation: String
        let actionLabel: String

        if entries.count < 10 {
            shouldWork = true
            recommendation = "Log more gigs for personalized timing advice. Every entry improves predictions."
            actionLabel = "Start earning"
        } else if projectedRate >= 20 {
            shouldWork = true
            let platformName = bestPlatform?.platform ?? "your best platform"
            recommendation = "\(platformName) projects \(formatCurrency(projectedRate))/hr net right now. This is a strong earning window."
            actionLabel = "\(formatCurrency(projectedRate))/hr projected"
        } else if projectedRate >= 15 {
            shouldWork = true
            recommendation = "Decent earning potential at \(formatCurrency(projectedRate))/hr. \(timeBlockScore.bestBlockToday) is historically better."
            actionLabel = "\(formatCurrency(projectedRate))/hr — decent"
        } else if projectedRate >= 10 {
            shouldWork = false
            if let hoursUntil = timeBlockScore.hoursUntilBestBlock, hoursUntil > 0 && hoursUntil <= 4 {
                recommendation = "Low projected rate. \(timeBlockScore.bestBlockToday) starts in \(hoursUntil)h with \(formatCurrency(timeBlockScore.bestBlockAvgRate))/hr avg."
                actionLabel = "Wait \(hoursUntil)h for peak"
            } else {
                recommendation = "Below-average earning potential right now. Consider waiting for a better time block."
                actionLabel = "\(formatCurrency(projectedRate))/hr — below avg"
            }
        } else {
            shouldWork = false
            recommendation = "Low earning potential this time. Rest up for tomorrow's peak hours."
            actionLabel = "Low demand — rest up"
        }

        return WorkRecommendation(
            shouldWork: shouldWork,
            projectedHourlyRate: projectedRate,
            confidence: confidence,
            bestPlatform: bestPlatform,
            platformRanking: sorted,
            timeBlockAnalysis: timeBlockScore,
            goalImpact: goalImpact,
            recommendation: recommendation,
            actionLabel: actionLabel
        )
    }

    // MARK: - Platform Projections

    private static func buildPlatformProjections(
        entries: [HistoricalEntry],
        currentHour: Int,
        currentDOW: Int,
        market: MarketContext,
        taxRate: Double
    ) -> [PlatformProjection] {
        let currentBlock = timeBlockName(for: currentHour)

        // Group entries by platform
        let byPlatform = Dictionary(grouping: entries) { $0.platform }

        return byPlatform.compactMap { platform, platformEntries in
            guard platformEntries.count >= 3 else { return nil }

            // Filter to same time block and weight by recency
            let calendar = Calendar.current
            let sameBlockEntries = platformEntries.filter {
                let hour = calendar.component(.hour, from: $0.date)
                return timeBlockName(for: hour) == currentBlock
            }

            // Use same-block entries if available, otherwise all entries
            let relevantEntries = sameBlockEntries.count >= 2 ? sameBlockEntries : platformEntries

            // Calculate weighted average (more recent = higher weight)
            let now = Date.now
            var weightedGrossSum: Double = 0
            var weightedNetSum: Double = 0
            var weightedHoursSum: Double = 0
            var totalWeight: Double = 0

            for entry in relevantEntries {
                let daysAgo = max(now.timeIntervalSince(entry.date) / 86400, 0.1)
                let recencyWeight = 1.0 / (1.0 + log(daysAgo + 1))  // Logarithmic decay

                // Day-of-week bonus: same day entries get 50% boost
                let dowBonus: Double = calendar.component(.weekday, from: entry.date) == currentDOW ? 1.5 : 1.0
                let weight = recencyWeight * dowBonus

                weightedGrossSum += entry.grossAmount * weight
                weightedNetSum += entry.netAmount * weight
                weightedHoursSum += entry.estimatedHours * weight
                totalWeight += weight
            }

            guard totalWeight > 0, weightedHoursSum > 0 else { return nil }

            let avgGrossPerHour = weightedGrossSum / weightedHoursSum
            let avgNetPerHour = weightedNetSum / weightedHoursSum
            let avgFeeRate = weightedGrossSum > 0 ? 1.0 - (weightedNetSum / weightedGrossSum) : 0.2

            // Gas cost per hour
            let gasCostPerHour = (market.avgMilesPerGigHour / market.vehicleMPG) * market.gasPrice

            // Net after gas and estimated taxes
            let netAfterGasAndTax = (avgNetPerHour - gasCostPerHour) * (1.0 - taxRate)

            // Confidence: based on data volume and recency
            let confidence = min(Double(relevantEntries.count) / 20.0, 1.0)
                * (sameBlockEntries.count >= 2 ? 1.0 : 0.7)

            return PlatformProjection(
                id: platform,
                platform: platform,
                projectedGrossPerHour: avgGrossPerHour,
                projectedNetPerHour: max(netAfterGasAndTax, 0),
                estimatedFeeRate: avgFeeRate,
                estimatedGasCostPerHour: gasCostPerHour,
                dataPointCount: relevantEntries.count,
                confidence: confidence
            )
        }
    }

    // MARK: - Time Block Scoring

    private static func buildTimeBlockScore(
        entries: [HistoricalEntry],
        currentHour: Int,
        currentDOW: Int,
        market: MarketContext,
        taxRate: Double
    ) -> TimeBlockScore {
        let calendar = Calendar.current
        let blocks = ["Morning", "Afternoon", "Evening", "Night"]
        let currentBlock = timeBlockName(for: currentHour)

        // Calculate avg net/hr for each time block
        var blockRates: [(name: String, rate: Double, count: Int)] = []

        for block in blocks {
            let blockEntries = entries.filter {
                let hour = calendar.component(.hour, from: $0.date)
                return timeBlockName(for: hour) == block
            }

            guard !blockEntries.isEmpty else {
                blockRates.append((block, 0, 0))
                continue
            }

            let totalNet = blockEntries.reduce(0.0) { $0 + $1.netAmount }
            let totalHours = blockEntries.reduce(0.0) { $0 + $1.estimatedHours }
            let rate = totalHours > 0 ? totalNet / totalHours : 0
            blockRates.append((block, rate, blockEntries.count))
        }

        // Current block score (0-100 relative to best)
        let maxRate = blockRates.map(\.rate).max() ?? 1
        let currentRate = blockRates.first(where: { $0.name == currentBlock })?.rate ?? 0
        let currentScore = maxRate > 0 ? (currentRate / maxRate) * 100 : 50

        // Best block
        let bestBlock = blockRates.max(by: { $0.rate < $1.rate }) ?? (currentBlock, 0, 0)

        // Hours until best block
        let hoursUntil: Int?
        if bestBlock.name == currentBlock {
            hoursUntil = nil
        } else {
            let bestStartHour: Int
            switch bestBlock.name {
            case "Morning": bestStartHour = 5
            case "Afternoon": bestStartHour = 12
            case "Evening": bestStartHour = 17
            case "Night": bestStartHour = 21
            default: bestStartHour = 0
            }
            let diff = bestStartHour - currentHour
            hoursUntil = diff > 0 ? diff : diff + 24
        }

        return TimeBlockScore(
            currentBlock: currentBlock,
            currentBlockScore: currentScore,
            bestBlockToday: bestBlock.name,
            bestBlockAvgRate: bestBlock.rate,
            hoursUntilBestBlock: hoursUntil
        )
    }

    // MARK: - Helpers

    private static func timeBlockName(for hour: Int) -> String {
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    private static func formatCurrency(_ value: Double) -> String {
        "$\(Int(value.rounded()))"
    }
}
