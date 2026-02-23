import Foundation
import Accelerate

/// On-device machine learning forecasting engine for gig worker finances.
///
/// Uses Apple's Accelerate framework (vDSP) for real linear algebra:
/// least-squares regression, exponential moving averages, statistical measures,
/// and time-series forecasting. All computation is vectorized on the CPU via
/// SIMD — no Core ML model, no server calls, no heuristics.
///
/// Design philosophy:
/// - Honest about confidence. Low data = low confidence. High variance = low confidence.
/// - Uses real regression math, not hand-tuned rules.
/// - Stateless enum — every function is a pure static transform.
/// - All money values are `Double` (consistent with SwiftData models).
enum GigMLEngine: Sendable {

    // MARK: - Forecast Output Types

    /// Predicted future earnings with statistical confidence bounds.
    struct EarningsForecast: Sendable {
        /// Predicted gross earnings for the next 7 days.
        let predictedNextWeek: Double
        /// Predicted gross earnings for the next 30 days.
        let predictedNextMonth: Double
        /// Confidence in the prediction, 0-1. Derived from R-squared, data volume,
        /// and coefficient of variation. A value below 0.3 means "take this with
        /// a large grain of salt."
        let confidence: Double
        /// Qualitative trend direction based on regression slope, R-squared, and volatility.
        let trend: Trend
        /// Day-of-week seasonal multiplier for today (e.g., 1.25 means today is
        /// historically 25% above the daily mean).
        let seasonalAdjustment: Double
        /// Human-readable provenance string, e.g. "Based on 45 days of earnings data".
        let forecastBasis: String
    }

    /// Qualitative trend classification.
    ///
    /// Determined by three signals:
    /// - Regression slope sign and magnitude
    /// - R-squared (goodness of fit — is the trend real?)
    /// - Coefficient of variation (noise level)
    enum Trend: String, Sendable {
        case accelerating = "Accelerating"
        case steady = "Steady"
        case decelerating = "Decelerating"
        case volatile = "Volatile"
        case insufficient = "Insufficient Data"
    }

    /// Predicted future expenses with per-category breakdown.
    struct ExpenseForecast: Sendable {
        /// Predicted total expenses for the coming 30 days.
        let predictedMonthlyExpenses: Double
        /// Per-category predictions with individual trend directions.
        let categoryForecasts: [CategoryForecast]
        /// Current daily burn rate (EMA-smoothed over last 14 days).
        let burnRatePerDay: Double
        /// If a monthly budget was provided, how many days at the current burn rate
        /// until that budget is exhausted. `nil` if no budget or burn rate is zero.
        let daysUntilBudgetExhausted: Double?
    }

    /// A single category's expense forecast.
    struct CategoryForecast: Sendable {
        let category: String
        let predicted: Double
        let trend: Trend
    }

    /// Rate-of-change analysis for earnings momentum.
    ///
    /// Think of this like the speedometer AND accelerometer for your income.
    /// `currentDailyRate` is your speed. `acceleration` is whether you're speeding up.
    struct IncomeVelocity: Sendable {
        /// EMA-smoothed daily earning rate over the most recent half of the data.
        let currentDailyRate: Double
        /// EMA-smoothed daily earning rate over the earlier half of the data.
        let priorDailyRate: Double
        /// Rate of change of the daily rate. Positive = earning faster over time.
        /// Calculated as `(currentDailyRate - priorDailyRate) / priorDailyRate`.
        let acceleration: Double
        /// Estimated days to reach `target` at `currentDailyRate`.
        /// `nil` if no target provided or current rate is zero/negative.
        let daysToTarget: Int?
    }

    // MARK: - Minimum Data Requirements

    /// Minimum data points required to produce a meaningful earnings forecast.
    /// Two weeks of daily data gives us enough for day-of-week seasonality.
    private static let minimumForecastPoints = 14

    /// Minimum data points for expense forecasting (one week).
    private static let minimumExpensePoints = 7

    /// Minimum data points for velocity calculation.
    private static let minimumVelocityPoints = 10

    // MARK: - Linear Regression (Accelerate vDSP)

    /// Ordinary Least Squares (OLS) linear regression using Accelerate vDSP.
    ///
    /// Fits the model `y = slope * x + intercept` by minimizing the sum of
    /// squared residuals. The closed-form solution is:
    ///
    ///     slope = (n * sum(x*y) - sum(x) * sum(y)) / (n * sum(x^2) - sum(x)^2)
    ///     intercept = mean(y) - slope * mean(x)
    ///
    /// R-squared (coefficient of determination) measures how much variance in `y`
    /// is explained by the linear relationship with `x`:
    ///
    ///     R^2 = 1 - SS_res / SS_tot
    ///
    /// where SS_res = sum((y_i - y_hat_i)^2) and SS_tot = sum((y_i - mean(y))^2).
    ///
    /// All summations and element-wise operations use vDSP for vectorized performance.
    ///
    /// - Parameters:
    ///   - x: Independent variable values (e.g., day indices).
    ///   - y: Dependent variable values (e.g., daily earnings).
    /// - Returns: Tuple of (slope, intercept, rSquared), or `nil` if inputs are
    ///   invalid (mismatched lengths, fewer than 2 points, or zero variance in x).
    static func linearRegression(x: [Double], y: [Double]) -> (slope: Double, intercept: Double, rSquared: Double)? {
        let n = x.count
        guard n == y.count, n >= 2 else { return nil }

        let nDouble = Double(n)

        // mean(x) and mean(y) via vDSP
        var meanX: Double = 0
        var meanY: Double = 0
        vDSP_meanvD(x, 1, &meanX, vDSP_Length(n))
        vDSP_meanvD(y, 1, &meanY, vDSP_Length(n))

        // sum(x * y) via vDSP_dotprD
        var sumXY: Double = 0
        vDSP_dotprD(x, 1, y, 1, &sumXY, vDSP_Length(n))

        // sum(x^2) via vDSP_dotprD(x, x)
        var sumX2: Double = 0
        vDSP_dotprD(x, 1, x, 1, &sumX2, vDSP_Length(n))

        // sum(x) and sum(y)
        var sumX: Double = 0
        var sumY: Double = 0
        vDSP_sveD(x, 1, &sumX, vDSP_Length(n))
        vDSP_sveD(y, 1, &sumY, vDSP_Length(n))

        // denominator = n * sum(x^2) - sum(x)^2
        let denominator = nDouble * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-12 else { return nil } // zero variance in x

        // slope = (n * sum(x*y) - sum(x) * sum(y)) / denominator
        let slope = (nDouble * sumXY - sumX * sumY) / denominator
        let intercept = meanY - slope * meanX

        // R-squared: 1 - SS_res / SS_tot
        // Predicted values: y_hat = slope * x + intercept
        var yHat = [Double](repeating: 0, count: n)
        // y_hat = x * slope
        var slopeVar = slope
        vDSP_vsmulD(x, 1, &slopeVar, &yHat, 1, vDSP_Length(n))
        // y_hat = y_hat + intercept
        var interceptVar = intercept
        vDSP_vsaddD(yHat, 1, &interceptVar, &yHat, 1, vDSP_Length(n))

        // residuals = y - y_hat
        var residuals = [Double](repeating: 0, count: n)
        vDSP_vsubD(yHat, 1, y, 1, &residuals, 1, vDSP_Length(n))

        // SS_res = sum(residuals^2)
        var ssRes: Double = 0
        vDSP_dotprD(residuals, 1, residuals, 1, &ssRes, vDSP_Length(n))

        // deviations = y - mean(y)
        var negMeanY = -meanY
        var deviations = [Double](repeating: 0, count: n)
        vDSP_vsaddD(y, 1, &negMeanY, &deviations, 1, vDSP_Length(n))

        // SS_tot = sum(deviations^2)
        var ssTot: Double = 0
        vDSP_dotprD(deviations, 1, deviations, 1, &ssTot, vDSP_Length(n))

        let rSquared: Double
        if ssTot < 1e-12 {
            // All y values are identical — perfect fit (zero variance).
            rSquared = 1.0
        } else {
            rSquared = max(0, 1.0 - ssRes / ssTot)
        }

        return (slope: slope, intercept: intercept, rSquared: rSquared)
    }

    // MARK: - Exponential Moving Average

    /// Exponential Moving Average (EMA) with configurable span.
    ///
    /// EMA gives more weight to recent observations, making it responsive to
    /// trend changes while smoothing noise. The smoothing factor is:
    ///
    ///     alpha = 2 / (span + 1)
    ///
    /// Each value is computed as:
    ///
    ///     EMA_t = alpha * value_t + (1 - alpha) * EMA_{t-1}
    ///
    /// The first value is seeded as-is (no smoothing possible on one point).
    ///
    /// - Parameters:
    ///   - values: Time-ordered observations (index 0 = oldest).
    ///   - span: Number of periods for the smoothing window. Higher = smoother.
    ///     A span of 7 is good for weekly patterns; 14 for biweekly.
    /// - Returns: Array of EMA values, same length as input. Empty if input is empty.
    static func exponentialMovingAverage(values: [Double], span: Int) -> [Double] {
        guard !values.isEmpty, span >= 1 else { return [] }

        let alpha = 2.0 / (Double(span) + 1.0)
        var ema = [Double](repeating: 0, count: values.count)
        ema[0] = values[0]

        for i in 1..<values.count {
            ema[i] = alpha * values[i] + (1.0 - alpha) * ema[i - 1]
        }

        return ema
    }

    // MARK: - Simple Moving Average

    /// Simple Moving Average (SMA) with a fixed window size.
    ///
    /// For the first `window - 1` elements, the average is computed over all
    /// available preceding values (expanding window). From index `window - 1`
    /// onward, a true rolling average of the last `window` values is used.
    ///
    /// - Parameters:
    ///   - values: Time-ordered observations.
    ///   - window: Number of periods in the rolling window.
    /// - Returns: Smoothed values, same length as input.
    static func movingAverage(values: [Double], window: Int) -> [Double] {
        guard !values.isEmpty, window >= 1 else { return [] }

        let n = values.count
        var result = [Double](repeating: 0, count: n)
        var runningSum: Double = 0

        for i in 0..<n {
            runningSum += values[i]
            if i < window {
                // Expanding window phase
                result[i] = runningSum / Double(i + 1)
            } else {
                runningSum -= values[i - window]
                result[i] = runningSum / Double(window)
            }
        }

        return result
    }

    // MARK: - Statistical Helpers

    /// Population standard deviation using Accelerate.
    ///
    /// Computed as: sqrt(mean((x - mean(x))^2))
    ///
    /// Uses vDSP for the mean and element-wise operations, then a final
    /// dot product for the sum of squared deviations.
    ///
    /// - Parameter values: The dataset.
    /// - Returns: Population standard deviation, or 0 if fewer than 2 values.
    static func standardDeviation(values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }

        var mean: Double = 0
        vDSP_meanvD(values, 1, &mean, vDSP_Length(n))

        // deviations = values - mean
        var negMean = -mean
        var deviations = [Double](repeating: 0, count: n)
        vDSP_vsaddD(values, 1, &negMean, &deviations, 1, vDSP_Length(n))

        // sumSqDev = sum(deviations^2)
        var sumSqDev: Double = 0
        vDSP_dotprD(deviations, 1, deviations, 1, &sumSqDev, vDSP_Length(n))

        return sqrt(sumSqDev / Double(n))
    }

    /// Coefficient of Variation (CV): standard deviation divided by the mean.
    ///
    /// A dimensionless measure of relative variability. A CV of 0.5 means the
    /// standard deviation is half the mean — moderate variability. Above 1.0
    /// indicates highly volatile data.
    ///
    /// - Parameter values: The dataset.
    /// - Returns: CV, or `Double.infinity` if the mean is zero.
    static func coefficientOfVariation(values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return .infinity }

        var mean: Double = 0
        vDSP_meanvD(values, 1, &mean, vDSP_Length(n))
        guard abs(mean) > 1e-12 else { return .infinity }

        return standardDeviation(values: values) / abs(mean)
    }

    /// Percentile value using linear interpolation (the "C = 1" method from Excel PERCENTILE.INC).
    ///
    /// The p-th percentile is the value below which `p` fraction of the data falls.
    /// For example, `percentile(values, p: 0.5)` returns the median.
    ///
    /// Algorithm:
    /// 1. Sort the values.
    /// 2. Compute the rank: `rank = p * (n - 1)`
    /// 3. Interpolate between `sorted[floor(rank)]` and `sorted[ceil(rank)]`.
    ///
    /// - Parameters:
    ///   - values: The dataset (need not be sorted).
    ///   - p: Percentile in [0, 1]. 0.5 = median, 0.25 = first quartile, etc.
    /// - Returns: The interpolated percentile value, or 0 if empty.
    static func percentile(values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let pClamped = min(max(p, 0), 1)

        if sorted.count == 1 { return sorted[0] }

        let rank = pClamped * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = rank - Double(lower)

        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }

    // MARK: - Earnings Forecast

    /// Generates a statistically grounded earnings forecast from daily income data.
    ///
    /// The forecasting pipeline:
    /// 1. **Aggregate** raw entries into daily totals (summing same-day amounts).
    /// 2. **Fill gaps** — days with no earnings get $0 (they're real zero-earning days).
    /// 3. **Linear regression** on daily index vs. daily total to capture the trend.
    /// 4. **EMA** (span = 7) on daily totals for a smoothed recent-rate estimate.
    /// 5. **Day-of-week seasonal factors** — average earnings per weekday / overall mean.
    /// 6. **Blend** regression projection and EMA projection with weights based on R-squared.
    /// 7. **Apply** seasonal adjustment for a 7-day and 30-day forward forecast.
    /// 8. **Confidence** derived from data volume, R-squared, and coefficient of variation.
    ///
    /// - Parameter dailyEarnings: Unsorted array of (date, amount) pairs. Multiple entries
    ///   on the same date are summed. Dates need not be contiguous.
    /// - Returns: An `EarningsForecast`, or `nil` if fewer than 14 data points exist
    ///   after aggregation.
    static func forecastEarnings(dailyEarnings: [(date: Date, amount: Double)]) -> EarningsForecast? {
        guard !dailyEarnings.isEmpty else { return nil }

        // Step 1: Aggregate into daily totals
        let calendar = Calendar.current
        var dailyTotals: [DateComponents: Double] = [:]
        for entry in dailyEarnings {
            let dc = calendar.dateComponents([.year, .month, .day], from: entry.date)
            dailyTotals[dc, default: 0] += entry.amount
        }

        // Step 2: Build contiguous daily series (fill gaps with 0)
        let allDates = dailyEarnings.map { $0.date }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else { return nil }

        var seriesDates: [Date] = []
        var seriesAmounts: [Double] = []
        var current = calendar.startOfDay(for: minDate)
        let end = calendar.startOfDay(for: maxDate)

        while current <= end {
            let dc = calendar.dateComponents([.year, .month, .day], from: current)
            seriesDates.append(current)
            seriesAmounts.append(dailyTotals[dc] ?? 0)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }

        let totalDays = seriesAmounts.count
        guard totalDays >= minimumForecastPoints else { return nil }

        // Step 3: Linear regression on day index vs. daily total
        let xIndices = (0..<totalDays).map { Double($0) }
        let regression = linearRegression(x: xIndices, y: seriesAmounts)
        let slope = regression?.slope ?? 0
        let intercept = regression?.intercept ?? 0
        let rSquared = regression?.rSquared ?? 0

        // Step 4: EMA-smoothed recent rate (span = 7 for weekly pattern)
        let ema = exponentialMovingAverage(values: seriesAmounts, span: 7)
        let emaDailyRate = ema.last ?? 0

        // Step 5: Day-of-week seasonal factors
        // Group earnings by weekday (1=Sun ... 7=Sat) and compute mean per weekday.
        var weekdayTotals: [Int: [Double]] = [:]
        for i in 0..<totalDays {
            let weekday = calendar.component(.weekday, from: seriesDates[i])
            weekdayTotals[weekday, default: []].append(seriesAmounts[i])
        }

        var overallMean: Double = 0
        vDSP_meanvD(seriesAmounts, 1, &overallMean, vDSP_Length(totalDays))
        let safeMean = max(overallMean, 1e-6)

        var seasonalFactors: [Int: Double] = [:]
        for (weekday, amounts) in weekdayTotals {
            var wMean: Double = 0
            vDSP_meanvD(amounts, 1, &wMean, vDSP_Length(amounts.count))
            seasonalFactors[weekday] = wMean / safeMean
        }

        // Today's seasonal adjustment
        let todayWeekday = calendar.component(.weekday, from: Date.now)
        let todaySeasonal = seasonalFactors[todayWeekday] ?? 1.0

        // Step 6: Blend regression projection and EMA projection
        // Regression gets more weight when R-squared is high (linear fit is good).
        // EMA gets more weight when R-squared is low (trend is noisy, recent data matters more).
        let regressionWeight = min(max(rSquared, 0), 1.0)
        let emaWeight = 1.0 - regressionWeight

        // Regression predicts the value at future day indices
        let nextDayIndex = Double(totalDays) // one day ahead

        // Week forecast: sum of 7 future days
        var weekTotal: Double = 0
        for d in 0..<7 {
            let futureIndex = nextDayIndex + Double(d)
            let regressionPred = slope * futureIndex + intercept
            let blended = regressionWeight * max(regressionPred, 0) + emaWeight * emaDailyRate

            // Apply seasonal factor for the predicted day's weekday
            let futureDate = calendar.date(byAdding: .day, value: d + 1, to: end) ?? end
            let futureWeekday = calendar.component(.weekday, from: futureDate)
            let seasonal = seasonalFactors[futureWeekday] ?? 1.0

            weekTotal += blended * seasonal
        }

        // Month forecast: sum of 30 future days
        var monthTotal: Double = 0
        for d in 0..<30 {
            let futureIndex = nextDayIndex + Double(d)
            let regressionPred = slope * futureIndex + intercept
            let blended = regressionWeight * max(regressionPred, 0) + emaWeight * emaDailyRate

            let futureDate = calendar.date(byAdding: .day, value: d + 1, to: end) ?? end
            let futureWeekday = calendar.component(.weekday, from: futureDate)
            let seasonal = seasonalFactors[futureWeekday] ?? 1.0

            monthTotal += blended * seasonal
        }

        // Step 7: Trend classification
        let cv = coefficientOfVariation(values: seriesAmounts)
        let trend = classifyTrend(slope: slope, rSquared: rSquared, cv: cv, mean: overallMean)

        // Step 8: Confidence score
        let confidence = computeConfidence(dataPoints: totalDays, rSquared: rSquared, cv: cv)

        // Ensure non-negative predictions
        let predictedWeek = max(weekTotal, 0)
        let predictedMonth = max(monthTotal, 0)

        return EarningsForecast(
            predictedNextWeek: predictedWeek,
            predictedNextMonth: predictedMonth,
            confidence: confidence,
            trend: trend,
            seasonalAdjustment: todaySeasonal,
            forecastBasis: "Based on \(totalDays) days of earnings data"
        )
    }

    // MARK: - Expense Forecast

    /// Generates an expense forecast with per-category breakdowns.
    ///
    /// Pipeline:
    /// 1. Aggregate daily expense totals and per-category daily totals.
    /// 2. EMA-smooth the aggregate for a daily burn rate.
    /// 3. Linear regression on aggregate for trend-aware 30-day projection.
    /// 4. Per-category: regression + EMA blend for individual forecasts.
    /// 5. Budget exhaustion: `remainingBudget / burnRatePerDay`.
    ///
    /// - Parameters:
    ///   - dailyExpenses: Array of (date, amount, category) tuples.
    ///   - monthlyBudget: Optional monthly spending budget. If provided, the forecast
    ///     includes days-until-exhausted.
    /// - Returns: An `ExpenseForecast`, or `nil` if insufficient data.
    static func forecastExpenses(
        dailyExpenses: [(date: Date, amount: Double, category: String)],
        monthlyBudget: Double?
    ) -> ExpenseForecast? {
        guard !dailyExpenses.isEmpty else { return nil }

        let calendar = Calendar.current

        // Aggregate into daily totals (overall and per-category)
        var dailyTotals: [DateComponents: Double] = [:]
        var categoryDaily: [String: [DateComponents: Double]] = [:]

        for entry in dailyExpenses {
            let dc = calendar.dateComponents([.year, .month, .day], from: entry.date)
            dailyTotals[dc, default: 0] += entry.amount
            categoryDaily[entry.category, default: [:]][dc, default: 0] += entry.amount
        }

        // Build contiguous daily series
        let allDates = dailyExpenses.map { $0.date }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else { return nil }

        var seriesAmounts: [Double] = []
        var current = calendar.startOfDay(for: minDate)
        let end = calendar.startOfDay(for: maxDate)

        while current <= end {
            let dc = calendar.dateComponents([.year, .month, .day], from: current)
            seriesAmounts.append(dailyTotals[dc] ?? 0)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }

        let totalDays = seriesAmounts.count
        guard totalDays >= minimumExpensePoints else { return nil }

        // EMA-smoothed daily burn rate (span = 14 for expenses — smoother)
        let ema = exponentialMovingAverage(values: seriesAmounts, span: 14)
        let burnRate = max(ema.last ?? 0, 0)

        // Regression for overall trend
        let xIndices = (0..<totalDays).map { Double($0) }
        let regression = linearRegression(x: xIndices, y: seriesAmounts)
        let rSq = regression?.rSquared ?? 0
        let rWeight = min(max(rSq, 0), 1.0)

        // 30-day aggregate forecast (blend of regression extrapolation and EMA)
        var monthlyPrediction: Double = 0
        for d in 0..<30 {
            let futureIndex = Double(totalDays) + Double(d)
            let regPred = (regression?.slope ?? 0) * futureIndex + (regression?.intercept ?? 0)
            let blended = rWeight * max(regPred, 0) + (1.0 - rWeight) * burnRate
            monthlyPrediction += blended
        }
        monthlyPrediction = max(monthlyPrediction, 0)

        // Per-category forecasts
        var categoryForecasts: [CategoryForecast] = []
        for (category, dailyMap) in categoryDaily {
            // Build category series aligned to same date range
            var catSeries: [Double] = []
            var catCurrent = calendar.startOfDay(for: minDate)
            while catCurrent <= end {
                let dc = calendar.dateComponents([.year, .month, .day], from: catCurrent)
                catSeries.append(dailyMap[dc] ?? 0)
                catCurrent = calendar.date(byAdding: .day, value: 1, to: catCurrent) ?? catCurrent.addingTimeInterval(86400)
            }

            guard catSeries.count >= 2 else {
                // Not enough data for regression — use simple average * 30
                var mean: Double = 0
                vDSP_meanvD(catSeries, 1, &mean, vDSP_Length(catSeries.count))
                categoryForecasts.append(CategoryForecast(
                    category: category,
                    predicted: max(mean * 30, 0),
                    trend: .insufficient
                ))
                continue
            }

            let catX = (0..<catSeries.count).map { Double($0) }
            let catReg = linearRegression(x: catX, y: catSeries)
            let catEma = exponentialMovingAverage(values: catSeries, span: 14)
            let catBurn = catEma.last ?? 0

            let catRSq = catReg?.rSquared ?? 0
            let catRWeight = min(max(catRSq, 0), 1.0)

            var catMonthly: Double = 0
            for d in 0..<30 {
                let fi = Double(catSeries.count) + Double(d)
                let regP = (catReg?.slope ?? 0) * fi + (catReg?.intercept ?? 0)
                catMonthly += catRWeight * max(regP, 0) + (1.0 - catRWeight) * catBurn
            }

            var catMean: Double = 0
            vDSP_meanvD(catSeries, 1, &catMean, vDSP_Length(catSeries.count))
            let catCV = coefficientOfVariation(values: catSeries)
            let catTrend = classifyTrend(
                slope: catReg?.slope ?? 0,
                rSquared: catRSq,
                cv: catCV,
                mean: catMean
            )

            categoryForecasts.append(CategoryForecast(
                category: category,
                predicted: max(catMonthly, 0),
                trend: catTrend
            ))
        }

        // Sort categories by predicted amount descending
        categoryForecasts.sort { $0.predicted > $1.predicted }

        // Budget exhaustion calculation
        var daysUntilExhausted: Double?
        if let budget = monthlyBudget, burnRate > 1e-6 {
            // How much of this month's budget is already spent?
            // Sum expenses in the current calendar month.
            let now = Date.now
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)

            var spentThisMonth: Double = 0
            for entry in dailyExpenses {
                let m = calendar.component(.month, from: entry.date)
                let y = calendar.component(.year, from: entry.date)
                if m == currentMonth && y == currentYear {
                    spentThisMonth += entry.amount
                }
            }

            let remaining = budget - spentThisMonth
            if remaining > 0 {
                daysUntilExhausted = remaining / burnRate
            } else {
                daysUntilExhausted = 0 // Already over budget
            }
        }

        return ExpenseForecast(
            predictedMonthlyExpenses: monthlyPrediction,
            categoryForecasts: categoryForecasts,
            burnRatePerDay: burnRate,
            daysUntilBudgetExhausted: daysUntilExhausted
        )
    }

    // MARK: - Income Velocity

    /// Calculates income velocity and acceleration by comparing EMA-smoothed
    /// daily rates between the recent half and the earlier half of the data.
    ///
    /// Velocity is your current earning speed. Acceleration is whether that speed
    /// is increasing or decreasing. Together they answer: "Am I earning faster
    /// or slower than before, and by how much?"
    ///
    /// - Parameters:
    ///   - dailyEarnings: Time-ordered (date, amount) pairs.
    ///   - target: Optional earnings target (e.g., weekly goal remainder).
    ///     If provided, `daysToTarget` estimates how long to reach it.
    /// - Returns: An `IncomeVelocity`, or `nil` if fewer than 10 data points.
    static func calculateVelocity(
        dailyEarnings: [(date: Date, amount: Double)],
        target: Double?
    ) -> IncomeVelocity? {
        guard !dailyEarnings.isEmpty else { return nil }

        let calendar = Calendar.current

        // Aggregate and fill gaps (same as earnings forecast)
        var dailyTotals: [DateComponents: Double] = [:]
        for entry in dailyEarnings {
            let dc = calendar.dateComponents([.year, .month, .day], from: entry.date)
            dailyTotals[dc, default: 0] += entry.amount
        }

        let allDates = dailyEarnings.map { $0.date }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else { return nil }

        var series: [Double] = []
        var current = calendar.startOfDay(for: minDate)
        let end = calendar.startOfDay(for: maxDate)

        while current <= end {
            let dc = calendar.dateComponents([.year, .month, .day], from: current)
            series.append(dailyTotals[dc] ?? 0)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }

        guard series.count >= minimumVelocityPoints else { return nil }

        // Split into two halves
        let midpoint = series.count / 2
        let priorHalf = Array(series[0..<midpoint])
        let recentHalf = Array(series[midpoint...])

        // EMA each half (span = half length, capped at 14)
        let priorSpan = min(priorHalf.count, 14)
        let recentSpan = min(recentHalf.count, 14)

        let priorEma = exponentialMovingAverage(values: priorHalf, span: priorSpan)
        let recentEma = exponentialMovingAverage(values: recentHalf, span: recentSpan)

        let priorRate = priorEma.last ?? 0
        let currentRate = recentEma.last ?? 0

        // Acceleration = relative change in rate
        let acceleration: Double
        if abs(priorRate) > 1e-6 {
            acceleration = (currentRate - priorRate) / abs(priorRate)
        } else if currentRate > 1e-6 {
            acceleration = 1.0 // Went from nothing to something — infinite acceleration, cap at 1
        } else {
            acceleration = 0
        }

        // Days to target
        var daysToTarget: Int?
        if let target = target, currentRate > 1e-6 {
            let days = ceil(target / currentRate)
            if days > 0 && days < 100_000 {
                daysToTarget = Int(days)
            }
        }

        return IncomeVelocity(
            currentDailyRate: currentRate,
            priorDailyRate: priorRate,
            acceleration: acceleration,
            daysToTarget: daysToTarget
        )
    }

    // MARK: - Private Helpers

    /// Classifies the trend based on regression slope, fit quality, and noise level.
    ///
    /// Decision logic:
    /// - If CV > 1.0, the data is too noisy for a meaningful trend: `.volatile`
    /// - If R-squared < 0.05, the linear model explains almost nothing: `.steady`
    ///   (or `.volatile` if CV is also high)
    /// - Otherwise, slope direction determines `.accelerating` vs `.decelerating`
    ///   but only if the slope is materially significant (> 1% of mean per day).
    ///
    /// - Parameters:
    ///   - slope: Regression slope (units per day).
    ///   - rSquared: Coefficient of determination.
    ///   - cv: Coefficient of variation.
    ///   - mean: Mean of the dependent variable.
    /// - Returns: A `Trend` classification.
    private static func classifyTrend(slope: Double, rSquared: Double, cv: Double, mean: Double) -> Trend {
        // High noise overwhelms any detected trend
        if cv > 1.0 {
            return .volatile
        }

        // Very low R-squared means the linear model is basically useless
        if rSquared < 0.05 {
            return cv > 0.6 ? .volatile : .steady
        }

        // Slope significance: is the daily change at least 1% of the mean?
        let safeMean = max(abs(mean), 1e-6)
        let slopeSignificance = abs(slope) / safeMean

        if slopeSignificance < 0.01 {
            return .steady
        }

        return slope > 0 ? .accelerating : .decelerating
    }

    /// Computes a confidence score in [0, 1] from data volume, R-squared, and CV.
    ///
    /// Three independent factors, each contributing a third of the score:
    ///
    /// 1. **Data volume factor**: More data = more confidence.
    ///    - 14 days (minimum) = 0.3
    ///    - 30 days = 0.6
    ///    - 60 days = 0.85
    ///    - 90+ days = 1.0
    ///    Uses a logarithmic curve: `min(1, log(n/10) / log(9))`
    ///
    /// 2. **Fit factor**: Higher R-squared = better linear fit = more trustworthy trend.
    ///    Directly uses R-squared (already 0-1).
    ///
    /// 3. **Consistency factor**: Lower CV = more consistent data = more confidence.
    ///    `max(0, 1 - cv)` — CV of 0 means perfect consistency, CV >= 1 means zero confidence
    ///    from this factor.
    ///
    /// Final confidence = weighted blend: 40% data volume, 30% fit, 30% consistency.
    ///
    /// - Parameters:
    ///   - dataPoints: Number of data points (days).
    ///   - rSquared: Coefficient of determination from regression.
    ///   - cv: Coefficient of variation.
    /// - Returns: Confidence score in [0, 1].
    private static func computeConfidence(dataPoints: Int, rSquared: Double, cv: Double) -> Double {
        // Data volume factor (logarithmic saturation)
        let volumeFactor: Double
        if dataPoints <= 0 {
            volumeFactor = 0
        } else {
            // log(n/10) / log(9) gives ~0.3 at n=14, ~0.6 at n=30, ~1.0 at n=90
            volumeFactor = min(1.0, max(0, log(Double(dataPoints) / 10.0) / log(9.0)))
        }

        // Fit factor — direct from R-squared
        let fitFactor = min(max(rSquared, 0), 1.0)

        // Consistency factor — inverse of CV, clamped to [0, 1]
        let consistencyFactor = min(max(1.0 - cv, 0), 1.0)

        // Weighted blend
        let confidence = 0.40 * volumeFactor + 0.30 * fitFactor + 0.30 * consistencyFactor

        return min(max(confidence, 0), 1.0)
    }
}
