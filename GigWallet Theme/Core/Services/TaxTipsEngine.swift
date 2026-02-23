import Foundation

/// Generates personalized tax savings tips based on user's actual data
/// This is a core "Rolls Royce" feature that makes the app feel like a financial advisor
struct TaxTipsEngine {

    struct TaxTip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let potentialSavings: Double?
        let priority: Priority
        let category: Category

        enum Priority: Int, Comparable {
            case critical = 0 // Large money at stake
            case high = 1     // Significant savings
            case medium = 2   // Moderate value
            case low = 3      // Nice to know

            static func < (lhs: Priority, rhs: Priority) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        enum Category: String {
            case mileage = "Mileage"
            case expenses = "Expenses"
            case income = "Income"
            case taxPlanning = "Tax Planning"
            case retirement = "Retirement"
            case health = "Health"
        }
    }

    /// Analyze user data and generate personalized tips sorted by potential savings
    static func generateTips(
        yearlyIncome: Double,
        yearlyDeductions: Double,
        mileageLogged: Double,
        expenseCategories: Set<String>,
        hasHealthInsurance: Bool,
        filingStatus: FilingStatus,
        stateCode: String,
        monthsActive: Int
    ) -> [TaxTip] {
        var tips: [TaxTip] = []

        let monthsInYear = max(monthsActive, 1)
        let projectedAnnualIncome = yearlyIncome * (12.0 / Double(monthsInYear))

        // 1. Mileage gap analysis
        let avgGigMilesPerMonth: Double = 1200 // Average gig driver: ~14,400 miles/year
        let expectedMileage = avgGigMilesPerMonth * Double(monthsActive)
        let mileageGap = expectedMileage - mileageLogged

        if mileageGap > 500 {
            let missedDeduction = mileageGap * TaxEngine.TaxConstants.mileageRate
            tips.append(TaxTip(
                icon: "car.fill",
                title: "You may be under-tracking mileage",
                detail: "You've logged \(Int(mileageLogged)) miles, but similar gig workers average \(Int(expectedMileage)) miles in \(monthsActive) months. That's ~\(CurrencyFormatter.format(missedDeduction)) in missed deductions.",
                potentialSavings: missedDeduction,
                priority: missedDeduction > 1000 ? .critical : .high,
                category: .mileage
            ))
        }

        // 2. Phone bill deduction
        if !expenseCategories.contains("Phone & Internet") && yearlyIncome > 5000 {
            let monthlyPhoneCost = 85.0 // Average phone bill
            let annualDeduction = monthlyPhoneCost * 0.50 * 12 // 50% business use
            tips.append(TaxTip(
                icon: "iphone",
                title: "Deduct your phone bill",
                detail: "50% of your phone bill is deductible as a gig worker. At ~$85/month, that's \(CurrencyFormatter.format(annualDeduction))/year in deductions.",
                potentialSavings: annualDeduction,
                priority: .high,
                category: .expenses
            ))
        }

        // 3. Health insurance deduction
        if !expenseCategories.contains("Health Insurance") && yearlyIncome > 10000 {
            tips.append(TaxTip(
                icon: "heart.fill",
                title: "Self-employed health insurance is fully deductible",
                detail: "If you pay for your own health insurance, the full premium is deductible (not just an itemized deduction). This could save you $3,000-$8,000/year.",
                potentialSavings: 4000,
                priority: .critical,
                category: .health
            ))
        }

        // 4. Home office deduction
        if !expenseCategories.contains("Home Office") && yearlyIncome > 10000 {
            tips.append(TaxTip(
                icon: "house.fill",
                title: "Consider the home office deduction",
                detail: "If you use a dedicated space at home for your gig business (managing deliveries, bookkeeping), you can deduct $5/sq ft up to 300 sq ft ($1,500/year).",
                potentialSavings: 1500,
                priority: .medium,
                category: .expenses
            ))
        }

        // 5. Vehicle maintenance + insurance
        if !expenseCategories.contains("Vehicle Maintenance") && mileageLogged > 1000 {
            tips.append(TaxTip(
                icon: "wrench.fill",
                title: "Track vehicle maintenance costs",
                detail: "Oil changes, tire rotations, car washes, and repairs are deductible at your business-use percentage. Don't forget to log these!",
                potentialSavings: 800,
                priority: .medium,
                category: .expenses
            ))
        }

        // 6. Retirement savings
        if projectedAnnualIncome > 30000 {
            let maxSEP = min(projectedAnnualIncome * 0.25, 70000)
            let taxSavings = maxSEP * 0.25 // Rough estimate of tax savings
            tips.append(TaxTip(
                icon: "banknote.fill",
                title: "Save on taxes with a SEP IRA",
                detail: "You could contribute up to \(CurrencyFormatter.format(maxSEP)) to a SEP IRA, potentially saving \(CurrencyFormatter.format(taxSavings)) in taxes while building retirement savings.",
                potentialSavings: taxSavings,
                priority: .high,
                category: .retirement
            ))
        }

        // 7. Quarterly payment reminder
        let engine = TaxEngine()
        let estimate = engine.calculateEstimate(
            grossIncome: projectedAnnualIncome,
            totalDeductions: yearlyDeductions * (12.0 / Double(monthsInYear)),
            filingStatus: filingStatus,
            stateCode: stateCode
        )
        let weeklySetAside = estimate.quarterlyPaymentDue / 13 // ~13 weeks per quarter

        if weeklySetAside > 0 {
            tips.append(TaxTip(
                icon: "dollarsign.arrow.circlepath",
                title: "Set aside \(CurrencyFormatter.format(weeklySetAside))/week for taxes",
                detail: "Based on your projected income of \(CurrencyFormatter.format(projectedAnnualIncome)), you should set aside about \(CurrencyFormatter.format(weeklySetAside)) per week to cover quarterly estimated taxes.",
                potentialSavings: nil, // Not a savings, but important advice
                priority: .high,
                category: .taxPlanning
            ))
        }

        // 8. Software & subscriptions
        if !expenseCategories.contains("Software & Apps") && yearlyIncome > 3000 {
            tips.append(TaxTip(
                icon: "app.fill",
                title: "Deduct your gig app subscriptions",
                detail: "Gig tracking apps, GigWallet Pro, music streaming (if you drive), and navigation apps are all deductible business expenses.",
                potentialSavings: 300,
                priority: .low,
                category: .expenses
            ))
        }

        // 9. 1099-K awareness
        if projectedAnnualIncome >= TaxEngine.TaxConstants.form1099KThreshold * 0.8 {
            tips.append(TaxTip(
                icon: "doc.text.fill",
                title: "You'll likely receive a 1099-K",
                detail: "The IRS reporting threshold is \(CurrencyFormatter.format(TaxEngine.TaxConstants.form1099KThreshold)). Make sure all income is properly tracked to avoid discrepancies when you file.",
                potentialSavings: nil,
                priority: .medium,
                category: .income
            ))
        }

        // 10. Deduction rate check
        let deductionRate = yearlyIncome > 0 ? yearlyDeductions / yearlyIncome : 0
        if deductionRate < 0.10 && yearlyIncome > 5000 {
            let targetDeductions = yearlyIncome * 0.18
            let gap = targetDeductions - yearlyDeductions
            tips.append(TaxTip(
                icon: "exclamationmark.triangle.fill",
                title: "Your deductions seem low",
                detail: "You're deducting only \(CurrencyFormatter.formatPercent(deductionRate)) of income. Similar gig workers deduct 15-25%. You may be missing ~\(CurrencyFormatter.format(gap)) in deductions.",
                potentialSavings: gap * 0.25, // Rough tax savings on missed deductions
                priority: .critical,
                category: .taxPlanning
            ))
        }

        // Sort by priority, then by savings amount
        return tips.sorted { tip1, tip2 in
            if tip1.priority != tip2.priority {
                return tip1.priority < tip2.priority
            }
            return (tip1.potentialSavings ?? 0) > (tip2.potentialSavings ?? 0)
        }
    }
}
