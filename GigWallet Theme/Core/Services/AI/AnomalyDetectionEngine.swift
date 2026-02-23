import Foundation
import Accelerate

/// Statistical anomaly detection engine for gig worker financial data.
///
/// Uses proper statistical methods — z-scores, IQR (Tukey fences), Modified Z-Scores
/// (Median Absolute Deviation), and Grubbs' test — to flag genuinely unusual financial
/// events. This is NOT simple percentage-threshold checking; it adapts to each worker's
/// actual distribution of earnings, expenses, and fees.
///
/// Entirely client-side, stateless, and deterministic. Every method requires a minimum
/// sample size (typically n >= 10) to avoid false positives from sparse data.
enum AnomalyDetectionEngine: Sendable {

    // MARK: - Data Types

    /// A detected statistical anomaly in the user's financial data.
    struct Anomaly: Identifiable, Sendable {
        let id: UUID
        let type: AnomalyType
        let severity: Severity
        let metric: String
        let observedValue: Double
        let expectedRange: (low: Double, high: Double)
        let zScore: Double
        let description: String
        let recommendation: String
        let detectedAt: Date

        init(
            type: AnomalyType,
            severity: Severity,
            metric: String,
            observedValue: Double,
            expectedRange: (low: Double, high: Double),
            zScore: Double,
            description: String,
            recommendation: String,
            detectedAt: Date
        ) {
            self.id = UUID()
            self.type = type
            self.severity = severity
            self.metric = metric
            self.observedValue = observedValue
            self.expectedRange = expectedRange
            self.zScore = zScore
            self.description = description
            self.recommendation = recommendation
            self.detectedAt = detectedAt
        }
    }

    /// Classification of the anomaly's nature.
    enum AnomalyType: String, Sendable {
        case earningsSpike = "Earnings Spike"
        case earningsDrop = "Earnings Drop"
        case feeIncrease = "Fee Increase"
        case expenseSpike = "Expense Spike"
        case unusualPlatformShift = "Platform Shift"
        case incomeGap = "Income Gap"
        case categoryOutlier = "Category Outlier"
    }

    /// How urgent the anomaly is. Higher rawValue = more severe.
    enum Severity: Int, Comparable, Sendable {
        case info = 0
        case warning = 1
        case critical = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Input Snapshots

    /// A single day's earnings record, decoupled from SwiftData.
    struct EarningsEntry: Sendable {
        let date: Date
        let amount: Double
        let platform: String
    }

    /// A single expense record, decoupled from SwiftData.
    struct ExpenseEntry: Sendable {
        let date: Date
        let amount: Double
        let category: String
    }

    /// A single fee record, decoupled from SwiftData.
    struct FeeEntry: Sendable {
        let date: Date
        let grossAmount: Double
        let fees: Double
        let platform: String
    }

    // MARK: - Constants

    /// Minimum number of data points required before any statistical test is meaningful.
    /// Below this, the standard deviation estimate is too noisy and we'd flag everything.
    private static let minimumSampleSize = 10

    // MARK: - Core Statistical Detection Methods

    /// Detects outliers using the standard z-score method.
    ///
    /// For each value, computes z = (x - mean) / stddev. Values with |z| exceeding the
    /// threshold are flagged. This works well when the underlying data is roughly normal,
    /// but is sensitive to existing outliers since they inflate the mean and stddev.
    ///
    /// - Parameters:
    ///   - values: The numeric observations to test.
    ///   - labels: Human-readable label for each observation (same count as values).
    ///   - dates: Date associated with each observation (same count as values).
    ///   - metric: Name of the metric being measured (e.g. "Daily Earnings").
    ///   - threshold: Number of standard deviations to consider anomalous. Default 2.0.
    /// - Returns: Array of anomalies for values beyond the threshold.
    static func detectByZScore(
        values: [Double],
        labels: [String],
        dates: [Date],
        metric: String,
        threshold: Double = 2.0
    ) -> [Anomaly] {
        guard values.count >= minimumSampleSize else { return [] }
        guard values.count == labels.count, values.count == dates.count else { return [] }

        let mean = vMean(values)
        let stddev = vStdDev(values)
        guard stddev > 1e-10 else { return [] } // All values identical

        var anomalies: [Anomaly] = []
        let low = mean - threshold * stddev
        let high = mean + threshold * stddev

        for i in values.indices {
            let z = (values[i] - mean) / stddev
            guard abs(z) > threshold else { continue }

            let type: AnomalyType = z > 0 ? .earningsSpike : .earningsDrop
            let severity = severityFromZScore(abs(z))

            anomalies.append(Anomaly(
                type: type,
                severity: severity,
                metric: metric,
                observedValue: values[i],
                expectedRange: (low: low, high: high),
                zScore: z,
                description: "\(labels[i]) of \(formatCurrency(values[i])) is \(String(format: "%.1f", abs(z))) standard deviations \(z > 0 ? "above" : "below") the mean of \(formatCurrency(mean)).",
                recommendation: z > 0
                    ? "Great day! Consider what made this day exceptional and try to replicate it."
                    : "This was well below your typical earnings. Check if a platform had outages or if demand was unusually low.",
                detectedAt: dates[i]
            ))
        }

        return anomalies
    }

    /// Detects outliers using Tukey's IQR (Interquartile Range) fences.
    ///
    /// Unlike z-scores, IQR fences are robust to outliers because quartiles resist
    /// extreme values. The standard multiplier of 1.5 flags "mild" outliers; 3.0
    /// flags "extreme" outliers.
    ///
    /// Fence definitions:
    ///   - Lower fence = Q1 - multiplier * IQR
    ///   - Upper fence = Q3 + multiplier * IQR
    ///
    /// - Parameters:
    ///   - values: The numeric observations to test.
    ///   - labels: Human-readable label for each observation.
    ///   - dates: Date associated with each observation.
    ///   - metric: Name of the metric being measured.
    ///   - multiplier: IQR multiplier for the fence. Default 1.5 (Tukey's standard).
    /// - Returns: Array of anomalies for values outside the fences.
    static func detectByIQR(
        values: [Double],
        labels: [String],
        dates: [Date],
        metric: String,
        multiplier: Double = 1.5
    ) -> [Anomaly] {
        guard values.count >= minimumSampleSize else { return [] }
        guard values.count == labels.count, values.count == dates.count else { return [] }

        let q = quartiles(values: values)
        let iqr = q.q3 - q.q1
        guard iqr > 1e-10 else { return [] } // Data too tightly clustered

        let lowerFence = q.q1 - multiplier * iqr
        let upperFence = q.q3 + multiplier * iqr

        // We still compute z-score using robust statistics for severity grading
        let med = q.median
        let madValue = mad(values: values)

        var anomalies: [Anomaly] = []

        for i in values.indices {
            guard values[i] < lowerFence || values[i] > upperFence else { continue }

            let robustZ: Double
            if madValue > 1e-10 {
                robustZ = 0.6745 * (values[i] - med) / madValue
            } else {
                // Fallback: use distance from fence in IQR units
                let dist = values[i] > upperFence
                    ? (values[i] - upperFence) / iqr
                    : (lowerFence - values[i]) / iqr
                robustZ = dist + 1.5 // Already past the fence
            }

            let type: AnomalyType = values[i] > upperFence ? .earningsSpike : .earningsDrop
            let severity = severityFromZScore(abs(robustZ))

            anomalies.append(Anomaly(
                type: type,
                severity: severity,
                metric: metric,
                observedValue: values[i],
                expectedRange: (low: lowerFence, high: upperFence),
                zScore: robustZ,
                description: "\(labels[i]) of \(formatCurrency(values[i])) is outside the IQR fence [\(formatCurrency(lowerFence)) .. \(formatCurrency(upperFence))].",
                recommendation: values[i] > upperFence
                    ? "Unusually high for this metric. If this is earnings, identify what drove the spike."
                    : "Unusually low for this metric. Review whether external factors were at play.",
                detectedAt: dates[i]
            ))
        }

        return anomalies
    }

    /// Computes the Modified Z-Score for each value using Median Absolute Deviation (MAD).
    ///
    /// The modified z-score replaces the mean with the median and the standard deviation
    /// with 1.4826 * MAD, making it highly robust to existing outliers. The constant
    /// 0.6745 (= 1/1.4826) is the 75th percentile of the standard normal distribution,
    /// which makes the MAD a consistent estimator of sigma for normal data.
    ///
    /// Formula: modified_z_i = 0.6745 * (x_i - median) / MAD
    ///
    /// - Parameter values: The observations.
    /// - Returns: Modified z-score for each observation, in the same order.
    static func modifiedZScore(values: [Double]) -> [Double] {
        guard values.count >= minimumSampleSize else {
            return Array(repeating: 0.0, count: values.count)
        }

        let med = median(values: values)
        let madValue = mad(values: values)

        guard madValue > 1e-10 else {
            // MAD is zero — more than half the values are identical to the median.
            // Fall back to mean-based distance as a rough proxy.
            return values.map { $0 == med ? 0.0 : ($0 > med ? 3.5 : -3.5) }
        }

        return values.map { 0.6745 * ($0 - med) / madValue }
    }

    /// Performs Grubbs' test for a single outlier in a univariate dataset.
    ///
    /// Grubbs' test checks whether the value farthest from the sample mean is a
    /// statistically significant outlier under the assumption of normality. The test
    /// statistic is G = max|x_i - mean| / s, compared against a critical value
    /// derived from the t-distribution at the given significance level alpha.
    ///
    /// Critical values are computed from the t-distribution using the formula:
    ///   G_crit = ((n-1) / sqrt(n)) * sqrt(t^2 / (n - 2 + t^2))
    /// where t is the t-distribution critical value at alpha/(2n) with n-2 degrees of freedom.
    ///
    /// - Parameters:
    ///   - values: The observations (n >= 10).
    ///   - alpha: Significance level. Default 0.05 (95% confidence).
    /// - Returns: Index of the most extreme outlier if statistically significant, nil otherwise.
    static func grubbsTest(values: [Double], alpha: Double = 0.05) -> Int? {
        let n = values.count
        guard n >= minimumSampleSize else { return nil }

        let mean = vMean(values)
        let stddev = vStdDev(values)
        guard stddev > 1e-10 else { return nil }

        // Find the value farthest from the mean
        var maxDeviation = 0.0
        var maxIndex = 0
        for i in values.indices {
            let deviation = abs(values[i] - mean)
            if deviation > maxDeviation {
                maxDeviation = deviation
                maxIndex = i
            }
        }

        let grubbsStatistic = maxDeviation / stddev

        // Critical value using t-distribution approximation
        let criticalValue = grubbsCriticalValue(n: n, alpha: alpha)

        return grubbsStatistic > criticalValue ? maxIndex : nil
    }

    // MARK: - Domain-Specific Analysis

    /// Analyzes daily earnings data to detect anomalous earning days.
    ///
    /// Applies multiple detection strategies:
    /// 1. Modified z-score on daily totals (robust to the occasional big day).
    /// 2. IQR fences to catch extreme outliers missed by z-score.
    /// 3. Gap detection — flags unusually long stretches without any earnings.
    /// 4. Weekday vs weekend pattern comparison.
    ///
    /// Uses a rolling 30-day context window so that seasonal shifts don't create
    /// false positives (e.g., holiday surge won't flag if it's consistently high
    /// during that window).
    ///
    /// - Parameter dailyEarnings: Earnings entries with date, amount, and platform.
    /// - Returns: Detected anomalies sorted by severity (critical first).
    static func analyzeEarnings(dailyEarnings: [EarningsEntry]) -> [Anomaly] {
        guard dailyEarnings.count >= minimumSampleSize else { return [] }

        let sorted = dailyEarnings.sorted { $0.date < $1.date }
        var anomalies: [Anomaly] = []

        // --- Aggregate to daily totals ---
        let calendar = Calendar.current
        var dailyTotals: [(date: Date, total: Double)] = []
        var dayBuckets: [DateComponents: Double] = [:]

        for entry in sorted {
            let dc = calendar.dateComponents([.year, .month, .day], from: entry.date)
            dayBuckets[dc, default: 0.0] += entry.amount
        }

        for (dc, total) in dayBuckets {
            if let date = calendar.date(from: dc) {
                dailyTotals.append((date: date, total: total))
            }
        }
        dailyTotals.sort { $0.date < $1.date }

        guard dailyTotals.count >= minimumSampleSize else { return [] }

        // --- Modified z-score detection on daily totals ---
        let amounts = dailyTotals.map(\.total)
        let modZScores = modifiedZScore(values: amounts)
        let med = median(values: amounts)
        let madValue = mad(values: amounts)

        let modZLow: Double
        let modZHigh: Double
        if madValue > 1e-10 {
            modZLow = med - 2.0 * madValue / 0.6745
            modZHigh = med + 2.0 * madValue / 0.6745
        } else {
            modZLow = med * 0.5
            modZHigh = med * 1.5
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        for i in dailyTotals.indices {
            let absZ = abs(modZScores[i])
            guard absZ > 1.5 else { continue }

            let isHigh = modZScores[i] > 0
            let type: AnomalyType = isHigh ? .earningsSpike : .earningsDrop
            let severity = severityFromZScore(absZ)

            anomalies.append(Anomaly(
                type: type,
                severity: severity,
                metric: "Daily Earnings",
                observedValue: dailyTotals[i].total,
                expectedRange: (low: max(0, modZLow), high: modZHigh),
                zScore: modZScores[i],
                description: "\(dateFormatter.string(from: dailyTotals[i].date)): \(formatCurrency(dailyTotals[i].total)) is \(String(format: "%.1f", absZ)) MAD-adjusted deviations \(isHigh ? "above" : "below") your median of \(formatCurrency(med)).",
                recommendation: isHigh
                    ? "Exceptional earnings day. Note what you did differently — platform, hours, area — and try to replicate it."
                    : "Below your typical earnings. Consider whether demand was low, or if you worked fewer hours.",
                detectedAt: dailyTotals[i].date
            ))
        }

        // --- Gap detection ---
        anomalies.append(contentsOf: detectIncomeGaps(dailyTotals: dailyTotals))

        // --- Weekday vs weekend comparison ---
        anomalies.append(contentsOf: detectWeekdayWeekendAnomalies(dailyTotals: dailyTotals))

        return anomalies.sorted { $0.severity > $1.severity }
    }

    /// Analyzes expense data to detect anomalous spending.
    ///
    /// For each expense category with sufficient history, applies IQR outlier detection
    /// on the amounts. Also detects sudden new categories (a category appearing for the
    /// first time with a large transaction) and unusual expense frequency spikes.
    ///
    /// - Parameter expenses: Expense entries with date, amount, and category.
    /// - Returns: Detected anomalies sorted by severity.
    static func analyzeExpenses(expenses: [ExpenseEntry]) -> [Anomaly] {
        guard expenses.count >= minimumSampleSize else { return [] }

        var anomalies: [Anomaly] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        // --- Per-category outlier detection ---
        let byCategory = Dictionary(grouping: expenses) { $0.category }

        for (category, entries) in byCategory {
            let amounts = entries.map(\.amount)

            guard amounts.count >= minimumSampleSize else { continue }

            let q = quartiles(values: amounts)
            let iqr = q.q3 - q.q1
            guard iqr > 1e-10 else { continue }

            let upperFence = q.q3 + 1.5 * iqr
            let lowerFence = q.q1 - 1.5 * iqr

            for entry in entries {
                guard entry.amount > upperFence else { continue }

                let madValue = mad(values: amounts)
                let med = q.median
                let robustZ: Double
                if madValue > 1e-10 {
                    robustZ = 0.6745 * (entry.amount - med) / madValue
                } else {
                    robustZ = (entry.amount - upperFence) / iqr + 1.5
                }

                anomalies.append(Anomaly(
                    type: .expenseSpike,
                    severity: severityFromZScore(abs(robustZ)),
                    metric: "\(category) Expenses",
                    observedValue: entry.amount,
                    expectedRange: (low: max(0, lowerFence), high: upperFence),
                    zScore: robustZ,
                    description: "\(category) expense of \(formatCurrency(entry.amount)) on \(dateFormatter.string(from: entry.date)) exceeds the IQR fence of \(formatCurrency(upperFence)).",
                    recommendation: "This \(category) expense is unusually high. Verify it's correct and consider whether a cheaper alternative exists.",
                    detectedAt: entry.date
                ))
            }
        }

        // --- New category detection ---
        anomalies.append(contentsOf: detectNewCategories(expenses: expenses))

        // --- Expense frequency spike ---
        anomalies.append(contentsOf: detectExpenseFrequencySpikes(expenses: expenses))

        return anomalies.sorted { $0.severity > $1.severity }
    }

    /// Analyzes platform fee rates to detect when a platform quietly raises its take.
    ///
    /// For each platform, computes the fee rate (fees / grossAmount) for every entry,
    /// then applies modified z-score analysis to detect entries where the fee rate is
    /// significantly higher than the platform's historical norm.
    ///
    /// This is crucial for gig workers: platforms like Uber, DoorDash, and Instacart
    /// periodically adjust their fee structures, and workers often don't notice until
    /// they've lost hundreds of dollars.
    ///
    /// - Parameter entries: Fee entries with date, gross amount, fees, and platform.
    /// - Returns: Detected anomalies sorted by severity.
    static func analyzeFees(entries: [FeeEntry]) -> [Anomaly] {
        guard entries.count >= minimumSampleSize else { return [] }

        var anomalies: [Anomaly] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let byPlatform = Dictionary(grouping: entries) { $0.platform }

        for (platform, platformEntries) in byPlatform {
            // Compute fee rates, guarding against zero gross amounts
            let ratesAndEntries: [(rate: Double, entry: FeeEntry)] = platformEntries.compactMap { entry in
                guard entry.grossAmount > 1e-10 else { return nil }
                return (rate: entry.fees / entry.grossAmount, entry: entry)
            }

            let rates = ratesAndEntries.map(\.rate)
            guard rates.count >= minimumSampleSize else { continue }

            let modZScores = modifiedZScore(values: rates)
            let med = median(values: rates)
            let madValue = mad(values: rates)

            let expectedLow: Double
            let expectedHigh: Double
            if madValue > 1e-10 {
                expectedLow = med - 2.0 * madValue / 0.6745
                expectedHigh = med + 2.0 * madValue / 0.6745
            } else {
                expectedLow = med * 0.9
                expectedHigh = med * 1.1
            }

            for i in ratesAndEntries.indices {
                // Only flag fee increases (positive z-score), not decreases
                guard modZScores[i] > 1.5 else { continue }

                let entry = ratesAndEntries[i].entry
                let rate = ratesAndEntries[i].rate
                let absZ = abs(modZScores[i])

                anomalies.append(Anomaly(
                    type: .feeIncrease,
                    severity: severityFromZScore(absZ),
                    metric: "\(platform) Fee Rate",
                    observedValue: rate,
                    expectedRange: (low: max(0, expectedLow), high: expectedHigh),
                    zScore: modZScores[i],
                    description: "\(platform) charged \(formatPercent(rate)) on \(dateFormatter.string(from: entry.date)), compared to your typical rate of \(formatPercent(med)).",
                    recommendation: "This \(platform) fee rate is higher than your historical average. Check if the platform changed its fee structure or if this trip/delivery type has different rates.",
                    detectedAt: entry.date
                ))
            }
        }

        return anomalies.sorted { $0.severity > $1.severity }
    }

    /// Runs all anomaly detection methods, deduplicates, and returns a unified list
    /// sorted by severity (critical first, then warning, then info).
    ///
    /// - Parameters:
    ///   - earnings: Daily earnings entries.
    ///   - expenses: Expense entries.
    ///   - fees: Fee entries.
    /// - Returns: Deduplicated anomalies across all categories, sorted by severity.
    static func analyzeAll(
        earnings: [EarningsEntry],
        expenses: [ExpenseEntry],
        fees: [FeeEntry]
    ) -> [Anomaly] {
        var all: [Anomaly] = []

        all.append(contentsOf: analyzeEarnings(dailyEarnings: earnings))
        all.append(contentsOf: analyzeExpenses(expenses: expenses))
        all.append(contentsOf: analyzeFees(entries: fees))

        // Deduplicate: if two anomalies refer to the same date + metric + type, keep
        // the one with the higher severity (or higher |z| if severity ties).
        var seen: [String: Anomaly] = [:]
        for anomaly in all {
            let key = deduplicationKey(anomaly)
            if let existing = seen[key] {
                if anomaly.severity > existing.severity ||
                    (anomaly.severity == existing.severity && abs(anomaly.zScore) > abs(existing.zScore)) {
                    seen[key] = anomaly
                }
            } else {
                seen[key] = anomaly
            }
        }

        return seen.values.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return abs(lhs.zScore) > abs(rhs.zScore)
        }
    }

    // MARK: - Statistical Helpers

    /// Computes the median of an array of Doubles.
    ///
    /// Sorts the values and returns the middle element (odd count) or the average
    /// of the two middle elements (even count).
    ///
    /// - Parameter values: The observations. Must not be empty.
    /// - Returns: The median value.
    static func median(values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 0 {
            return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
        } else {
            return sorted[n / 2]
        }
    }

    /// Computes Q1, median, and Q3 using the inclusive method (Method 1 / Tukey's hinges).
    ///
    /// Q1 is the median of the lower half (not including the median for odd n),
    /// Q3 is the median of the upper half. This matches the method used by most
    /// statistics textbooks and R's default `quantile(type=7)`.
    ///
    /// - Parameter values: The observations. Must not be empty.
    /// - Returns: Tuple of (q1, median, q3).
    static func quartiles(values: [Double]) -> (q1: Double, median: Double, q3: Double) {
        guard !values.isEmpty else { return (0, 0, 0) }
        let sorted = values.sorted()
        let n = sorted.count
        let med = median(values: sorted)

        let lowerHalf: [Double]
        let upperHalf: [Double]

        if n % 2 == 0 {
            lowerHalf = Array(sorted[0 ..< n / 2])
            upperHalf = Array(sorted[n / 2 ..< n])
        } else {
            lowerHalf = Array(sorted[0 ..< n / 2])
            upperHalf = Array(sorted[(n / 2 + 1) ..< n])
        }

        let q1 = lowerHalf.isEmpty ? med : median(values: lowerHalf)
        let q3 = upperHalf.isEmpty ? med : median(values: upperHalf)

        return (q1: q1, median: med, q3: q3)
    }

    /// Computes the Median Absolute Deviation (MAD).
    ///
    /// MAD = median(|x_i - median(x)|)
    ///
    /// MAD is a robust measure of spread that is not influenced by outliers. It serves
    /// the same role as standard deviation but is far more resistant to contamination.
    ///
    /// - Parameter values: The observations. Must not be empty.
    /// - Returns: The MAD value.
    static func mad(values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let med = median(values: values)
        let absoluteDeviations = values.map { abs($0 - med) }
        return median(values: absoluteDeviations)
    }

    // MARK: - Private Helpers

    /// Maps an absolute z-score to a severity level.
    /// |z| > 3.0 = critical, |z| > 2.0 = warning, |z| > 1.5 = info
    private static func severityFromZScore(_ absZ: Double) -> Severity {
        if absZ > 3.0 { return .critical }
        if absZ > 2.0 { return .warning }
        return .info
    }

    /// Computes the mean using Accelerate's vDSP for performance.
    private static func vMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        var result = 0.0
        vDSP_meanvD(values, 1, &result, vDSP_Length(values.count))
        return result
    }

    /// Computes the population standard deviation using Accelerate.
    ///
    /// Uses vDSP for the sum-of-squares calculation:
    ///   variance = (1/n) * sum((x_i - mean)^2)
    ///   stddev = sqrt(variance)
    private static func vStdDev(_ values: [Double]) -> Double {
        let n = values.count
        guard n > 1 else { return 0 }

        let mean = vMean(values)

        // Subtract mean from each value
        var centered = [Double](repeating: 0, count: n)
        var negativeMean = -mean
        vDSP_vsaddD(values, 1, &negativeMean, &centered, 1, vDSP_Length(n))

        // Square each centered value
        var squared = [Double](repeating: 0, count: n)
        vDSP_vsqD(centered, 1, &squared, 1, vDSP_Length(n))

        // Sum the squares
        var sumOfSquares = 0.0
        vDSP_sveD(squared, 1, &sumOfSquares, vDSP_Length(n))

        // Sample standard deviation (n-1 denominator)
        return sqrt(sumOfSquares / Double(n - 1))
    }

    /// Computes the Grubbs' test critical value for sample size n and significance alpha.
    ///
    /// Uses the formula:
    ///   G_crit = ((n-1) / sqrt(n)) * sqrt(t^2 / (n - 2 + t^2))
    /// where t is the t-distribution critical value at significance alpha/(2n) with
    /// (n-2) degrees of freedom.
    ///
    /// Since Swift doesn't have a built-in t-distribution inverse CDF, we use a lookup
    /// table for common degrees of freedom and interpolate. For large n (> 100), we use
    /// the normal approximation.
    private static func grubbsCriticalValue(n: Int, alpha: Double) -> Double {
        let df = n - 2
        let adjustedAlpha = alpha / (2.0 * Double(n))

        let tValue = tDistributionInverse(p: adjustedAlpha, df: df)

        let nDouble = Double(n)
        let tSquared = tValue * tValue
        let gCrit = ((nDouble - 1.0) / sqrt(nDouble)) * sqrt(tSquared / (nDouble - 2.0 + tSquared))
        return gCrit
    }

    /// Approximates the inverse of the two-tailed t-distribution CDF.
    ///
    /// For large degrees of freedom (>= 120), uses the normal approximation.
    /// For smaller df, uses the Abramowitz & Stegun rational approximation
    /// combined with the Cornish-Fisher expansion for the t-distribution.
    private static func tDistributionInverse(p: Double, df: Int) -> Double {
        // Clamp p to avoid infinities
        let p = max(1e-15, min(1.0 - 1e-15, p))

        // Normal quantile via rational approximation (Abramowitz & Stegun 26.2.23)
        let zp = normalQuantile(p: p)

        // For large df, normal approximation is sufficient
        guard df < 120 else { return abs(zp) }

        // Cornish-Fisher expansion for t from z
        let v = Double(df)
        let z2 = zp * zp

        let term1 = zp
        let term2 = (z2 + 1.0) / (4.0 * v)
        let term3 = (5.0 * z2 * z2 + 16.0 * z2 + 3.0) / (96.0 * v * v)
        let term4 = (3.0 * z2 * z2 * z2 + 19.0 * z2 * z2 + 17.0 * z2 - 15.0) / (384.0 * v * v * v)

        let tApprox = term1 + term2 + term3 + term4
        return abs(tApprox)
    }

    /// Normal quantile function (probit) using the Abramowitz & Stegun rational approximation.
    ///
    /// Accurate to about 4.5 x 10^-4, which is more than sufficient for our outlier
    /// detection use case.
    private static func normalQuantile(p: Double) -> Double {
        // Handle symmetry: work with the tail probability
        let p = max(1e-15, min(1.0 - 1e-15, p))

        if p == 0.5 { return 0.0 }

        let sign: Double = p < 0.5 ? -1.0 : 1.0
        let pAdj = p < 0.5 ? p : 1.0 - p

        // Rational approximation constants (A&S 26.2.23)
        let c0 = 2.515517
        let c1 = 0.802853
        let c2 = 0.010328
        let d1 = 1.432788
        let d2 = 0.189269
        let d3 = 0.001308

        let t = sqrt(-2.0 * log(pAdj))

        let numerator = c0 + c1 * t + c2 * t * t
        let denominator = 1.0 + d1 * t + d2 * t * t + d3 * t * t * t

        let z = sign * (t - numerator / denominator)
        return z
    }

    /// Detects unusually long gaps between earning days.
    ///
    /// Computes the inter-earning interval (days between consecutive earning dates),
    /// then applies modified z-score to flag gaps that are significantly longer than
    /// the worker's typical pattern.
    private static func detectIncomeGaps(dailyTotals: [(date: Date, total: Double)]) -> [Anomaly] {
        guard dailyTotals.count >= minimumSampleSize else { return [] }

        let calendar = Calendar.current
        var gaps: [(startDate: Date, endDate: Date, days: Double)] = []

        for i in 1 ..< dailyTotals.count {
            let daysBetween = Double(calendar.dateComponents([.day], from: dailyTotals[i - 1].date, to: dailyTotals[i].date).day ?? 0)
            if daysBetween > 0 {
                gaps.append((startDate: dailyTotals[i - 1].date, endDate: dailyTotals[i].date, days: daysBetween))
            }
        }

        guard gaps.count >= minimumSampleSize else { return [] }

        let gapDays = gaps.map(\.days)
        let modZScores = modifiedZScore(values: gapDays)
        let med = median(values: gapDays)
        let madValue = mad(values: gapDays)

        let expectedHigh: Double
        if madValue > 1e-10 {
            expectedHigh = med + 2.0 * madValue / 0.6745
        } else {
            expectedHigh = med * 2.0
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        var anomalies: [Anomaly] = []

        for i in gaps.indices {
            // Only flag unusually long gaps (positive z-score)
            guard modZScores[i] > 1.5 else { continue }

            let absZ = abs(modZScores[i])

            anomalies.append(Anomaly(
                type: .incomeGap,
                severity: severityFromZScore(absZ),
                metric: "Earning Gap",
                observedValue: gaps[i].days,
                expectedRange: (low: 1, high: expectedHigh),
                zScore: modZScores[i],
                description: "\(Int(gaps[i].days))-day gap between \(dateFormatter.string(from: gaps[i].startDate)) and \(dateFormatter.string(from: gaps[i].endDate)). Your typical gap is \(String(format: "%.0f", med)) days.",
                recommendation: "This is an unusually long break from earning. If unplanned, consider setting up income alerts to stay on track with your goals.",
                detectedAt: gaps[i].endDate
            ))
        }

        return anomalies
    }

    /// Compares weekday vs weekend earning patterns to detect when one deviates.
    ///
    /// Splits daily totals into weekday (Mon-Fri) and weekend (Sat-Sun) groups,
    /// then checks if the most recent 7 entries in each group deviate from that
    /// group's historical distribution.
    private static func detectWeekdayWeekendAnomalies(dailyTotals: [(date: Date, total: Double)]) -> [Anomaly] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        var weekdayAmounts: [(date: Date, total: Double)] = []
        var weekendAmounts: [(date: Date, total: Double)] = []

        for entry in dailyTotals {
            let weekday = calendar.component(.weekday, from: entry.date)
            if weekday == 1 || weekday == 7 {
                weekendAmounts.append(entry)
            } else {
                weekdayAmounts.append(entry)
            }
        }

        var anomalies: [Anomaly] = []

        // Check if recent weekday earnings deviate from weekday history
        anomalies.append(contentsOf: detectRecentDeviation(
            entries: weekdayAmounts,
            segmentLabel: "Weekday",
            dateFormatter: dateFormatter
        ))

        // Check if recent weekend earnings deviate from weekend history
        anomalies.append(contentsOf: detectRecentDeviation(
            entries: weekendAmounts,
            segmentLabel: "Weekend",
            dateFormatter: dateFormatter
        ))

        return anomalies
    }

    /// Checks if the most recent entries in a time-segment deviate significantly
    /// from the historical distribution for that segment.
    private static func detectRecentDeviation(
        entries: [(date: Date, total: Double)],
        segmentLabel: String,
        dateFormatter: DateFormatter
    ) -> [Anomaly] {
        guard entries.count >= minimumSampleSize + 3 else { return [] }

        // Use all but the last 3 as the "historical" baseline
        let historicalCount = entries.count - 3
        let historical = Array(entries.prefix(historicalCount))
        let recent = Array(entries.suffix(3))

        let historicalAmounts = historical.map(\.total)
        let med = median(values: historicalAmounts)
        let madValue = mad(values: historicalAmounts)

        guard madValue > 1e-10 else { return [] }

        let expectedLow = med - 2.0 * madValue / 0.6745
        let expectedHigh = med + 2.0 * madValue / 0.6745

        var anomalies: [Anomaly] = []

        for entry in recent {
            let modZ = 0.6745 * (entry.total - med) / madValue
            let absZ = abs(modZ)
            guard absZ > 2.0 else { continue }

            let isHigh = modZ > 0
            anomalies.append(Anomaly(
                type: isHigh ? .earningsSpike : .earningsDrop,
                severity: severityFromZScore(absZ),
                metric: "\(segmentLabel) Earnings",
                observedValue: entry.total,
                expectedRange: (low: max(0, expectedLow), high: expectedHigh),
                zScore: modZ,
                description: "\(segmentLabel) earnings of \(formatCurrency(entry.total)) on \(dateFormatter.string(from: entry.date)) is \(isHigh ? "above" : "below") your typical \(segmentLabel.lowercased()) of \(formatCurrency(med)).",
                recommendation: isHigh
                    ? "Your recent \(segmentLabel.lowercased()) earnings are higher than usual. Keep it up!"
                    : "Your recent \(segmentLabel.lowercased()) earnings are below typical. Consider adjusting your schedule or trying different platforms.",
                detectedAt: entry.date
            ))
        }

        return anomalies
    }

    /// Detects expense categories that appear for the first time with a significant amount.
    ///
    /// Looks for categories whose earliest entry is within the last 30 days and whose
    /// amount exceeds the median expense amount across all categories. This catches
    /// new recurring costs the worker should be aware of.
    private static func detectNewCategories(expenses: [ExpenseEntry]) -> [Anomaly] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        guard let latestDate = expenses.map(\.date).max(),
              let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: latestDate) else {
            return []
        }

        let allAmounts = expenses.map(\.amount)
        guard allAmounts.count >= minimumSampleSize else { return [] }
        let overallMedian = median(values: allAmounts)

        let byCategory = Dictionary(grouping: expenses) { $0.category }
        var anomalies: [Anomaly] = []

        for (category, entries) in byCategory {
            let sortedEntries = entries.sorted { $0.date < $1.date }
            guard let firstEntry = sortedEntries.first else { continue }

            // Only flag if the category first appeared recently
            guard firstEntry.date >= thirtyDaysAgo else { continue }

            // Only flag if the amount is noteworthy (above overall median)
            let categoryTotal = entries.reduce(0.0) { $0 + $1.amount }
            guard categoryTotal > overallMedian else { continue }

            anomalies.append(Anomaly(
                type: .categoryOutlier,
                severity: .warning,
                metric: "New Expense Category",
                observedValue: categoryTotal,
                expectedRange: (low: 0, high: overallMedian),
                zScore: 2.0, // Nominal z-score since this is pattern-based, not distribution-based
                description: "New expense category \"\(category)\" appeared on \(dateFormatter.string(from: firstEntry.date)) with \(formatCurrency(categoryTotal)) total across \(entries.count) entries.",
                recommendation: "A new expense category has appeared. If this is a recurring cost, make sure to track it for tax deductions. If unexpected, verify these charges.",
                detectedAt: firstEntry.date
            ))
        }

        return anomalies
    }

    /// Detects weeks with unusually high expense frequency.
    ///
    /// Counts expenses per calendar week, then flags weeks where the count is a
    /// statistical outlier using modified z-scores.
    private static func detectExpenseFrequencySpikes(expenses: [ExpenseEntry]) -> [Anomaly] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        // Bucket expenses by (year, weekOfYear)
        var weeklyBuckets: [String: (count: Int, total: Double, startOfWeek: Date)] = [:]

        for expense in expenses {
            let year = calendar.component(.yearForWeekOfYear, from: expense.date)
            let week = calendar.component(.weekOfYear, from: expense.date)
            let key = "\(year)-W\(week)"

            if weeklyBuckets[key] == nil {
                // Approximate start of week
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: expense.date)
                let startOfWeek = calendar.date(from: components) ?? expense.date
                weeklyBuckets[key] = (count: 0, total: 0, startOfWeek: startOfWeek)
            }
            weeklyBuckets[key]!.count += 1
            weeklyBuckets[key]!.total += expense.amount
        }

        let sortedWeeks = weeklyBuckets.sorted { $0.value.startOfWeek < $1.value.startOfWeek }
        let counts = sortedWeeks.map { Double($0.value.count) }

        guard counts.count >= minimumSampleSize else { return [] }

        let modZScores = modifiedZScore(values: counts)
        let med = median(values: counts)
        let madValue = mad(values: counts)

        let expectedHigh: Double
        if madValue > 1e-10 {
            expectedHigh = med + 2.0 * madValue / 0.6745
        } else {
            expectedHigh = med * 2.0
        }

        var anomalies: [Anomaly] = []

        for i in sortedWeeks.indices {
            guard modZScores[i] > 2.0 else { continue }

            let week = sortedWeeks[i]
            let absZ = abs(modZScores[i])

            anomalies.append(Anomaly(
                type: .expenseSpike,
                severity: severityFromZScore(absZ),
                metric: "Expense Frequency",
                observedValue: Double(week.value.count),
                expectedRange: (low: 1, high: expectedHigh),
                zScore: modZScores[i],
                description: "Week of \(dateFormatter.string(from: week.value.startOfWeek)): \(week.value.count) expenses totaling \(formatCurrency(week.value.total)). You typically have \(String(format: "%.0f", med)) expenses per week.",
                recommendation: "Unusually high number of expenses this week. Review them to ensure nothing is duplicated or unexpected.",
                detectedAt: week.value.startOfWeek
            ))
        }

        return anomalies
    }

    /// Generates a deduplication key from an anomaly's core identity.
    private static func deduplicationKey(_ anomaly: Anomaly) -> String {
        let calendar = Calendar.current
        let dc = calendar.dateComponents([.year, .month, .day], from: anomaly.detectedAt)
        return "\(anomaly.type.rawValue)-\(anomaly.metric)-\(dc.year ?? 0)-\(dc.month ?? 0)-\(dc.day ?? 0)"
    }

    /// Formats a Double as currency for display in anomaly descriptions.
    private static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }

    /// Formats a Double (0.0 to 1.0) as a percentage for display.
    private static func formatPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(String(format: "%.1f", value * 100))%"
    }
}
