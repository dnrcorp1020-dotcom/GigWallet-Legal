import Foundation
import Accelerate

/// GigWallet Financial Health Score — a proprietary composite score (0–100) that
/// quantifies how well a gig worker is managing their finances.
///
/// This is the "Tax Anxiety Score" concept evolved into a comprehensive financial
/// health metric. It's the single most important number in the app: it answers
/// "Am I on track?" instantly.
///
/// The score combines 6 weighted dimensions via ML-style weighted scoring:
///
///   1. Tax Readiness (25%)    — Are quarterly payments on track? Safe harbor compliance?
///   2. Deduction Coverage (20%) — Are they capturing available deductions?
///   3. Expense Control (15%)   — Is their expense-to-income ratio healthy?
///   4. Income Stability (15%)  — How volatile is their income?
///   5. Savings Behavior (15%)  — Are they setting aside enough for taxes?
///   6. Growth Trajectory (10%) — Is income trending up or down?
///
/// Score interpretation:
///   90-100: Excellent — "Your finances are dialed in"
///   75-89:  Good      — "Solid, a few opportunities"
///   60-74:  Fair      — "Needs attention in key areas"
///   40-59:  At Risk   — "Several red flags need fixing"
///   0-39:   Critical  — "Immediate action needed"
///
/// All computation is on-device using Accelerate framework for vector math.
enum FinancialHealthEngine: Sendable {

    // MARK: - Output Types

    struct HealthScore: Sendable {
        /// Overall composite score 0-100
        let score: Int
        /// Letter grade: A+, A, B+, B, C+, C, D, F
        let grade: String
        /// One-line status label
        let status: String
        /// Accent color name for UI
        let accentColor: String
        /// Individual dimension scores
        let dimensions: [Dimension]
        /// Top 3 actionable recommendations sorted by impact
        let recommendations: [Recommendation]
        /// Score trend vs last calculation (nil if first time)
        let trend: ScoreTrend?
    }

    struct Dimension: Sendable, Identifiable {
        let id: String
        let name: String
        let score: Double   // 0-100 for this dimension
        let weight: Double  // 0-1, how much it contributes
        let icon: String    // SF Symbol
        let detail: String  // Explanation
    }

    struct Recommendation: Sendable, Identifiable {
        let id: String
        let title: String
        let detail: String
        let impact: Impact   // How much it would improve the score
        let icon: String
        let accentColor: String
    }

    enum Impact: String, Sendable {
        case high = "High Impact"
        case medium = "Medium Impact"
        case low = "Low Impact"
    }

    struct ScoreTrend: Sendable {
        let direction: TrendDirection
        let change: Int  // Points changed
    }

    enum TrendDirection: String, Sendable {
        case up = "Improving"
        case down = "Declining"
        case stable = "Stable"
    }

    // MARK: - Input Snapshot

    struct FinancialSnapshot: Sendable {
        let yearlyGrossIncome: Double
        let yearlyNetIncome: Double
        let yearlyExpenses: Double
        let yearlyDeductions: Double
        let yearlyMileage: Double
        let estimatedTax: Double
        let taxPaid: Double
        let quarterlyPaymentDue: Double
        let safeHarborCompliant: Bool
        let deductionCategoriesUsed: Int
        let totalDeductionCategories: Int  // e.g., 13 IRS categories
        let monthlyIncomeValues: [Double]  // Last 6-12 months for volatility
        let weeklyIncomeValues: [Double]   // Last 8-12 weeks for trend
        let effectiveTaxRate: Double
        let hasHomeoOfficeDeduction: Bool
        let hasMileageDeductions: Bool
        let hasHealthInsurance: Bool
        let hasRetirementContributions: Bool
        let priorYearTax: Double
        let monthsActive: Int
    }

    // MARK: - Calculation

    static func calculate(snapshot: FinancialSnapshot) -> HealthScore {
        // Compute each dimension
        let taxReadiness = computeTaxReadiness(snapshot)
        let deductionCoverage = computeDeductionCoverage(snapshot)
        let expenseControl = computeExpenseControl(snapshot)
        let incomeStability = computeIncomeStability(snapshot)
        let savingsBehavior = computeSavingsBehavior(snapshot)
        let growthTrajectory = computeGrowthTrajectory(snapshot)

        let dimensions = [taxReadiness, deductionCoverage, expenseControl,
                          incomeStability, savingsBehavior, growthTrajectory]

        // Weighted composite score using vDSP
        let scores = dimensions.map { $0.score }
        let weights = dimensions.map { $0.weight }

        var weightedSum: Double = 0
        var totalWeight: Double = 0
        vDSP_dotprD(scores, 1, weights, 1, &weightedSum, vDSP_Length(scores.count))
        vDSP_sveD(weights, 1, &totalWeight, vDSP_Length(weights.count))

        let compositeScore = totalWeight > 0 ? Int(min(max(weightedSum / totalWeight, 0), 100)) : 50

        // Generate grade, status, color
        let (grade, status, color) = gradeForScore(compositeScore)

        // Generate recommendations
        let recommendations = generateRecommendations(dimensions: dimensions, snapshot: snapshot)

        return HealthScore(
            score: compositeScore,
            grade: grade,
            status: status,
            accentColor: color,
            dimensions: dimensions,
            recommendations: Array(recommendations.prefix(3)),
            trend: nil
        )
    }

    // MARK: - Dimension Computations

    private static func computeTaxReadiness(_ s: FinancialSnapshot) -> Dimension {
        var score: Double = 50 // Start at midpoint

        // Safe harbor compliance: +30 if compliant
        if s.safeHarborCompliant { score += 30 }

        // Payment progress: how much of estimated quarterly is paid
        if s.quarterlyPaymentDue > 0 {
            let paymentRatio = min(s.taxPaid / s.estimatedTax, 1.0)
            score += paymentRatio * 20
        } else {
            score += 10 // Low income, not much tax needed
        }

        // Prior year data available (for safe harbor planning)
        if s.priorYearTax > 0 { score += 5 }

        // Penalty: if they owe a lot and haven't paid
        if s.estimatedTax > 1000 && s.taxPaid < s.estimatedTax * 0.25 && s.monthsActive >= 4 {
            score -= 15
        }

        score = min(max(score, 0), 100)

        let detail: String
        if score >= 80 {
            detail = "Tax payments on track. Safe harbor compliant."
        } else if score >= 60 {
            detail = "Tax payments progressing. Review quarterly targets."
        } else {
            detail = "Behind on tax payments. Risk of IRS penalties."
        }

        return Dimension(
            id: "tax_readiness",
            name: "Tax Readiness",
            score: score,
            weight: 0.25,
            icon: "building.columns.fill",
            detail: detail
        )
    }

    private static func computeDeductionCoverage(_ s: FinancialSnapshot) -> Dimension {
        var score: Double = 30 // Base — everyone gets some credit

        // Category coverage ratio
        if s.totalDeductionCategories > 0 {
            let coverageRatio = Double(s.deductionCategoriesUsed) / Double(s.totalDeductionCategories)
            score += coverageRatio * 30
        }

        // Key deductions: mileage, home office, health insurance, retirement
        if s.hasMileageDeductions { score += 10 }
        if s.hasHomeoOfficeDeduction { score += 8 }
        if s.hasHealthInsurance { score += 7 }
        if s.hasRetirementContributions { score += 8 }

        // Deduction-to-income ratio check (industry avg is ~18% for gig workers)
        if s.yearlyGrossIncome > 0 {
            let deductionRate = s.yearlyDeductions / s.yearlyGrossIncome
            if deductionRate >= 0.15 { score += 7 }
            else if deductionRate < 0.05 && s.monthsActive >= 3 { score -= 10 }
        }

        score = min(max(score, 0), 100)

        let detail: String
        let used = s.deductionCategoriesUsed
        let total = s.totalDeductionCategories
        if score >= 80 {
            detail = "Capturing \(used)/\(total) deduction categories. Well optimized."
        } else if score >= 50 {
            detail = "Using \(used)/\(total) categories. \(total - used) potential deductions missing."
        } else {
            detail = "Only \(used)/\(total) categories. Significant savings left on the table."
        }

        return Dimension(
            id: "deduction_coverage",
            name: "Deduction Coverage",
            score: score,
            weight: 0.20,
            icon: "tag.fill",
            detail: detail
        )
    }

    private static func computeExpenseControl(_ s: FinancialSnapshot) -> Dimension {
        guard s.yearlyNetIncome > 0 else {
            return Dimension(
                id: "expense_control", name: "Expense Control",
                score: 50, weight: 0.15, icon: "gauge.with.dots.needle.50percent",
                detail: "Log more income to analyze expense control."
            )
        }

        let expenseRatio = s.yearlyExpenses / s.yearlyNetIncome
        let score: Double
        let detail: String

        // Industry average for gig workers is ~30%
        switch expenseRatio {
        case ..<0.15:
            score = 95
            detail = "Expense ratio \(pct(expenseRatio)). Excellent cost control."
        case 0.15..<0.25:
            score = 85
            detail = "Expense ratio \(pct(expenseRatio)). Healthy and sustainable."
        case 0.25..<0.35:
            score = 70
            detail = "Expense ratio \(pct(expenseRatio)). Near industry average."
        case 0.35..<0.45:
            score = 50
            detail = "Expense ratio \(pct(expenseRatio)). Higher than ideal."
        default:
            score = max(30 - (expenseRatio - 0.45) * 100, 0)
            detail = "Expense ratio \(pct(expenseRatio)). Eating into profits significantly."
        }

        return Dimension(
            id: "expense_control",
            name: "Expense Control",
            score: score,
            weight: 0.15,
            icon: "gauge.with.dots.needle.50percent",
            detail: detail
        )
    }

    private static func computeIncomeStability(_ s: FinancialSnapshot) -> Dimension {
        guard s.monthlyIncomeValues.count >= 3 else {
            return Dimension(
                id: "income_stability", name: "Income Stability",
                score: 50, weight: 0.15, icon: "waveform.path",
                detail: "Need 3+ months of data to assess stability."
            )
        }

        // Coefficient of Variation using vDSP
        let values = s.monthlyIncomeValues
        var mean: Double = 0
        vDSP_meanvD(values, 1, &mean, vDSP_Length(values.count))

        guard mean > 0 else {
            return Dimension(
                id: "income_stability", name: "Income Stability",
                score: 30, weight: 0.15, icon: "waveform.path",
                detail: "Income too low to assess stability."
            )
        }

        // Calculate standard deviation
        var squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        var variance: Double = 0
        vDSP_meanvD(&squaredDiffs, 1, &variance, vDSP_Length(squaredDiffs.count))
        let stdDev = sqrt(variance)
        let cv = stdDev / mean  // Coefficient of variation

        let score: Double
        let detail: String

        // CV interpretation: lower = more stable
        switch cv {
        case ..<0.15:
            score = 95
            detail = "Very stable income. Variance \(pct(cv))."
        case 0.15..<0.30:
            score = 80
            detail = "Moderately stable. Monthly variance \(pct(cv))."
        case 0.30..<0.50:
            score = 60
            detail = "Income varies \(pct(cv)) month-to-month. Plan for lean months."
        case 0.50..<0.75:
            score = 40
            detail = "High volatility (\(pct(cv))). Build a 2-month buffer."
        default:
            score = 20
            detail = "Very volatile income (\(pct(cv))). Emergency fund critical."
        }

        return Dimension(
            id: "income_stability",
            name: "Income Stability",
            score: score,
            weight: 0.15,
            icon: "waveform.path",
            detail: detail
        )
    }

    private static func computeSavingsBehavior(_ s: FinancialSnapshot) -> Dimension {
        guard s.estimatedTax > 100 else {
            return Dimension(
                id: "savings_behavior", name: "Tax Savings",
                score: 70, weight: 0.15, icon: "banknote.fill",
                detail: "Tax liability is low. Keep tracking expenses."
            )
        }

        let savingsRate = s.taxPaid / s.estimatedTax
        let score: Double
        let detail: String

        switch savingsRate {
        case 0.9...:
            score = 95
            detail = "Set aside \(pct(savingsRate)) of estimated taxes. Excellent."
        case 0.7..<0.9:
            score = 80
            detail = "\(pct(savingsRate)) funded. On track for quarterly payments."
        case 0.5..<0.7:
            score = 60
            detail = "\(pct(savingsRate)) funded. Need to catch up this quarter."
        case 0.25..<0.5:
            score = 40
            detail = "Only \(pct(savingsRate)) of taxes set aside. Risk of underpayment penalty."
        default:
            score = 20
            detail = "Less than 25% saved for taxes. Immediate action needed."
        }

        return Dimension(
            id: "savings_behavior",
            name: "Tax Savings",
            score: score,
            weight: 0.15,
            icon: "banknote.fill",
            detail: detail
        )
    }

    private static func computeGrowthTrajectory(_ s: FinancialSnapshot) -> Dimension {
        guard s.weeklyIncomeValues.count >= 4 else {
            return Dimension(
                id: "growth_trajectory", name: "Growth",
                score: 50, weight: 0.10, icon: "chart.line.uptrend.xyaxis",
                detail: "Need 4+ weeks of data to assess growth."
            )
        }

        // Linear regression on weekly income using vDSP
        let n = s.weeklyIncomeValues.count
        let x = (0..<n).map { Double($0) }
        let y = s.weeklyIncomeValues

        // slope = (n*sum(xy) - sum(x)*sum(y)) / (n*sum(x^2) - sum(x)^2)
        var sumX: Double = 0, sumY: Double = 0
        vDSP_sveD(x, 1, &sumX, vDSP_Length(n))
        vDSP_sveD(y, 1, &sumY, vDSP_Length(n))

        var xy = [Double](repeating: 0, count: n)
        vDSP_vmulD(x, 1, y, 1, &xy, 1, vDSP_Length(n))
        var sumXY: Double = 0
        vDSP_sveD(xy, 1, &sumXY, vDSP_Length(n))

        var x2 = [Double](repeating: 0, count: n)
        vDSP_vsqD(x, 1, &x2, 1, vDSP_Length(n))
        var sumX2: Double = 0
        vDSP_sveD(x2, 1, &sumX2, vDSP_Length(n))

        let denominator = Double(n) * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-10 else {
            return Dimension(
                id: "growth_trajectory", name: "Growth",
                score: 50, weight: 0.10, icon: "chart.line.uptrend.xyaxis",
                detail: "Income data too uniform to assess trend."
            )
        }

        let slope = (Double(n) * sumXY - sumX * sumY) / denominator
        let meanY = sumY / Double(n)

        // Normalize slope as % of mean weekly income
        let growthRate = meanY > 0 ? slope / meanY : 0

        let score: Double
        let detail: String

        switch growthRate {
        case 0.05...:
            score = 95
            detail = "Income growing \(pct(growthRate))/week. Strong upward trend."
        case 0.02..<0.05:
            score = 80
            detail = "Moderate growth of \(pct(growthRate))/week."
        case -0.02..<0.02:
            score = 65
            detail = "Income is stable. Consider new platforms or peak hours."
        case -0.05..<(-0.02):
            score = 40
            detail = "Income declining \(pct(abs(growthRate)))/week. Review strategy."
        default:
            score = 20
            detail = "Significant decline. Diversify platforms or adjust schedule."
        }

        return Dimension(
            id: "growth_trajectory",
            name: "Growth",
            score: score,
            weight: 0.10,
            icon: "chart.line.uptrend.xyaxis",
            detail: detail
        )
    }

    // MARK: - Recommendations

    private static func generateRecommendations(dimensions: [Dimension], snapshot: FinancialSnapshot) -> [Recommendation] {
        var recs: [Recommendation] = []

        // Sort dimensions by score ascending — worst areas first
        let sorted = dimensions.sorted { $0.score < $1.score }

        for dim in sorted {
            switch dim.id {
            case "tax_readiness" where dim.score < 70:
                recs.append(Recommendation(
                    id: "rec_tax",
                    title: "Catch up on quarterly taxes",
                    detail: "You've paid \(CurrencyFormatter.format(snapshot.taxPaid)) of an estimated \(CurrencyFormatter.format(snapshot.estimatedTax)). Set up a recurring transfer to avoid IRS penalties.",
                    impact: .high,
                    icon: "building.columns.fill",
                    accentColor: "destructive"
                ))

            case "deduction_coverage" where dim.score < 70:
                let missing = snapshot.totalDeductionCategories - snapshot.deductionCategoriesUsed
                recs.append(Recommendation(
                    id: "rec_deductions",
                    title: "Claim \(missing) missing deduction categories",
                    detail: "You're leaving money on the table. Check phone, home office, and health insurance deductions.",
                    impact: .high,
                    icon: "tag.fill",
                    accentColor: "warning"
                ))

            case "expense_control" where dim.score < 60:
                recs.append(Recommendation(
                    id: "rec_expenses",
                    title: "Reduce expense-to-income ratio",
                    detail: "Your expenses are above the 30% industry average. Review recurring costs and look for savings on gas, maintenance, and subscriptions.",
                    impact: .medium,
                    icon: "gauge.with.dots.needle.50percent",
                    accentColor: "warning"
                ))

            case "income_stability" where dim.score < 60:
                recs.append(Recommendation(
                    id: "rec_stability",
                    title: "Build a 2-month income buffer",
                    detail: "Your income varies significantly. A buffer of \(CurrencyFormatter.format(snapshot.yearlyNetIncome / 6)) would protect against lean months.",
                    impact: .medium,
                    icon: "waveform.path",
                    accentColor: "info"
                ))

            case "savings_behavior" where dim.score < 60:
                recs.append(Recommendation(
                    id: "rec_savings",
                    title: "Increase tax set-aside rate",
                    detail: "Aim to set aside \(pct(snapshot.effectiveTaxRate)) of every payment for taxes. Small consistent saves beat scrambling at deadline.",
                    impact: .high,
                    icon: "banknote.fill",
                    accentColor: "destructive"
                ))

            case "growth_trajectory" where dim.score < 50:
                recs.append(Recommendation(
                    id: "rec_growth",
                    title: "Optimize your earning schedule",
                    detail: "Your income is trending down. Try peak hours and your highest-paying platforms to reverse the trend.",
                    impact: .medium,
                    icon: "chart.line.uptrend.xyaxis",
                    accentColor: "primary"
                ))

            default:
                break
            }
        }

        return recs
    }

    // MARK: - Grading

    private static func gradeForScore(_ score: Int) -> (grade: String, status: String, color: String) {
        switch score {
        case 95...100: return ("A+", "Exceptional", "success")
        case 90..<95:  return ("A", "Excellent", "success")
        case 85..<90:  return ("A-", "Very Good", "success")
        case 80..<85:  return ("B+", "Good", "success")
        case 75..<80:  return ("B", "Solid", "primary")
        case 70..<75:  return ("B-", "Above Average", "primary")
        case 65..<70:  return ("C+", "Fair", "warning")
        case 60..<65:  return ("C", "Needs Work", "warning")
        case 50..<60:  return ("D", "At Risk", "destructive")
        default:       return ("F", "Critical", "destructive")
        }
    }

    // MARK: - Helpers

    private static func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
