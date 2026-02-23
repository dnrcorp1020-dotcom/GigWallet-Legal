import Foundation
import Accelerate

/// Time-series trend analysis engine for gig worker financial data.
///
/// Performs real statistical trend decomposition, change-point detection, and
/// linear regression using Apple's Accelerate (vDSP) framework for vectorized
/// performance. All methods are stateless and static — no retained state, no
/// server calls, purely on-device math.
///
/// **Statistical Foundations:**
/// - Ordinary Least Squares (OLS) regression for trend estimation
/// - Classical additive decomposition (Y = Trend + Seasonal + Residual)
/// - Binary segmentation with Welch's t-test for change-point detection
/// - Pearson product-moment correlation for multi-metric analysis
/// - Exponential moving averages for momentum scoring
///
/// Requires a minimum of 14 daily observations to produce meaningful results.
/// Returns `nil` when data is insufficient rather than hallucinating trends.
enum TrendAnalyzer: Sendable {

    // MARK: - Configuration

    /// Minimum number of daily observations required for trend analysis.
    /// Two full weeks gives at least two full seasonal (weekly) cycles.
    private static let minimumDataPoints = 14

    /// p-value threshold for statistical significance in change-point detection.
    /// Using 0.01 (99% confidence) to avoid flagging noise as real shifts.
    private static let significanceThreshold = 0.01

    // MARK: - Core Types

    /// The complete result of a trend analysis on a single time series.
    ///
    /// Combines linear regression, seasonal decomposition, change-point detection,
    /// and forecasting into a single actionable summary.
    struct TrendResult: Sendable {
        /// Overall direction classification based on slope and R-squared.
        let direction: TrendDirection

        /// Goodness-of-fit from R-squared (0 = no trend, 1 = perfect linear trend).
        /// Values above 0.3 indicate a meaningful trend for financial data.
        let strength: Double

        /// Rate of change in dollars per day from the OLS regression slope.
        let slope: Double

        /// Projected weekly change: `slope * 7`.
        let weeklyChange: Double

        /// Projected monthly change: `slope * 30`.
        let monthlyChange: Double

        /// Day-of-week multipliers where 1.0 = average.
        /// Key is weekday number (1 = Sunday, 7 = Saturday).
        /// A value of 1.3 on Saturday means Saturdays are 30% above average.
        let seasonalFactors: [Int: Double]

        /// Points where the trend significantly shifted direction or level.
        let changePoints: [ChangePoint]

        /// Predicted total earnings/expenses for the next 7 days,
        /// combining the linear trend with seasonal day-of-week factors.
        let forecast7Day: Double

        /// Predicted total earnings/expenses for the next 30 days.
        let forecast30Day: Double

        /// Coefficient of variation of the residuals (std dev / mean).
        /// Higher values indicate more day-to-day unpredictability.
        /// Below 0.5 is relatively stable for gig work; above 1.0 is very volatile.
        let volatility: Double

        /// Human-readable trend description combining direction, rate, and context.
        /// Example: "Moderate Uptrend — earnings growing ~$8.50/day ($59.50/week).
        /// Strongest days: Friday, Saturday. One significant shift detected on Jan 15."
        let summary: String
    }

    /// Directional classification of a trend based on slope magnitude and significance.
    ///
    /// Thresholds are calibrated for gig worker daily earnings:
    /// - Strong: > $5/day change with R² > 0.3
    /// - Moderate: > $2/day change with R² > 0.15
    /// - Flat: everything else
    enum TrendDirection: String, Sendable {
        case strongUp = "Strong Uptrend"
        case moderateUp = "Moderate Uptrend"
        case flat = "Flat"
        case moderateDown = "Moderate Downtrend"
        case strongDown = "Strong Downtrend"
    }

    /// A detected structural break in the time series where the mean level shifted.
    ///
    /// Detected via binary segmentation with Welch's t-test. Each change point
    /// represents a statistically significant (p < 0.01) shift in average daily value.
    struct ChangePoint: Sendable {
        /// The date on which the shift occurred.
        let date: Date

        /// Average daily value in the segment before this point.
        let beforeAvg: Double

        /// Average daily value in the segment after this point.
        let afterAvg: Double

        /// Percent change: `(afterAvg - beforeAvg) / beforeAvg * 100`.
        let percentChange: Double

        /// Human-readable description, e.g. "Earnings jumped 35% around Jan 15"
        let description: String
    }

    /// Result of classical additive time-series decomposition: Y = T + S + R.
    ///
    /// The decomposition separates observed values into three components:
    /// - **Trend (T):** The long-term direction, smoothed via centered moving average.
    /// - **Seasonal (S):** Repeating weekly pattern (e.g., weekends are always higher).
    /// - **Residual (R):** Whatever is left — noise, one-off events, unexplained variance.
    ///
    /// Seasonal strength measures how much of the detrended variance is explained
    /// by the weekly pattern vs. random noise.
    struct SeasonalDecomposition: Sendable {
        /// Smoothed trend component from centered moving average.
        /// Length matches input; edges are extrapolated from nearest available value.
        let trend: [Double]

        /// Weekly seasonal component. Repeating pattern of length `period`.
        /// Values represent deviation from trend (positive = above trend).
        let seasonal: [Double]

        /// Residual (irregular) component: `Y - T - S`.
        /// Large residuals indicate unusual days that break the normal pattern.
        let residual: [Double]

        /// Fraction of detrended variance explained by seasonality (0 to 1).
        /// Calculated as `1 - var(residual) / var(Y - trend)`.
        /// Above 0.3 indicates meaningful weekly patterns.
        let seasonalStrength: Double
    }

    /// Combined trend analysis across earnings, expenses, fees, and derived profit.
    struct MultiMetricTrend: Sendable {
        /// Trend analysis of gross earnings.
        let earningsTrend: TrendResult?

        /// Trend analysis of total expenses.
        let expenseTrend: TrendResult?

        /// Trend analysis of net profit (earnings - expenses).
        let profitTrend: TrendResult?

        /// Trend analysis of platform fee rates (fees / earnings).
        let feeRateTrend: TrendResult?

        /// Pairwise Pearson correlations between metrics.
        /// Each tuple: (metric1 name, metric2 name, correlation coefficient r).
        let correlations: [(metric1: String, metric2: String, correlation: Double)]

        /// Narrative summary combining all trends into actionable insight.
        /// Example: "Your earnings are rising while expenses are flat — profit margin
        /// is improving. Fee rates are uncorrelated with volume."
        let narrativeSummary: String
    }

    // MARK: - Primary Analysis

    /// Performs complete trend analysis on a daily time series.
    ///
    /// This is the main entry point. It chains together gap-filling, seasonal
    /// decomposition, OLS regression, change-point detection, and forecasting
    /// into a single `TrendResult`.
    ///
    /// - Parameters:
    ///   - dailyValues: Array of (date, value) pairs. Does not need to be contiguous —
    ///     missing days will be filled with zeros.
    ///   - label: Human-readable name for this metric (e.g., "earnings", "expenses").
    ///     Used in the generated summary text.
    /// - Returns: A `TrendResult` if there are at least 14 data points after gap-filling,
    ///   otherwise `nil`.
    static func analyzeTrend(
        dailyValues: [(date: Date, value: Double)],
        label: String
    ) -> TrendResult? {
        // Step 0: Validate and sort input
        guard dailyValues.count >= 2 else { return nil }

        let sorted = dailyValues.sorted { $0.date < $1.date }

        // Step 1: Fill missing days to create a contiguous daily series
        let filled = fillMissingDays(data: sorted)
        guard filled.count >= minimumDataPoints else { return nil }

        let values = filled.map(\.value)
        let dates = filled.map(\.date)

        // Step 2: Calculate day-of-week seasonal factors
        let seasonalFactors = computeSeasonalFactors(dates: dates, values: values)

        // Step 3: Deseasonalize by dividing out the weekly pattern
        let deseasonalized = deseasonalizeValues(dates: dates, values: values, factors: seasonalFactors)

        // Step 4: OLS linear regression on deseasonalized data using vDSP
        let n = deseasonalized.count
        let xValues = (0..<n).map { Double($0) }
        let regression = linearRegression(x: xValues, y: deseasonalized)

        // Step 5: R-squared (coefficient of determination)
        let rSquared = computeRSquared(x: xValues, y: deseasonalized, slope: regression.slope, intercept: regression.intercept)

        // Step 6: Detect change points via binary segmentation
        let changeIndices = detectChangePoints(values: values, minSegmentLength: 7)
        let changePoints = changeIndices.compactMap { idx -> ChangePoint? in
            guard idx > 0, idx < values.count else { return nil }
            let before = Array(values[0..<idx])
            let after = Array(values[idx..<values.count])
            let beforeAvg = vDSP_meanD(before)
            let afterAvg = vDSP_meanD(after)
            guard beforeAvg > 0 else { return nil }
            let pctChange = (afterAvg - beforeAvg) / beforeAvg * 100.0
            let date = dates[idx]
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let direction = pctChange > 0 ? "jumped" : "dropped"
            let desc = "\(label.capitalized) \(direction) \(String(format: "%.0f%%", abs(pctChange))) around \(formatter.string(from: date))"
            return ChangePoint(date: date, beforeAvg: beforeAvg, afterAvg: afterAvg, percentChange: pctChange, description: desc)
        }

        // Step 7: Forecast by combining trend extrapolation + seasonal factors
        let lastX = Double(n - 1)
        let calendar = Calendar.current
        let lastDate = dates[n - 1]

        var forecast7: Double = 0
        var forecast30: Double = 0

        for dayOffset in 1...30 {
            let futureX = lastX + Double(dayOffset)
            let trendValue = regression.intercept + regression.slope * futureX
            let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: lastDate) ?? lastDate
            let weekday = calendar.component(.weekday, from: futureDate)
            let factor = seasonalFactors[weekday] ?? 1.0
            let predicted = max(0, trendValue * factor)
            forecast30 += predicted
            if dayOffset <= 7 {
                forecast7 += predicted
            }
        }

        // Step 8: Volatility — coefficient of variation of residuals
        let residuals = zip(xValues, deseasonalized).map { x, y in
            y - (regression.intercept + regression.slope * x)
        }
        let volatility = coefficientOfVariation(residuals)

        // Step 9: Map to TrendDirection
        let direction = classifyDirection(slope: regression.slope, rSquared: rSquared)

        // Step 10: Generate human-readable summary
        let summary = buildSummary(
            label: label,
            direction: direction,
            slope: regression.slope,
            rSquared: rSquared,
            seasonalFactors: seasonalFactors,
            changePoints: changePoints,
            volatility: volatility
        )

        return TrendResult(
            direction: direction,
            strength: rSquared,
            slope: regression.slope,
            weeklyChange: regression.slope * 7,
            monthlyChange: regression.slope * 30,
            seasonalFactors: seasonalFactors,
            changePoints: changePoints,
            forecast7Day: forecast7,
            forecast30Day: forecast30,
            volatility: volatility,
            summary: summary
        )
    }

    // MARK: - Seasonal Decomposition

    /// Classical additive decomposition: Y = Trend + Seasonal + Residual.
    ///
    /// **Algorithm:**
    /// 1. Compute centered moving average with window = `period` to extract trend.
    ///    Edge values are extrapolated from the nearest computed trend value.
    /// 2. Subtract trend from observed values to get detrended series.
    /// 3. Average detrended values by position within period to get seasonal component.
    ///    The seasonal component is normalized to sum to zero over one period.
    /// 4. Residual = observed - trend - seasonal.
    /// 5. Seasonal strength = 1 - var(residual) / var(detrended).
    ///    A value near 1 means seasonality dominates; near 0 means it's all noise.
    ///
    /// - Parameters:
    ///   - dailyValues: Contiguous daily observations (no gaps).
    ///   - period: Seasonal period in days. Default is 7 (weekly cycle), which is
    ///     the dominant cycle in gig work.
    /// - Returns: A `SeasonalDecomposition` with all three components and strength metric.
    static func decomposeSeasonal(dailyValues: [Double], period: Int = 7) -> SeasonalDecomposition {
        let n = dailyValues.count

        // Trend: centered moving average
        let rawTrend = centeredMovingAverage(values: dailyValues, window: period)

        // Extrapolate edges where CMA is NaN/undefined
        let trend = extrapolateTrendEdges(rawTrend)

        // Detrended: Y - T
        var detrended = [Double](repeating: 0, count: n)
        vDSP.subtract(trend, dailyValues, result: &detrended)
        // vDSP.subtract computes (a - b), but we need (b - a) = Y - T
        vDSP.multiply(-1.0, detrended, result: &detrended)

        // Seasonal component: average of detrended values at each position mod period
        var seasonalBuckets = [[Double]](repeating: [], count: period)
        for i in 0..<n {
            seasonalBuckets[i % period].append(detrended[i])
        }
        var seasonalPattern = seasonalBuckets.map { bucket -> Double in
            guard !bucket.isEmpty else { return 0 }
            return vDSP_meanD(bucket)
        }

        // Normalize seasonal component to sum to zero (additive constraint)
        let seasonalMean = vDSP_meanD(seasonalPattern)
        seasonalPattern = seasonalPattern.map { $0 - seasonalMean }

        // Expand seasonal pattern to full series length
        var seasonal = [Double](repeating: 0, count: n)
        for i in 0..<n {
            seasonal[i] = seasonalPattern[i % period]
        }

        // Residual: Y - T - S
        var residual = [Double](repeating: 0, count: n)
        for i in 0..<n {
            residual[i] = dailyValues[i] - trend[i] - seasonal[i]
        }

        // Seasonal strength: 1 - var(residual) / var(detrended)
        let varResidual = varianceD(residual)
        let varDetrended = varianceD(detrended)
        let seasonalStrength: Double
        if varDetrended > 1e-10 {
            seasonalStrength = max(0, min(1, 1.0 - varResidual / varDetrended))
        } else {
            seasonalStrength = 0
        }

        return SeasonalDecomposition(
            trend: trend,
            seasonal: seasonal,
            residual: residual,
            seasonalStrength: seasonalStrength
        )
    }

    // MARK: - Change-Point Detection

    /// Detects structural breaks in a time series using binary segmentation.
    ///
    /// **Algorithm (Binary Segmentation):**
    /// 1. Consider every possible split point in the series.
    /// 2. At each candidate, compute Welch's t-statistic comparing the left
    ///    and right segments. Welch's t-test does not assume equal variances,
    ///    which is important for financial data where volatility itself changes.
    /// 3. Select the split point with the highest absolute t-statistic.
    /// 4. If that t-statistic exceeds the significance threshold (p < 0.01),
    ///    record it as a change point.
    /// 5. Recurse on each resulting segment until no more significant splits remain.
    ///
    /// The `minSegmentLength` prevents detecting spurious changes from very short
    /// segments where the mean estimate is unreliable.
    ///
    /// - Parameters:
    ///   - values: The time series to analyze.
    ///   - minSegmentLength: Minimum observations on each side of a split. Default 7
    ///     (one full week) to avoid false positives from weekend/weekday differences.
    /// - Returns: Sorted array of indices where significant level shifts occur.
    static func detectChangePoints(values: [Double], minSegmentLength: Int = 7) -> [Int] {
        var points: [Int] = []
        binarySegmentation(values: values, start: 0, end: values.count, minSegment: minSegmentLength, results: &points)
        return points.sorted()
    }

    // MARK: - Momentum

    /// Calculates trend momentum from the ratio of short-term to long-term EMAs.
    ///
    /// Momentum = (shortEMA - longEMA) / longEMA, expressed as a fraction.
    ///
    /// **Interpretation:**
    /// - Positive momentum: recent values are accelerating above the long-term average.
    /// - Negative momentum: recent values are decelerating below trend.
    /// - Zero (near-zero): short-term and long-term trends are aligned.
    ///
    /// This is analogous to MACD in technical analysis, applied to daily earnings
    /// instead of stock prices.
    ///
    /// - Parameters:
    ///   - values: Daily time series, ordered chronologically.
    ///   - shortWindow: Lookback for the short-term EMA. Default 7 days.
    ///   - longWindow: Lookback for the long-term EMA. Default 30 days.
    /// - Returns: Momentum as a fraction. +0.15 means short-term is 15% above long-term.
    static func calculateMomentum(values: [Double], shortWindow: Int = 7, longWindow: Int = 30) -> Double {
        guard values.count >= longWindow else { return 0 }

        let shortAlpha = 2.0 / Double(shortWindow + 1)
        let longAlpha = 2.0 / Double(longWindow + 1)

        let shortEMA = exponentialMovingAverage(values: values, alpha: shortAlpha)
        let longEMA = exponentialMovingAverage(values: values, alpha: longAlpha)

        guard let shortLast = shortEMA.last, let longLast = longEMA.last, abs(longLast) > 1e-10 else {
            return 0
        }

        return (shortLast - longLast) / longLast
    }

    // MARK: - Multi-Metric Analysis

    /// Analyzes earnings, expenses, and fees together to produce cross-metric insights.
    ///
    /// Computes individual trend analyses for each metric, derives a profit trend
    /// (earnings - expenses), and calculates pairwise Pearson correlations.
    /// The narrative summary synthesizes the individual trends into actionable advice.
    ///
    /// Example narrative: "Your earnings are rising while expenses are flat — profit
    /// margin is improving. Fee rates show no correlation with volume, suggesting
    /// platform fees are fixed-rate."
    ///
    /// - Parameters:
    ///   - dailyEarnings: Daily (date, gross earnings) pairs.
    ///   - dailyExpenses: Daily (date, expense total) pairs.
    ///   - dailyFees: Daily (date, platform fee total) pairs.
    /// - Returns: A `MultiMetricTrend` with individual analyses, correlations, and narrative.
    static func analyzeMultiMetric(
        dailyEarnings: [(date: Date, value: Double)],
        dailyExpenses: [(date: Date, value: Double)],
        dailyFees: [(date: Date, value: Double)]
    ) -> MultiMetricTrend {
        // Individual trend analyses
        let earningsTrend = analyzeTrend(dailyValues: dailyEarnings, label: "earnings")
        let expenseTrend = analyzeTrend(dailyValues: dailyExpenses, label: "expenses")
        let feeRateTrend = analyzeTrend(dailyValues: dailyFees, label: "fee rate")

        // Derive daily profit series by aligning earnings and expenses on dates
        let profitSeries = computeDailyProfit(earnings: dailyEarnings, expenses: dailyExpenses)
        let profitTrend = analyzeTrend(dailyValues: profitSeries, label: "profit")

        // Pairwise correlations on aligned series
        var correlations: [(metric1: String, metric2: String, correlation: Double)] = []

        let filledEarnings = fillMissingDays(data: dailyEarnings.sorted { $0.date < $1.date })
        let filledExpenses = fillMissingDays(data: dailyExpenses.sorted { $0.date < $1.date })
        let filledFees = fillMissingDays(data: dailyFees.sorted { $0.date < $1.date })

        // Align series by finding overlapping date range
        let alignedPairs = alignSeries(
            series: [
                ("Earnings", filledEarnings),
                ("Expenses", filledExpenses),
                ("Fees", filledFees)
            ]
        )

        // Compute correlations for each pair
        let metricNames = alignedPairs.map(\.name)
        let metricValues = alignedPairs.map(\.values)

        for i in 0..<metricNames.count {
            for j in (i + 1)..<metricNames.count {
                let r = pearsonCorrelation(x: metricValues[i], y: metricValues[j])
                if !r.isNaN {
                    correlations.append((metric1: metricNames[i], metric2: metricNames[j], correlation: r))
                }
            }
        }

        // Generate narrative summary
        let narrative = buildMultiMetricNarrative(
            earningsTrend: earningsTrend,
            expenseTrend: expenseTrend,
            profitTrend: profitTrend,
            feeRateTrend: feeRateTrend,
            correlations: correlations
        )

        return MultiMetricTrend(
            earningsTrend: earningsTrend,
            expenseTrend: expenseTrend,
            profitTrend: profitTrend,
            feeRateTrend: feeRateTrend,
            correlations: correlations,
            narrativeSummary: narrative
        )
    }

    // MARK: - Correlation

    /// Computes the Pearson product-moment correlation coefficient between two series.
    ///
    /// **Formula:** r = Σ((xi - x̄)(yi - ȳ)) / √(Σ(xi - x̄)² · Σ(yi - ȳ)²)
    ///
    /// Uses Accelerate vDSP for vectorized dot products and normalization.
    ///
    /// **Interpretation:**
    /// - r = +1: Perfect positive linear relationship
    /// - r = 0: No linear relationship
    /// - r = -1: Perfect negative linear relationship
    /// - |r| > 0.7: Strong correlation
    /// - |r| > 0.4: Moderate correlation
    /// - |r| < 0.2: Weak/no correlation
    ///
    /// - Parameters:
    ///   - x: First variable's observations.
    ///   - y: Second variable's observations. Must be same length as `x`.
    /// - Returns: Pearson r in [-1, 1], or NaN if inputs are invalid or constant.
    static func pearsonCorrelation(x: [Double], y: [Double]) -> Double {
        let n = min(x.count, y.count)
        guard n >= 3 else { return .nan }

        let xSlice = Array(x.prefix(n))
        let ySlice = Array(y.prefix(n))

        // Mean-center both vectors
        let xMean = vDSP_meanD(xSlice)
        let yMean = vDSP_meanD(ySlice)

        var xCentered = [Double](repeating: 0, count: n)
        var yCentered = [Double](repeating: 0, count: n)

        var negXMean = -xMean
        var negYMean = -yMean
        vDSP_vsaddD(xSlice, 1, &negXMean, &xCentered, 1, vDSP_Length(n))
        vDSP_vsaddD(ySlice, 1, &negYMean, &yCentered, 1, vDSP_Length(n))

        // Dot products using vDSP
        var xyDot: Double = 0
        var xxDot: Double = 0
        var yyDot: Double = 0

        vDSP_dotprD(xCentered, 1, yCentered, 1, &xyDot, vDSP_Length(n))
        vDSP_dotprD(xCentered, 1, xCentered, 1, &xxDot, vDSP_Length(n))
        vDSP_dotprD(yCentered, 1, yCentered, 1, &yyDot, vDSP_Length(n))

        let denominator = sqrt(xxDot * yyDot)
        guard denominator > 1e-10 else { return .nan }

        return xyDot / denominator
    }

    // MARK: - Helpers (Gap Filling)

    /// Fills gaps in a date-value series by inserting zero-value entries for missing days.
    ///
    /// Gig workers don't earn every day. A series might go Mon=50, Wed=80 with Tuesday
    /// missing. This function inserts Tue=0 to create a contiguous daily series, which
    /// is required for moving averages and seasonal decomposition.
    ///
    /// - Parameter data: Sorted array of (date, value) pairs with potential date gaps.
    /// - Returns: Contiguous daily series from first date to last date, gaps filled with 0.
    static func fillMissingDays(data: [(date: Date, value: Double)]) -> [(date: Date, value: Double)] {
        guard let first = data.first, let last = data.last else { return [] }

        let calendar = Calendar.current

        // Normalize all dates to start of day for consistent comparison
        let startDay = calendar.startOfDay(for: first.date)
        let endDay = calendar.startOfDay(for: last.date)

        // Build a lookup of existing values by day
        var valueLookup: [Date: Double] = [:]
        for entry in data {
            let day = calendar.startOfDay(for: entry.date)
            valueLookup[day, default: 0] += entry.value
        }

        // Walk from start to end, filling gaps with zero
        var result: [(date: Date, value: Double)] = []
        var current = startDay
        while current <= endDay {
            let value = valueLookup[current] ?? 0
            result.append((date: current, value: value))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return result
    }

    // MARK: - Helpers (Moving Averages)

    /// Centered moving average for trend extraction.
    ///
    /// For each point, averages the surrounding `window` values, centered on the point.
    /// For even window sizes (like 7), uses a 2-step CMA: first a window-wide average,
    /// then a 2-wide average of those results, to maintain symmetry.
    ///
    /// Edge values (within half-window of the boundaries) are set to NaN and should be
    /// handled by the caller (typically extrapolated).
    ///
    /// - Parameters:
    ///   - values: Input time series.
    ///   - window: Window size. Should be odd for perfect centering; if even, a 2x
    ///     centered average is applied.
    /// - Returns: Array of same length with smoothed values. Edge values are NaN.
    static func centeredMovingAverage(values: [Double], window: Int) -> [Double] {
        let n = values.count
        guard n >= window, window >= 2 else { return values }

        let halfWindow = window / 2
        var result = [Double](repeating: .nan, count: n)

        // Simple moving average centered at each point
        for i in halfWindow..<(n - halfWindow) {
            let startIdx = i - halfWindow
            let endIdx = i + halfWindow
            let slice = Array(values[startIdx...endIdx])
            result[i] = vDSP_meanD(slice)
        }

        return result
    }

    /// Exponential moving average (EMA) giving more weight to recent observations.
    ///
    /// **Formula:** EMA_t = α · x_t + (1 - α) · EMA_{t-1}
    ///
    /// The smoothing factor α controls responsiveness:
    /// - α close to 1: Tracks recent values closely (more reactive, less smooth).
    /// - α close to 0: Heavy smoothing, slow to react to changes.
    /// - Common convention: α = 2 / (window + 1), so a 7-day EMA uses α ≈ 0.25.
    ///
    /// Initialized with the first value (no look-ahead).
    ///
    /// - Parameters:
    ///   - values: Input time series, ordered chronologically.
    ///   - alpha: Smoothing factor in (0, 1]. Higher = more weight on recent values.
    /// - Returns: Array of same length with EMA values.
    static func exponentialMovingAverage(values: [Double], alpha: Double) -> [Double] {
        guard !values.isEmpty else { return [] }

        var ema = [Double](repeating: 0, count: values.count)
        ema[0] = values[0]

        let decay = 1.0 - alpha
        for i in 1..<values.count {
            ema[i] = alpha * values[i] + decay * ema[i - 1]
        }

        return ema
    }

    // MARK: - Private — Regression

    /// Ordinary Least Squares (OLS) linear regression: y = intercept + slope * x.
    ///
    /// Uses the closed-form solution:
    ///   slope = (n·Σxy - Σx·Σy) / (n·Σx² - (Σx)²)
    ///   intercept = ȳ - slope · x̄
    ///
    /// Computed using vDSP dot products for numerical stability on large series.
    ///
    /// - Parameters:
    ///   - x: Independent variable (typically day index: 0, 1, 2, ...).
    ///   - y: Dependent variable (daily earnings, expenses, etc.).
    /// - Returns: Tuple of (slope, intercept).
    private static func linearRegression(x: [Double], y: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(min(x.count, y.count))
        guard n >= 2 else { return (slope: 0, intercept: y.first ?? 0) }

        let count = Int(n)
        let xSlice = Array(x.prefix(count))
        let ySlice = Array(y.prefix(count))

        // Σx, Σy
        let sumX = vDSP_sumD(xSlice)
        let sumY = vDSP_sumD(ySlice)

        // Σxy via dot product
        var sumXY: Double = 0
        vDSP_dotprD(xSlice, 1, ySlice, 1, &sumXY, vDSP_Length(count))

        // Σx² via dot product
        var sumX2: Double = 0
        vDSP_dotprD(xSlice, 1, xSlice, 1, &sumX2, vDSP_Length(count))

        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-10 else {
            return (slope: 0, intercept: sumY / n)
        }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        return (slope: slope, intercept: intercept)
    }

    /// Coefficient of determination (R²) measuring how well the linear model fits.
    ///
    /// R² = 1 - SS_res / SS_tot
    ///
    /// - SS_res: Sum of squared residuals (actual - predicted)²
    /// - SS_tot: Total sum of squares (actual - mean)²
    ///
    /// R² = 1 means a perfect fit. R² = 0 means the model is no better than the mean.
    /// Negative R² is possible if the model is worse than the mean (shouldn't happen
    /// with OLS, but can with numerical edge cases). Clamped to [0, 1].
    private static func computeRSquared(x: [Double], y: [Double], slope: Double, intercept: Double) -> Double {
        let n = min(x.count, y.count)
        guard n >= 3 else { return 0 }

        let ySlice = Array(y.prefix(n))
        let yMean = vDSP_meanD(ySlice)

        var ssRes: Double = 0
        var ssTot: Double = 0

        for i in 0..<n {
            let predicted = intercept + slope * x[i]
            let residual = ySlice[i] - predicted
            let deviation = ySlice[i] - yMean
            ssRes += residual * residual
            ssTot += deviation * deviation
        }

        guard ssTot > 1e-10 else { return 0 }

        return max(0, min(1, 1.0 - ssRes / ssTot))
    }

    // MARK: - Private — Seasonal Analysis

    /// Computes day-of-week multipliers from raw daily data.
    ///
    /// For each day of the week (Sunday=1 through Saturday=7), calculates the average
    /// daily value, then normalizes by the overall daily average. A factor of 1.3 for
    /// Saturday means Saturdays are 30% above the overall daily average.
    ///
    /// - Parameters:
    ///   - dates: Array of dates corresponding to each observation.
    ///   - values: Daily values aligned with dates.
    /// - Returns: Dictionary mapping weekday number (1-7) to multiplier.
    private static func computeSeasonalFactors(dates: [Date], values: [Double]) -> [Int: Double] {
        let calendar = Calendar.current
        var buckets: [Int: [Double]] = [:]

        for i in 0..<min(dates.count, values.count) {
            let weekday = calendar.component(.weekday, from: dates[i])
            buckets[weekday, default: []].append(values[i])
        }

        let overallMean = vDSP_meanD(values)
        guard overallMean > 1e-10 else {
            // All zeros — return uniform factors
            var factors: [Int: Double] = [:]
            for day in 1...7 { factors[day] = 1.0 }
            return factors
        }

        var factors: [Int: Double] = [:]
        for day in 1...7 {
            if let bucket = buckets[day], !bucket.isEmpty {
                factors[day] = vDSP_meanD(bucket) / overallMean
            } else {
                factors[day] = 1.0
            }
        }

        return factors
    }

    /// Removes seasonal (weekly) pattern from values by dividing by day-of-week factors.
    ///
    /// Deseasonalization reveals the underlying trend without weekly oscillation.
    /// We divide rather than subtract because gig earnings are multiplicative —
    /// a "good day" effect scales with the overall level.
    private static func deseasonalizeValues(dates: [Date], values: [Double], factors: [Int: Double]) -> [Double] {
        let calendar = Calendar.current
        return zip(dates, values).map { date, value in
            let weekday = calendar.component(.weekday, from: date)
            let factor = factors[weekday] ?? 1.0
            return factor > 1e-10 ? value / factor : value
        }
    }

    // MARK: - Private — Change-Point Detection

    /// Recursive binary segmentation for change-point detection.
    ///
    /// At each recursion level, scans every candidate split point within the segment
    /// [start, end), evaluates a Welch t-test comparing the two halves, and if the
    /// best split is significant, records it and recurses on each half.
    private static func binarySegmentation(
        values: [Double],
        start: Int,
        end: Int,
        minSegment: Int,
        results: inout [Int]
    ) {
        let segmentLength = end - start
        guard segmentLength >= 2 * minSegment else { return }

        var bestT: Double = 0
        var bestSplit = -1

        // Scan all valid split points
        for split in (start + minSegment)..<(end - minSegment) {
            let left = Array(values[start..<split])
            let right = Array(values[split..<end])
            let t = welchTStatistic(left, right)
            if abs(t) > abs(bestT) {
                bestT = t
                bestSplit = split
            }
        }

        // Check significance using approximate t-distribution critical value
        // For large samples, t > 2.576 ≈ p < 0.01 (two-tailed)
        guard bestSplit >= 0, abs(bestT) > 2.576 else { return }

        results.append(bestSplit)

        // Recurse on each half
        binarySegmentation(values: values, start: start, end: bestSplit, minSegment: minSegment, results: &results)
        binarySegmentation(values: values, start: bestSplit, end: end, minSegment: minSegment, results: &results)
    }

    /// Welch's t-statistic for comparing two samples with potentially unequal variances.
    ///
    /// **Formula:** t = (x̄₁ - x̄₂) / √(s₁²/n₁ + s₂²/n₂)
    ///
    /// Welch's t-test does not assume equal variances (unlike Student's t-test),
    /// which is critical for financial data where volatility changes over time.
    private static func welchTStatistic(_ a: [Double], _ b: [Double]) -> Double {
        let n1 = Double(a.count)
        let n2 = Double(b.count)
        guard n1 >= 2, n2 >= 2 else { return 0 }

        let mean1 = vDSP_meanD(a)
        let mean2 = vDSP_meanD(b)

        let var1 = varianceD(a)
        let var2 = varianceD(b)

        let denominator = sqrt(var1 / n1 + var2 / n2)
        guard denominator > 1e-10 else { return 0 }

        return (mean1 - mean2) / denominator
    }

    // MARK: - Private — Classification & Summary

    /// Maps regression slope and R-squared to a human-readable trend direction.
    ///
    /// Thresholds are calibrated for gig worker daily earnings ($50-$300/day typical):
    /// - Strong trend: |slope| > $5/day AND R² > 0.3
    /// - Moderate trend: |slope| > $2/day AND R² > 0.15
    /// - Flat: weak slope or low R² (trend exists but isn't meaningful)
    private static func classifyDirection(slope: Double, rSquared: Double) -> TrendDirection {
        let absSlope = abs(slope)

        if absSlope > 5.0 && rSquared > 0.3 {
            return slope > 0 ? .strongUp : .strongDown
        } else if absSlope > 2.0 && rSquared > 0.15 {
            return slope > 0 ? .moderateUp : .moderateDown
        } else {
            return .flat
        }
    }

    /// Builds a human-readable summary combining all trend signals.
    private static func buildSummary(
        label: String,
        direction: TrendDirection,
        slope: Double,
        rSquared: Double,
        seasonalFactors: [Int: Double],
        changePoints: [ChangePoint],
        volatility: Double
    ) -> String {
        var parts: [String] = []

        // Direction and rate
        let weeklyChange = slope * 7
        switch direction {
        case .strongUp:
            parts.append("\(direction.rawValue) — \(label) growing ~\(formatCurrency(abs(slope)))/day (\(formatCurrency(abs(weeklyChange)))/week)")
        case .moderateUp:
            parts.append("\(direction.rawValue) — \(label) gradually increasing ~\(formatCurrency(abs(slope)))/day")
        case .flat:
            parts.append("\(label.capitalized) are relatively stable with no significant trend")
        case .moderateDown:
            parts.append("\(direction.rawValue) — \(label) gradually decreasing ~\(formatCurrency(abs(slope)))/day")
        case .strongDown:
            parts.append("\(direction.rawValue) — \(label) declining ~\(formatCurrency(abs(slope)))/day (\(formatCurrency(abs(weeklyChange)))/week)")
        }

        // Strongest days
        let dayNames = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        let sortedDays = seasonalFactors.sorted { $0.value > $1.value }
        let strongDays = sortedDays.prefix(2).compactMap { entry -> String? in
            guard entry.value > 1.1 else { return nil }
            return dayNames[entry.key]
        }
        if !strongDays.isEmpty {
            parts.append("Strongest days: \(strongDays.joined(separator: ", "))")
        }

        // Change points
        if changePoints.count == 1 {
            parts.append("One significant shift detected: \(changePoints[0].description)")
        } else if changePoints.count > 1 {
            parts.append("\(changePoints.count) significant shifts detected")
        }

        // Volatility
        if volatility > 1.0 {
            parts.append("High day-to-day volatility — earnings are unpredictable")
        } else if volatility > 0.5 {
            parts.append("Moderate volatility in daily amounts")
        }

        // Trend strength
        if rSquared < 0.1 && direction == .flat {
            parts.append("No clear directional pattern in the data (R²=\(String(format: "%.2f", rSquared)))")
        }

        return parts.joined(separator: ". ") + "."
    }

    /// Generates a narrative summary for multi-metric trend analysis.
    private static func buildMultiMetricNarrative(
        earningsTrend: TrendResult?,
        expenseTrend: TrendResult?,
        profitTrend: TrendResult?,
        feeRateTrend: TrendResult?,
        correlations: [(metric1: String, metric2: String, correlation: Double)]
    ) -> String {
        var sentences: [String] = []

        // Earnings direction
        if let earnings = earningsTrend {
            switch earnings.direction {
            case .strongUp, .moderateUp:
                sentences.append("Your earnings are trending upward (\(formatCurrency(abs(earnings.weeklyChange)))/week)")
            case .strongDown, .moderateDown:
                sentences.append("Your earnings have been declining (\(formatCurrency(abs(earnings.weeklyChange)))/week)")
            case .flat:
                sentences.append("Your earnings have been relatively stable")
            }
        }

        // Expense direction relative to earnings
        if let expenses = expenseTrend, let earnings = earningsTrend {
            let earningsUp = earnings.direction == .strongUp || earnings.direction == .moderateUp
            let expensesFlat = expenses.direction == .flat
            let expensesUp = expenses.direction == .strongUp || expenses.direction == .moderateUp

            if earningsUp && expensesFlat {
                sentences.append("while expenses are flat — profit margin is improving")
            } else if earningsUp && expensesUp {
                if abs(expenses.slope) > abs(earnings.slope) {
                    sentences.append("but expenses are growing faster — watch your profit margin")
                } else {
                    sentences.append("and expenses are rising too, but slower — margins are still improving")
                }
            } else if !earningsUp && expensesUp {
                sentences.append("while expenses are rising — profit is being squeezed")
            }
        } else if let expenses = expenseTrend {
            switch expenses.direction {
            case .strongUp, .moderateUp:
                sentences.append("Expenses are trending up (\(formatCurrency(abs(expenses.weeklyChange)))/week)")
            case .strongDown, .moderateDown:
                sentences.append("Expenses are declining — good for your bottom line")
            case .flat:
                sentences.append("Expenses are holding steady")
            }
        }

        // Profit summary
        if let profit = profitTrend {
            switch profit.direction {
            case .strongUp:
                sentences.append("Net profit is on a strong upward trajectory")
            case .moderateUp:
                sentences.append("Net profit is gradually improving")
            case .strongDown:
                sentences.append("Net profit is dropping significantly — action needed")
            case .moderateDown:
                sentences.append("Net profit is slowly declining")
            case .flat:
                break // Already covered by earnings/expense relationship
            }
        }

        // Fee rate
        if let fees = feeRateTrend {
            switch fees.direction {
            case .strongUp, .moderateUp:
                sentences.append("Platform fees appear to be increasing")
            case .strongDown, .moderateDown:
                sentences.append("Platform fees are trending down")
            case .flat:
                break // Not worth mentioning if flat
            }
        }

        // Notable correlations
        for corr in correlations {
            if abs(corr.correlation) > 0.7 {
                let relationship = corr.correlation > 0 ? "move together" : "move in opposite directions"
                sentences.append("\(corr.metric1) and \(corr.metric2) \(relationship) (r=\(String(format: "%.2f", corr.correlation)))")
            }
        }

        if sentences.isEmpty {
            return "Insufficient data to identify meaningful trends across metrics."
        }

        return sentences.joined(separator: ". ") + "."
    }

    // MARK: - Private — Utility Functions

    /// Extrapolates NaN values at the edges of a trend array with the nearest valid value.
    ///
    /// The centered moving average produces NaN at both ends (within half-window).
    /// We fill these by extending the first/last valid value outward, which is a
    /// conservative assumption (edges match the nearest known trend level).
    private static func extrapolateTrendEdges(_ trend: [Double]) -> [Double] {
        var result = trend

        // Find first non-NaN value and backfill
        if let firstValid = result.firstIndex(where: { !$0.isNaN }) {
            for i in 0..<firstValid {
                result[i] = result[firstValid]
            }
        }

        // Find last non-NaN value and forward-fill
        if let lastValid = result.lastIndex(where: { !$0.isNaN }) {
            for i in (lastValid + 1)..<result.count {
                result[i] = result[lastValid]
            }
        }

        // If everything is NaN (shouldn't happen), fill with zeros
        if result.allSatisfy({ $0.isNaN }) {
            return [Double](repeating: 0, count: result.count)
        }

        return result
    }

    /// Computes daily profit by aligning earnings and expenses on matching dates.
    ///
    /// For each date that appears in either series, profit = earnings - expenses.
    /// Missing earnings or expenses for a date are treated as zero.
    private static func computeDailyProfit(
        earnings: [(date: Date, value: Double)],
        expenses: [(date: Date, value: Double)]
    ) -> [(date: Date, value: Double)] {
        let calendar = Calendar.current

        var earningsMap: [Date: Double] = [:]
        for e in earnings {
            let day = calendar.startOfDay(for: e.date)
            earningsMap[day, default: 0] += e.value
        }

        var expensesMap: [Date: Double] = [:]
        for e in expenses {
            let day = calendar.startOfDay(for: e.date)
            expensesMap[day, default: 0] += e.value
        }

        let allDates = Set(earningsMap.keys).union(expensesMap.keys).sorted()
        return allDates.map { date in
            let earn = earningsMap[date] ?? 0
            let exp = expensesMap[date] ?? 0
            return (date: date, value: earn - exp)
        }
    }

    /// Aligns multiple named series to a common date range for correlation analysis.
    ///
    /// Only includes dates that exist in ALL series to ensure alignment.
    private static func alignSeries(
        series: [(name: String, data: [(date: Date, value: Double)])]
    ) -> [(name: String, values: [Double])] {
        let calendar = Calendar.current

        // Build date-keyed lookups for each series
        let lookups: [[(name: String, lookup: [Date: Double])]] = series.map { s in
            var lookup: [Date: Double] = [:]
            for entry in s.data {
                let day = calendar.startOfDay(for: entry.date)
                lookup[day, default: 0] += entry.value
            }
            return [(name: s.name, lookup: lookup)]
        }

        let flatLookups = lookups.flatMap { $0 }

        // Find dates common to all series
        guard let firstLookup = flatLookups.first else { return [] }
        var commonDates = Set(firstLookup.lookup.keys)
        for l in flatLookups.dropFirst() {
            commonDates = commonDates.intersection(l.lookup.keys)
        }

        let sortedDates = commonDates.sorted()
        guard !sortedDates.isEmpty else { return [] }

        return flatLookups.map { entry in
            let values = sortedDates.map { entry.lookup[$0] ?? 0 }
            return (name: entry.name, values: values)
        }
    }

    /// Sample variance using the population formula: Σ(xi - x̄)² / n.
    ///
    /// Using population variance (not sample variance with n-1) because we're
    /// computing variance of the full observed series, not estimating a population
    /// parameter.
    private static func varianceD(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }

        let mean = vDSP_meanD(values)
        var sumSq: Double = 0
        for v in values {
            let diff = v - mean
            sumSq += diff * diff
        }
        return sumSq / Double(n)
    }

    /// Coefficient of variation: standard deviation / |mean|.
    ///
    /// A dimensionless measure of dispersion relative to the central tendency.
    /// Useful for comparing volatility across metrics with different scales.
    /// Returns 0 if the mean is near zero to avoid division by zero.
    private static func coefficientOfVariation(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }

        let mean = vDSP_meanD(values)
        guard abs(mean) > 1e-10 else { return 0 }

        let variance = varianceD(values)
        return sqrt(variance) / abs(mean)
    }

    /// Convenience wrapper for vDSP mean on a Double array.
    private static func vDSP_meanD(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        var result: Double = 0
        vDSP_meanvD(values, 1, &result, vDSP_Length(values.count))
        return result
    }

    /// Convenience wrapper for vDSP sum on a Double array.
    private static func vDSP_sumD(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        var result: Double = 0
        vDSP_sveD(values, 1, &result, vDSP_Length(values.count))
        return result
    }

    /// Formats a dollar amount for display in summaries.
    private static func formatCurrency(_ amount: Double) -> String {
        return String(format: "$%.2f", amount)
    }
}
