import Foundation

struct TaxEngine {

    enum TaxConstants {
        static let selfEmploymentTaxRate: Double = 0.153
        static let socialSecurityRate: Double = 0.124
        static let medicareRate: Double = 0.029
        static let selfEmploymentAdjustment: Double = 0.9235
        static let socialSecurityWageBase: Double = 176_100
        static let seTaxDeductionRate: Double = 0.5
        static let mileageRate: Double = 0.70
        static let form1099KThreshold: Double = 5_000  // Lowered to $5K for 2024+ (IRS phased rollout)
        static let form1099KTransactionThreshold: Int = 0  // Transaction count threshold removed for 2024+
    }

    struct StandardDeductions {
        /// Returns the standard deduction for a given filing status and tax year.
        /// Currently uses 2026 IRS amounts. Update annually when IRS publishes new figures.
        static func amount(for status: FilingStatus, year: Int = 2026) -> Double {
            // TODO: Add 2027+ brackets when IRS publishes them (typically October of prior year)
            // For now, 2026 values are used for all years. This is conservative —
            // deductions typically increase with inflation, so users won't over-deduct.
            switch status {
            case .single: return 15_700
            case .marriedJoint: return 31_400
            case .marriedSeparate: return 15_700
            case .headOfHousehold: return 23_500
            }
        }
    }

    static let federalBrackets2026Single: [(threshold: Double, rate: Double)] = [
        (0, 0.10),
        (11_925, 0.12),
        (48_475, 0.22),
        (103_350, 0.24),
        (197_300, 0.32),
        (250_525, 0.35),
        (626_350, 0.37)
    ]

    static let federalBrackets2026MarriedJoint: [(threshold: Double, rate: Double)] = [
        (0, 0.10),
        (23_850, 0.12),
        (96_950, 0.22),
        (206_700, 0.24),
        (394_600, 0.32),
        (501_050, 0.35),
        (751_600, 0.37)
    ]

    static let federalBrackets2026HeadOfHousehold: [(threshold: Double, rate: Double)] = [
        (0, 0.10),
        (17_000, 0.12),
        (64_850, 0.22),
        (103_350, 0.24),
        (197_300, 0.32),
        (250_500, 0.35),
        (626_350, 0.37)
    ]

    static let federalBrackets2026MarriedSeparate: [(threshold: Double, rate: Double)] = [
        (0, 0.10),
        (11_925, 0.12),
        (48_475, 0.22),
        (103_350, 0.24),
        (197_300, 0.32),
        (250_525, 0.35),
        (375_800, 0.37)
    ]

    func calculateEstimate(
        grossIncome: Double,
        totalDeductions: Double,
        filingStatus: FilingStatus,
        stateCode: String,
        w2Withholding: Double = 0,
        w2Income: Double = 0,
        personalDeduction: Double? = nil,
        taxCredits: Double = 0
    ) -> TaxCalculationResult {
        let netSEIncome = max(grossIncome - totalDeductions, 0)

        guard netSEIncome > 0 else {
            return .zero
        }

        // Self-employment tax
        let taxableSEIncome = netSEIncome * TaxConstants.selfEmploymentAdjustment
        // SS wage base applies to COMBINED W-2 + SE income; reduce cap by W-2 wages already subject to SS
        let remainingSSCap = max(TaxConstants.socialSecurityWageBase - w2Income, 0)
        let socialSecurityTax = min(taxableSEIncome, remainingSSCap) * TaxConstants.socialSecurityRate
        let medicareTax = taxableSEIncome * TaxConstants.medicareRate
        let totalSETax = socialSecurityTax + medicareTax

        // SE tax deduction (50% is deductible)
        let seTaxDeduction = totalSETax * TaxConstants.seTaxDeductionRate

        // AGI and federal income tax
        let agi = netSEIncome - seTaxDeduction
        let deductionAmount = personalDeduction ?? StandardDeductions.amount(for: filingStatus)
        let taxableIncome = max(agi - deductionAmount, 0)
        let federalTax = calculateFederalTax(taxableIncome: taxableIncome, filingStatus: filingStatus)

        // State tax (simplified effective rates)
        let stateTax = calculateStateTax(taxableIncome: taxableIncome, stateCode: stateCode)

        // Tax credits reduce income tax (federal + state) dollar-for-dollar, but NOT self-employment tax.
        // Credits cannot reduce income tax below zero.
        let incomeTaxBeforeCredits = federalTax + stateTax
        let creditApplied = min(taxCredits, incomeTaxBeforeCredits)
        let adjustedFederalTax = incomeTaxBeforeCredits > 0
            ? federalTax - (creditApplied * federalTax / incomeTaxBeforeCredits)
            : 0
        let adjustedStateTax = incomeTaxBeforeCredits > 0
            ? stateTax - (creditApplied * stateTax / incomeTaxBeforeCredits)
            : 0
        let totalAnnualTax = totalSETax + adjustedFederalTax + adjustedStateTax
        // If the user has a W-2 job, their employer's withholding offsets their quarterly obligation.
        // They only need to pay estimated tax on the REMAINING amount after W-2 withholding.
        let remainingAfterW2 = max(totalAnnualTax - w2Withholding, 0)
        let quarterlyPayment = remainingAfterW2 / 4
        let effectiveRate = netSEIncome > 0 ? totalAnnualTax / netSEIncome : 0

        return TaxCalculationResult(
            grossIncome: grossIncome,
            totalDeductions: totalDeductions,
            netSelfEmploymentIncome: netSEIncome,
            selfEmploymentTax: totalSETax,
            federalIncomeTax: adjustedFederalTax,
            stateIncomeTax: adjustedStateTax,
            totalEstimatedTax: totalAnnualTax,
            quarterlyPaymentDue: quarterlyPayment,
            effectiveTaxRate: effectiveRate
        )
    }

    func calculateMileageDeduction(miles: Double) -> Double {
        miles * TaxConstants.mileageRate
    }

    func willReceive1099K(grossPayments: Double, transactionCount: Int = 0) -> Bool {
        // As of 2024+, only the gross amount threshold matters ($5K for 2024, likely lowering further)
        grossPayments >= TaxConstants.form1099KThreshold
    }

    // MARK: - Multi-State Support

    /// Represents a single state's share of a worker's total income.
    /// `incomeShare` is a value in the range 0.0–1.0.
    /// Shares are normalised internally so they never sum to more than 1.0.
    struct StateAllocation {
        let stateCode: String
        /// Fraction of total income earned in this state (e.g., 0.60 = 60%).
        let incomeShare: Double
    }

    /// The per-state breakdown returned alongside the combined total.
    struct MultiStateResult {
        struct StateDetail {
            let stateCode: String
            let incomeShare: Double
            let stateTax: Double
        }
        let details: [StateDetail]
        let totalStateTax: Double
    }

    /// Calculates estimated tax when income was earned across multiple states.
    /// Federal SE tax and income tax are computed once on the full income and remain
    /// unchanged — only state tax is apportioned by each state's income share.
    func calculateMultiStateEstimate(
        grossIncome: Double,
        totalDeductions: Double,
        filingStatus: FilingStatus,
        stateAllocations: [StateAllocation]
    ) -> (federal: TaxCalculationResult, state: MultiStateResult) {

        // Compute the full federal result using the first state for the
        // single-state call (state tax will be overridden below).
        let primaryState = stateAllocations.first?.stateCode ?? "TX"
        let federalResult = calculateEstimate(
            grossIncome: grossIncome,
            totalDeductions: totalDeductions,
            filingStatus: filingStatus,
            stateCode: primaryState
        )

        // Normalise shares so they can never sum to more than 1.0.
        let rawTotal = stateAllocations.reduce(0) { $0 + max($1.incomeShare, 0) }
        let normalisationFactor = rawTotal > 1.0 ? rawTotal : 1.0

        // Compute taxable income at the federal level (used as the base for state rates).
        let netSEIncome = max(grossIncome - totalDeductions, 0)
        let seTaxDeduction = federalResult.selfEmploymentTax * TaxConstants.seTaxDeductionRate
        let agi = netSEIncome - seTaxDeduction
        let standardDeduction = StandardDeductions.amount(for: filingStatus)
        let taxableIncomeBase = max(agi - standardDeduction, 0)

        var stateDetails: [MultiStateResult.StateDetail] = []
        var totalStateTax = 0.0

        for allocation in stateAllocations {
            let normalisedShare = max(allocation.incomeShare, 0) / normalisationFactor
            let taxableIncomeForState = taxableIncomeBase * normalisedShare
            let rate = stateEffectiveTaxRate(for: allocation.stateCode)
            let stateTax = taxableIncomeForState * rate

            stateDetails.append(MultiStateResult.StateDetail(
                stateCode: allocation.stateCode,
                incomeShare: normalisedShare,
                stateTax: stateTax
            ))
            totalStateTax += stateTax
        }

        return (federal: federalResult, state: MultiStateResult(details: stateDetails, totalStateTax: totalStateTax))
    }

    // MARK: - Private

    private func calculateFederalTax(taxableIncome: Double, filingStatus: FilingStatus) -> Double {
        let brackets: [(threshold: Double, rate: Double)]
        switch filingStatus {
        case .single:
            brackets = Self.federalBrackets2026Single
        case .marriedJoint:
            brackets = Self.federalBrackets2026MarriedJoint
        case .marriedSeparate:
            brackets = Self.federalBrackets2026MarriedSeparate
        case .headOfHousehold:
            brackets = Self.federalBrackets2026HeadOfHousehold
        }

        var tax: Double = 0
        for (index, bracket) in brackets.enumerated() {
            let nextThreshold = index + 1 < brackets.count ? brackets[index + 1].threshold : Double.greatestFiniteMagnitude
            let taxableInBracket = min(taxableIncome, nextThreshold) - bracket.threshold
            if taxableInBracket > 0 {
                tax += taxableInBracket * bracket.rate
            }
            if taxableIncome <= nextThreshold { break }
        }
        return tax
    }

    private func calculateStateTax(taxableIncome: Double, stateCode: String) -> Double {
        let rate = stateEffectiveTaxRate(for: stateCode)
        return taxableIncome * rate
    }

    /// Public access to state effective tax rate — use this instead of duplicating the lookup table.
    func stateEffectiveTaxRate(for stateCode: String) -> Double {
        // Simplified effective rates for common states
        let rates: [String: Double] = [
            "CA": 0.0725, "NY": 0.0685, "TX": 0.0, "FL": 0.0,
            "WA": 0.0, "IL": 0.0495, "PA": 0.0307, "OH": 0.04,
            "GA": 0.055, "NC": 0.0475, "NJ": 0.055, "VA": 0.0575,
            "MA": 0.05, "MD": 0.0575, "CO": 0.044, "MN": 0.0535,
            "OR": 0.09, "AZ": 0.025, "TN": 0.0, "NV": 0.0,
            "WY": 0.0, "SD": 0.0, "AK": 0.0, "NH": 0.0,
            "CT": 0.05, "SC": 0.065, "AL": 0.05, "LA": 0.0425,
            "KY": 0.04, "OK": 0.0475, "IA": 0.038, "MS": 0.05,
            "AR": 0.044, "KS": 0.057, "UT": 0.0465, "NE": 0.0584,
            "NM": 0.049, "WV": 0.055, "ID": 0.058, "HI": 0.0825,
            "ME": 0.0715, "MT": 0.059, "RI": 0.0599, "DE": 0.066,
            "ND": 0.019, "VT": 0.066, "DC": 0.065, "WI": 0.0627,
            "IN": 0.031, "MI": 0.0425, "MO": 0.048,
        ]
        return rates[stateCode] ?? 0.05
    }
}

struct TaxCalculationResult {
    let grossIncome: Double
    let totalDeductions: Double
    let netSelfEmploymentIncome: Double
    let selfEmploymentTax: Double
    let federalIncomeTax: Double
    let stateIncomeTax: Double
    let totalEstimatedTax: Double
    let quarterlyPaymentDue: Double
    let effectiveTaxRate: Double

    static let zero = TaxCalculationResult(
        grossIncome: 0, totalDeductions: 0, netSelfEmploymentIncome: 0,
        selfEmploymentTax: 0, federalIncomeTax: 0, stateIncomeTax: 0,
        totalEstimatedTax: 0, quarterlyPaymentDue: 0, effectiveTaxRate: 0
    )
}
