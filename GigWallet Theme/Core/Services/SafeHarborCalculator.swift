import Foundation

/// IRS Safe Harbor Rules for Quarterly Estimated Tax Payments
///
/// Gig workers OVERPAY by thousands every year because they don't know these rules:
///
/// Rule 1: Pay 100% of PRIOR year's tax liability (110% if AGI > $150K)
/// Rule 2: Pay 90% of CURRENT year's tax liability
/// Rule 3: No penalty if you owe less than $1,000 at filing time
///
/// The MINIMUM legal payment is the LESSER of Rule 1 and Rule 2.
/// Most gig workers use Rule 2 (current year), but Rule 1 is often MUCH lower
/// if they're earning more this year than last.
///
/// Example: Earned $30K last year (tax: $6K), earning $60K this year (tax: $12K)
/// - Without safe harbor: they think they owe $3K/quarter = $12K
/// - With safe harbor (Rule 1): they only need to pay $1,500/quarter = $6K
/// - Savings: $6,000 in cash flow (they still owe at filing, but penalty-free)
struct SafeHarborCalculator {

    struct SafeHarborResult {
        let minimumQuarterlyPayment: Double
        let ruleUsed: SafeHarborRule
        let priorYearQuarterly: Double       // Rule 1: prior year ÷ 4
        let currentYearQuarterly: Double     // Rule 2: 90% of current ÷ 4
        let savings: Double                  // How much less than the "naive" current-year estimate
        let explanation: String
        let isUnderThousandRule: Bool        // Rule 3: owe < $1K = no penalty regardless
    }

    enum SafeHarborRule: String {
        case priorYear = "Prior Year"            // 100% of last year (or 110% if high income)
        case currentYear90 = "Current Year 90%"  // 90% of this year
        case underThreshold = "Under $1,000"     // Owe < $1K total
    }

    /// Calculate the minimum safe harbor payment for each quarter
    static func calculate(
        currentYearEstimatedTax: Double,
        priorYearTotalTax: Double,
        priorYearAGI: Double = 0,     // If > $150K, the 110% rule applies
        totalPaymentsMadeSoFar: Double,
        currentQuarter: TaxQuarter
    ) -> SafeHarborResult {

        // Rule 3: If total tax owed is under $1,000, no penalty regardless
        let remainingTax = currentYearEstimatedTax - totalPaymentsMadeSoFar
        if remainingTax < 1000 && remainingTax >= 0 {
            return SafeHarborResult(
                minimumQuarterlyPayment: 0,
                ruleUsed: .underThreshold,
                priorYearQuarterly: priorYearTotalTax / 4,
                currentYearQuarterly: currentYearEstimatedTax * 0.9 / 4,
                savings: currentYearEstimatedTax / 4,
                explanation: "You're projected to owe less than $1,000 at filing. No estimated payments required to avoid penalties.",
                isUnderThousandRule: true
            )
        }

        // Rule 1: Prior year safe harbor
        // 100% of prior year tax (110% if prior year AGI > $150K)
        let priorYearMultiplier = priorYearAGI > 150_000 ? 1.10 : 1.00
        let priorYearSafeHarbor = priorYearTotalTax * priorYearMultiplier
        let priorYearQuarterly = priorYearSafeHarbor / 4

        // Rule 2: Current year safe harbor (90% of this year's estimated tax)
        let currentYear90 = currentYearEstimatedTax * 0.90
        let currentYearQuarterly = currentYear90 / 4

        // Minimum is the LESSER of Rule 1 and Rule 2
        let naiveQuarterly = currentYearEstimatedTax / 4

        // Determine which quarters we still need to account for
        let quartersRemaining: Int
        switch currentQuarter {
        case .q1: quartersRemaining = 4
        case .q2: quartersRemaining = 3
        case .q3: quartersRemaining = 2
        case .q4: quartersRemaining = 1
        }

        // Account for payments already made — spread remaining obligation over remaining quarters
        let priorYearRemaining = max(priorYearSafeHarbor - totalPaymentsMadeSoFar, 0)
        let currentYearRemaining = max(currentYear90 - totalPaymentsMadeSoFar, 0)

        let adjustedPriorQuarterly = quartersRemaining > 0 ? priorYearRemaining / Double(quartersRemaining) : 0
        let adjustedCurrentQuarterly = quartersRemaining > 0 ? currentYearRemaining / Double(quartersRemaining) : 0

        if priorYearTotalTax > 0 && adjustedPriorQuarterly < adjustedCurrentQuarterly {
            // Rule 1 wins — prior year is cheaper
            let savings = max(naiveQuarterly - adjustedPriorQuarterly, 0)
            return SafeHarborResult(
                minimumQuarterlyPayment: max(adjustedPriorQuarterly, 0),
                ruleUsed: .priorYear,
                priorYearQuarterly: priorYearQuarterly,
                currentYearQuarterly: currentYearQuarterly,
                savings: savings,
                explanation: savings > 50
                    ? "Based on last year's tax of \(formatCurrency(priorYearTotalTax)), you only need to pay \(formatCurrency(adjustedPriorQuarterly)) this quarter to avoid penalties. That's \(formatCurrency(savings)) less than paying based on this year's income."
                    : "Your minimum penalty-free payment is \(formatCurrency(adjustedPriorQuarterly)) based on last year's tax.",
                isUnderThousandRule: false
            )
        } else {
            // Rule 2 wins — or no prior year data
            let savings = max(naiveQuarterly - adjustedCurrentQuarterly, 0)
            return SafeHarborResult(
                minimumQuarterlyPayment: max(adjustedCurrentQuarterly, 0),
                ruleUsed: .currentYear90,
                priorYearQuarterly: priorYearQuarterly,
                currentYearQuarterly: currentYearQuarterly,
                savings: savings,
                explanation: priorYearTotalTax == 0
                    ? "Enter last year's total tax to potentially lower your quarterly payments using the IRS safe harbor rule."
                    : "Your minimum penalty-free payment is \(formatCurrency(adjustedCurrentQuarterly)) (90% of estimated tax).",
                isUnderThousandRule: false
            )
        }
    }

    /// Calculate home office deduction — simplified vs actual method comparison
    static func homeOfficeDeduction(
        squareFeet: Double,
        totalHomeExpenses: Double = 0, // For actual method: rent/mortgage, utilities, insurance
        totalHomeSqFt: Double = 0
    ) -> (simplified: Double, actual: Double, recommendation: String) {

        // Simplified method: $5/sq ft, max 300 sq ft = $1,500 max
        let simplifiedSqFt = min(squareFeet, 300)
        let simplified = simplifiedSqFt * 5

        // Actual method: (office sq ft / total sq ft) × total expenses
        var actual = 0.0
        if totalHomeSqFt > 0 && totalHomeExpenses > 0 {
            let percentage = squareFeet / totalHomeSqFt
            actual = totalHomeExpenses * percentage
        }

        let recommendation: String
        if actual > simplified && actual > 0 {
            recommendation = "The actual method saves you \(formatCurrency(actual - simplified)) more. Track your rent, utilities, and insurance to claim \(formatCurrency(actual))."
        } else if simplified > 0 {
            recommendation = "Use the simplified method: \(formatCurrency(simplified)) deduction for \(String(Int(simplifiedSqFt))) sq ft. No receipts needed."
        } else {
            recommendation = "Enter your home office square footage to calculate your deduction."
        }

        return (simplified, actual, recommendation)
    }

    private static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}
