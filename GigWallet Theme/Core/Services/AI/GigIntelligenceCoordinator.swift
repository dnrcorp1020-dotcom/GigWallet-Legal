import Foundation
import SwiftData

/// The central AI orchestrator for GigWallet.
///
/// This coordinator runs all AI/ML engines against the user's data and produces
/// a unified intelligence report. It's the single entry point that the Dashboard
/// calls to get all AI-generated insights, forecasts, anomalies, and trends.
///
/// Architecture:
/// ```
///  ┌─────────────────────────────────────────────┐
///  │          GigIntelligenceCoordinator          │
///  │  (orchestrates all engines, caches results)  │
///  └─────────────┬───────────────────────────────┘
///                │
///    ┌───────────┼────────────┬──────────────┐
///    ▼           ▼            ▼              ▼
///  GigMLEngine  TrendAnalyzer  Anomaly     Market
///  (Forecast)   (Decompose)   Detection   Intelligence
///    ▼           ▼            ▼              ▼
///  SmartCat ML  InsightsEngine (upgraded)   External APIs
/// ```
///
/// All computation happens off the main thread. Results are cached and refreshed
/// when underlying data changes.
@MainActor
@Observable
final class GigIntelligenceCoordinator {

    // MARK: - Intelligence Report

    /// The unified output from all AI engines.
    struct IntelligenceReport {
        /// ML-powered earnings forecast
        let earningsForecast: GigMLEngine.EarningsForecast?

        /// ML-powered expense forecast
        let expenseForecast: GigMLEngine.ExpenseForecast?

        /// Time-series trend analysis
        let earningsTrend: TrendAnalyzer.TrendResult?
        let expenseTrend: TrendAnalyzer.TrendResult?
        let profitTrend: TrendAnalyzer.TrendResult?

        /// Multi-metric correlations and narrative
        let multiMetricTrend: TrendAnalyzer.MultiMetricTrend?

        /// Statistical anomalies detected
        let anomalies: [AnomalyDetectionEngine.Anomaly]

        /// Income velocity (acceleration/deceleration)
        let incomeVelocity: GigMLEngine.IncomeVelocity?

        /// Market context from external data
        let marketInsights: [ContextualInsight]

        /// ML-enhanced categorization model status
        let categorizationModelAccuracy: Double
        let categorizationTrainingSize: Int

        /// When this report was generated
        let generatedAt: Date

        /// Human-readable narrative combining all signals
        let narrativeSummary: String

        /// Top 5 most important insights, prioritized across all engines
        let topInsights: [PrioritizedInsight]
    }

    /// A single insight that has been scored and ranked across all AI engines.
    struct PrioritizedInsight: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
        let color: String           // BrandColors key
        let score: Double            // 0-1, composite importance score
        let source: String           // Which engine produced this
        let category: InsightCategory
        let actionLabel: String?
    }

    enum InsightCategory: String {
        case forecast = "Forecast"
        case trend = "Trend"
        case anomaly = "Anomaly"
        case market = "Market"
        case optimization = "Optimization"
        case risk = "Risk"
        case opportunity = "Opportunity"
    }

    // MARK: - State

    /// The latest intelligence report
    private(set) var currentReport: IntelligenceReport?

    /// Whether the coordinator is currently running analysis
    private(set) var isAnalyzing = false

    /// Last time analysis was run
    private(set) var lastAnalysisTime: Date?

    /// The market intelligence service
    let marketService: MarketIntelligenceService

    /// The ML categorization engine
    let categorizationML: SmartCategorizationML

    // MARK: - Init

    init(
        marketService: MarketIntelligenceService = .shared,
        categorizationML: SmartCategorizationML = .shared
    ) {
        self.marketService = marketService
        self.categorizationML = categorizationML
    }

    // MARK: - Analysis

    /// Run full intelligence analysis on the user's data.
    ///
    /// This is the main entry point. Call it from the Dashboard's `.task` modifier
    /// or when data changes significantly.
    ///
    /// All heavy computation runs on background threads via `nonisolated` helpers.
    func analyze(
        incomeEntries: [IncomeEntry],
        expenseEntries: [ExpenseEntry],
        mileageTrips: [MileageTrip],
        taxPayments: [TaxPayment],
        profile: UserProfile?,
        weeklyGoal: Double
    ) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Snapshot data for background processing (value types, no SwiftData refs)
        let incomeSnapshots = incomeEntries.map { entry in
            IncomeSnapshot(
                date: entry.entryDate,
                grossAmount: entry.grossAmount,
                netAmount: entry.netAmount,
                fees: entry.platformFees,
                platform: entry.platform.displayName
            )
        }

        let expenseSnapshots = expenseEntries.map { entry in
            ExpenseSnapshot(
                date: entry.expenseDate,
                amount: entry.amount,
                category: entry.category.rawValue,
                vendor: entry.vendor,
                isDeductible: entry.isDeductible
            )
        }

        let stateCode = profile?.stateCode ?? "CA"
        let platforms = Array(Set(incomeEntries.map { $0.platform.displayName }))
        let yearlyIncome = incomeEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0.0) { $0 + $1.netAmount }
        let yearlyExpenses = expenseEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0.0) { $0 + $1.amount }
        let yearlyMileage = mileageTrips
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0.0) { $0 + $1.miles }

        // Calculate hourly rate from income data
        let totalHours = incomeEntries.reduce(0.0) { $0 + $1.platform.estimatedHoursPerEntry }
        let actualHourlyRate = totalHours > 0 ? yearlyIncome / totalHours : 0

        // Run all AI engines concurrently
        async let forecastResult = runForecasting(income: incomeSnapshots, expenses: expenseSnapshots)
        async let trendResult = runTrendAnalysis(income: incomeSnapshots, expenses: expenseSnapshots)
        async let anomalyResult = runAnomalyDetection(income: incomeSnapshots, expenses: expenseSnapshots)
        async let velocityResult = runVelocityAnalysis(income: incomeSnapshots, weeklyGoal: weeklyGoal)
        async let marketResult = runMarketIntelligence(
            yearlyIncome: yearlyIncome,
            yearlyExpenses: yearlyExpenses,
            yearlyMileage: yearlyMileage,
            hourlyRate: actualHourlyRate,
            platforms: platforms,
            stateCode: stateCode
        )

        // Await all results
        let (forecasts, trends, anomalies, velocity, marketInsights) = await (
            forecastResult, trendResult, anomalyResult, velocityResult, marketResult
        )

        // Train ML categorization on expense history
        trainCategorizationModel(expenses: expenseSnapshots)

        // Generate narrative summary
        let narrative = generateNarrative(
            forecast: forecasts.earnings,
            trend: trends.earnings,
            anomalies: anomalies,
            velocity: velocity
        )

        // Prioritize top insights
        let topInsights = prioritizeInsights(
            forecast: forecasts.earnings,
            expenseForecast: forecasts.expenses,
            trends: trends,
            anomalies: anomalies,
            velocity: velocity,
            marketInsights: marketInsights
        )

        // Build the report
        currentReport = IntelligenceReport(
            earningsForecast: forecasts.earnings,
            expenseForecast: forecasts.expenses,
            earningsTrend: trends.earnings,
            expenseTrend: trends.expenses,
            profitTrend: trends.profit,
            multiMetricTrend: trends.multiMetric,
            anomalies: anomalies,
            incomeVelocity: velocity,
            marketInsights: marketInsights,
            categorizationModelAccuracy: categorizationML.estimatedAccuracy,
            categorizationTrainingSize: categorizationML.trainingSize,
            generatedAt: Date.now,
            narrativeSummary: narrative,
            topInsights: topInsights
        )

        lastAnalysisTime = Date.now
    }

    // MARK: - Engine Runners (Background)

    private func runForecasting(
        income: [IncomeSnapshot],
        expenses: [ExpenseSnapshot]
    ) async -> (earnings: GigMLEngine.EarningsForecast?, expenses: GigMLEngine.ExpenseForecast?) {
        // Build daily aggregates
        let dailyEarnings = aggregateDaily(income.map { (date: $0.date, value: $0.netAmount) })
        let expenseWithCategory = expenses.map { (date: $0.date, amount: $0.amount, category: $0.category) }

        let earningsForecast = GigMLEngine.forecastEarnings(
            dailyEarnings: toAmountTuples(dailyEarnings)
        )
        let expenseForecast = GigMLEngine.forecastExpenses(
            dailyExpenses: expenseWithCategory,
            monthlyBudget: nil
        )

        return (earningsForecast, expenseForecast)
    }

    private func runTrendAnalysis(
        income: [IncomeSnapshot],
        expenses: [ExpenseSnapshot]
    ) async -> (
        earnings: TrendAnalyzer.TrendResult?,
        expenses: TrendAnalyzer.TrendResult?,
        profit: TrendAnalyzer.TrendResult?,
        multiMetric: TrendAnalyzer.MultiMetricTrend?
    ) {
        let dailyEarnings = aggregateDaily(income.map { (date: $0.date, value: $0.netAmount) })
        let dailyExpenses = aggregateDaily(expenses.map { (date: $0.date, value: $0.amount) })

        let earningsTrend = TrendAnalyzer.analyzeTrend(
            dailyValues: dailyEarnings,
            label: "Earnings"
        )
        let expenseTrend = TrendAnalyzer.analyzeTrend(
            dailyValues: dailyExpenses,
            label: "Expenses"
        )

        // Profit trend: daily earnings - daily expenses
        let dailyProfit = buildDailyProfit(earnings: dailyEarnings, expenses: dailyExpenses)
        let profitTrend = TrendAnalyzer.analyzeTrend(
            dailyValues: dailyProfit,
            label: "Profit"
        )

        // Daily fee data for multi-metric
        let dailyFees = aggregateDaily(income.map { (date: $0.date, value: $0.fees) })

        let multiMetric = TrendAnalyzer.analyzeMultiMetric(
            dailyEarnings: dailyEarnings,
            dailyExpenses: dailyExpenses,
            dailyFees: dailyFees
        )

        return (earningsTrend, expenseTrend, profitTrend, multiMetric)
    }

    private func runAnomalyDetection(
        income: [IncomeSnapshot],
        expenses: [ExpenseSnapshot]
    ) async -> [AnomalyDetectionEngine.Anomaly] {
        let earningsData = income.map {
            AnomalyDetectionEngine.EarningsEntry(
                date: $0.date,
                amount: $0.netAmount,
                platform: $0.platform
            )
        }
        let expenseData = expenses.map {
            AnomalyDetectionEngine.ExpenseEntry(
                date: $0.date,
                amount: $0.amount,
                category: $0.category
            )
        }
        let feeData = income.map {
            AnomalyDetectionEngine.FeeEntry(
                date: $0.date,
                grossAmount: $0.grossAmount,
                fees: $0.fees,
                platform: $0.platform
            )
        }

        return AnomalyDetectionEngine.analyzeAll(
            earnings: earningsData,
            expenses: expenseData,
            fees: feeData
        )
    }

    private func runVelocityAnalysis(
        income: [IncomeSnapshot],
        weeklyGoal: Double
    ) async -> GigMLEngine.IncomeVelocity? {
        let dailyEarnings = aggregateDaily(income.map { (date: $0.date, value: $0.netAmount) })
        return GigMLEngine.calculateVelocity(
            dailyEarnings: toAmountTuples(dailyEarnings),
            target: weeklyGoal > 0 ? weeklyGoal * 4.33 : nil // Monthly target
        )
    }

    private func runMarketIntelligence(
        yearlyIncome: Double,
        yearlyExpenses: Double,
        yearlyMileage: Double,
        hourlyRate: Double,
        platforms: [String],
        stateCode: String
    ) async -> [ContextualInsight] {
        await marketService.refreshIfNeeded(stateCode: stateCode)
        return marketService.generateContextualInsights(
            userIncome: yearlyIncome,
            userExpenses: yearlyExpenses,
            userMileage: yearlyMileage,
            userHourlyRate: hourlyRate,
            platforms: platforms
        )
    }

    // MARK: - ML Training

    private func trainCategorizationModel(expenses: [ExpenseSnapshot]) {
        let examples = expenses.map {
            SmartCategorizationML.TrainingExample(
                description: $0.vendor,
                merchantName: nil,
                amount: $0.amount,
                category: $0.category,
                timestamp: $0.date
            )
        }

        if !examples.isEmpty && examples.count > categorizationML.trainingSize {
            categorizationML.trainBatch(examples: examples)
        }
    }

    // MARK: - Narrative Generation

    /// Generates a human-readable narrative combining signals from all engines.
    private func generateNarrative(
        forecast: GigMLEngine.EarningsForecast?,
        trend: TrendAnalyzer.TrendResult?,
        anomalies: [AnomalyDetectionEngine.Anomaly],
        velocity: GigMLEngine.IncomeVelocity?
    ) -> String {
        var parts: [String] = []

        // Trend narrative
        if let trend = trend {
            switch trend.direction {
            case .strongUp:
                parts.append("Your earnings are in a strong uptrend, growing \(CurrencyFormatter.format(trend.weeklyChange))/week.")
            case .moderateUp:
                parts.append("Earnings are trending up moderately.")
            case .flat:
                parts.append("Your earnings have been steady recently.")
            case .moderateDown:
                parts.append("Your earnings have been declining — down \(CurrencyFormatter.format(abs(trend.weeklyChange)))/week.")
            case .strongDown:
                parts.append("Earnings are dropping significantly. Consider adjusting your schedule.")
            }
        }

        // Forecast narrative
        if let forecast = forecast, forecast.confidence > 0.3 {
            parts.append("ML projects \(CurrencyFormatter.format(forecast.predictedNextWeek)) next week (\(Int(forecast.confidence * 100))% confidence).")
        }

        // Anomaly narrative
        let criticalAnomalies = anomalies.filter { $0.severity == .critical }
        if !criticalAnomalies.isEmpty {
            parts.append("\(criticalAnomalies.count) anomal\(criticalAnomalies.count == 1 ? "y" : "ies") detected requiring attention.")
        }

        // Velocity narrative
        if let velocity = velocity, velocity.acceleration != 0 {
            if velocity.acceleration > 0 {
                parts.append("Your earning rate is accelerating.")
            } else {
                parts.append("Your earning rate is decelerating.")
            }
        }

        return parts.isEmpty ? "Collecting data for AI analysis. Keep logging income and expenses." : parts.joined(separator: " ")
    }

    // MARK: - Insight Prioritization

    /// Scores and ranks insights from all engines into a unified top-5 list.
    private func prioritizeInsights(
        forecast: GigMLEngine.EarningsForecast?,
        expenseForecast: GigMLEngine.ExpenseForecast?,
        trends: (earnings: TrendAnalyzer.TrendResult?, expenses: TrendAnalyzer.TrendResult?, profit: TrendAnalyzer.TrendResult?, multiMetric: TrendAnalyzer.MultiMetricTrend?),
        anomalies: [AnomalyDetectionEngine.Anomaly],
        velocity: GigMLEngine.IncomeVelocity?,
        marketInsights: [ContextualInsight]
    ) -> [PrioritizedInsight] {
        var insights: [PrioritizedInsight] = []

        // Anomalies (highest priority — something unusual happened)
        for anomaly in anomalies.prefix(3) {
            let score: Double
            switch anomaly.severity {
            case .critical: score = 0.95
            case .warning: score = 0.75
            case .info: score = 0.50
            }

            insights.append(PrioritizedInsight(
                title: anomaly.type.rawValue,
                detail: anomaly.description,
                icon: "exclamationmark.triangle.fill",
                color: anomaly.severity == .critical ? "destructive" : "warning",
                score: score,
                source: "Anomaly Detection",
                category: .anomaly,
                actionLabel: anomaly.recommendation
            ))
        }

        // Forecast insight
        if let forecast = forecast, forecast.confidence > 0.3 {
            let icon: String
            let color: String
            switch forecast.trend {
            case .accelerating:
                icon = "chart.line.uptrend.xyaxis"
                color = "success"
            case .decelerating:
                icon = "chart.line.downtrend.xyaxis"
                color = "warning"
            case .volatile:
                icon = "waveform.path.ecg"
                color = "info"
            default:
                icon = "chart.line.flattrend.xyaxis"
                color = "primary"
            }

            insights.append(PrioritizedInsight(
                title: "Next Week: \(CurrencyFormatter.format(forecast.predictedNextWeek))",
                detail: "\(forecast.trend.rawValue) trend. \(forecast.forecastBasis)",
                icon: icon,
                color: color,
                score: 0.80 * forecast.confidence,
                source: "ML Forecast",
                category: .forecast,
                actionLabel: nil
            ))
        }

        // Trend insights
        if let trend = trends.earnings {
            if trend.direction == .strongDown || trend.direction == .moderateDown {
                insights.append(PrioritizedInsight(
                    title: "Earnings \(trend.direction.rawValue)",
                    detail: trend.summary,
                    icon: "arrow.down.right",
                    color: "warning",
                    score: 0.85,
                    source: "Trend Analysis",
                    category: .trend,
                    actionLabel: nil
                ))
            } else if trend.direction == .strongUp {
                insights.append(PrioritizedInsight(
                    title: "Earnings \(trend.direction.rawValue)",
                    detail: trend.summary,
                    icon: "arrow.up.right",
                    color: "success",
                    score: 0.70,
                    source: "Trend Analysis",
                    category: .trend,
                    actionLabel: nil
                ))
            }
        }

        // Velocity insight
        if let velocity = velocity, let daysToTarget = velocity.daysToTarget, daysToTarget > 0 {
            insights.append(PrioritizedInsight(
                title: "Goal in \(daysToTarget) days",
                detail: "At \(CurrencyFormatter.format(velocity.currentDailyRate))/day, you'll hit your target in \(daysToTarget) days.",
                icon: "target",
                color: "primary",
                score: 0.60,
                source: "Velocity Engine",
                category: .forecast,
                actionLabel: nil
            ))
        }

        // Market insights
        for mi in marketInsights.prefix(2) {
            insights.append(PrioritizedInsight(
                title: mi.title,
                detail: mi.detail,
                icon: mi.icon,
                color: "info",
                score: 0.50 * mi.confidence,
                source: "Market Intelligence",
                category: .market,
                actionLabel: nil
            ))
        }

        // Sort by score and take top 5
        return Array(insights.sorted { $0.score > $1.score }.prefix(5))
    }

    // MARK: - Data Aggregation Helpers

    /// Aggregate timestamped values into daily totals.
    /// Returns tuples with `value` label to match TrendAnalyzer's expected signature.
    private func aggregateDaily(_ data: [(date: Date, value: Double)]) -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        var dailyTotals: [Date: Double] = [:]

        for item in data {
            let day = calendar.startOfDay(for: item.date)
            dailyTotals[day, default: 0] += item.value
        }

        return dailyTotals
            .map { (date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Convert from TrendAnalyzer format `(date:, value:)` to GigMLEngine format `(date:, amount:)`.
    private func toAmountTuples(_ data: [(date: Date, value: Double)]) -> [(date: Date, amount: Double)] {
        data.map { (date: $0.date, amount: $0.value) }
    }

    /// Build daily profit series from daily earnings and expenses.
    private func buildDailyProfit(
        earnings: [(date: Date, value: Double)],
        expenses: [(date: Date, value: Double)]
    ) -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        var earningsByDay: [Date: Double] = [:]
        var expensesByDay: [Date: Double] = [:]

        for e in earnings { earningsByDay[calendar.startOfDay(for: e.date)] = e.value }
        for e in expenses { expensesByDay[calendar.startOfDay(for: e.date)] = e.value }

        let allDays = Set(Array(earningsByDay.keys) + Array(expensesByDay.keys))
        return allDays.map { day in
            (date: day, value: (earningsByDay[day] ?? 0) - (expensesByDay[day] ?? 0))
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Value Type Snapshots

    struct IncomeSnapshot {
        let date: Date
        let grossAmount: Double
        let netAmount: Double
        let fees: Double
        let platform: String
    }

    struct ExpenseSnapshot {
        let date: Date
        let amount: Double
        let category: String
        let vendor: String
        let isDeductible: Bool
    }
}
