import SwiftUI
import SwiftData

/// Proactive deduction scanner — analyzes user's data and surfaces SPECIFIC deductions
/// they're missing with exact dollar amounts. This is the "Find My Deductions" premium feature.
///
/// Unlike TaxTipsEngine (which gives general advice), this scans actual data patterns:
/// - "You logged 847 miles but no gas expenses — add ~$212 in gas deductions"
/// - "You have no phone bill logged — 50% of $85/mo = $510/year deduction"
/// - "Your home office at 150 sq ft = $750 simplified deduction (not yet claimed)"
struct DeductionFinderView: View {
    @Query(sort: \IncomeEntry.entryDate) private var incomeEntries: [IncomeEntry]
    @Query(sort: \ExpenseEntry.expenseDate) private var expenseEntries: [ExpenseEntry]
    @Query private var mileageTrips: [MileageTrip]
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    private var yearExpenses: [ExpenseEntry] {
        expenseEntries.filter { $0.taxYear == DateHelper.currentTaxYear }
    }

    private var yearIncome: Double {
        incomeEntries.filter { $0.taxYear == DateHelper.currentTaxYear }.reduce(0) { $0 + $1.netAmount }
    }

    private var yearMileage: Double {
        mileageTrips.filter { $0.taxYear == DateHelper.currentTaxYear }.reduce(0) { $0 + $1.miles }
    }

    private var categoriesUsed: Set<String> {
        Set(yearExpenses.map { $0.category.rawValue })
    }

    struct MissingDeduction: Identifiable {
        let id = UUID()
        let icon: String
        let category: String
        let title: String
        let estimatedSavings: Double
        let explanation: String
        let actionLabel: String
        let priority: Int // 1 = highest
    }

    private var missingDeductions: [MissingDeduction] {
        var deductions: [MissingDeduction] = []
        let calendar = Calendar.current
        let monthsActive = max(calendar.component(.month, from: .now), 1)

        // 1. Gas/Fuel — only suggest if NOT using standard mileage rate
        // IRS Rule: If you claim the standard mileage rate ($0.70/mile), you CANNOT also
        // deduct actual gas expenses — they are mutually exclusive methods.
        let usesStandardMileageRate = yearMileage > 0
        if !usesStandardMileageRate && !categoriesUsed.contains(ExpenseCategory.gas.rawValue) && yearIncome > 1000 {
            deductions.append(MissingDeduction(
                icon: "fuelpump.fill",
                category: "Gas & Fuel",
                title: "No gas expenses logged",
                estimatedSavings: 500, // Conservative estimate
                explanation: "If you use the actual expense method (instead of the standard mileage rate), you can deduct gas costs. Track fill-ups for your gig driving.",
                actionLabel: "Add Gas Expense",
                priority: 2
            ))
        } else if usesStandardMileageRate && !categoriesUsed.contains(ExpenseCategory.gas.rawValue) {
            // Informational: let them know mileage rate already covers gas
            deductions.append(MissingDeduction(
                icon: "fuelpump.fill",
                category: "Gas & Fuel",
                title: "Gas is already covered by your mileage deduction",
                estimatedSavings: 0,
                explanation: "Since you use the standard mileage rate ($0.70/mile), gas costs are already included. You cannot deduct gas separately — the IRS considers it double-dipping.",
                actionLabel: "Already Covered",
                priority: 5
            ))
        }

        // 2. Phone bill — almost every gig worker should have this
        if yearIncome > 1000 && !categoriesUsed.contains(ExpenseCategory.phoneAndInternet.rawValue) {
            let phoneSavings = 85.0 * 0.5 * Double(monthsActive) // $85/mo × 50% business use
            deductions.append(MissingDeduction(
                icon: "iphone",
                category: "Phone & Internet",
                title: "No phone bill logged",
                estimatedSavings: phoneSavings,
                explanation: "You need your phone for every gig app. 50% of your bill (~$42/mo) is deductible. That's \(CurrencyFormatter.format(phoneSavings)) so far this year.",
                actionLabel: "Add Phone Bill",
                priority: 1
            ))
        }

        // 3. Home office — if they set square footage
        let sqFt = profile?.homeOfficeSquareFeet ?? 0
        if sqFt > 0 && !categoriesUsed.contains(ExpenseCategory.homeOffice.rawValue) {
            let simplified = min(sqFt, 300) * 5
            deductions.append(MissingDeduction(
                icon: "house.fill",
                category: "Home Office",
                title: "Unclaimed home office deduction",
                estimatedSavings: simplified,
                explanation: "Your \(String(Int(sqFt))) sq ft office qualifies for a \(CurrencyFormatter.format(simplified)) simplified deduction ($5/sq ft). No receipts needed.",
                actionLabel: "Claim Deduction",
                priority: 2
            ))
        } else if sqFt == 0 && yearIncome > 5000 {
            deductions.append(MissingDeduction(
                icon: "house.fill",
                category: "Home Office",
                title: "Do you have a home office?",
                estimatedSavings: 750, // Assume 150 sq ft average
                explanation: "If you use any part of your home exclusively for gig work (even a desk), you can deduct $5/sq ft up to $1,500. Set your square footage in Settings.",
                actionLabel: "Set Up in Settings",
                priority: 3
            ))
        }

        // 4. Car insurance — only if NOT using standard mileage rate
        // IRS Rule: Standard mileage rate includes insurance costs. Cannot deduct separately.
        let isDrivingGig = incomeEntries.contains { [.uber, .lyft, .doordash, .grubhub, .ubereats, .instacart, .amazonFlex, .shipt].contains($0.platform) }
        if isDrivingGig && !usesStandardMileageRate && !categoriesUsed.contains(ExpenseCategory.insurance.rawValue) {
            let insuranceSavings = 150.0 * 0.5 * Double(monthsActive) // $150/mo × 50%
            deductions.append(MissingDeduction(
                icon: "shield.checkered",
                category: "Car Insurance",
                title: "No car insurance logged",
                estimatedSavings: insuranceSavings,
                explanation: "Using the actual expense method, 50% of your auto insurance premium (~$75/mo) is deductible as a business expense.",
                actionLabel: "Add Insurance",
                priority: 2
            ))
        }

        // 5. Vehicle maintenance — only if NOT using standard mileage rate
        // IRS Rule: Standard mileage rate includes maintenance costs. Cannot deduct separately.
        if yearMileage > 3000 && !usesStandardMileageRate && !categoriesUsed.contains(ExpenseCategory.vehicleMaintenance.rawValue) {
            let maintenanceSavings = yearMileage * 0.05 // ~$0.05/mile maintenance avg
            deductions.append(MissingDeduction(
                icon: "wrench.and.screwdriver.fill",
                category: "Vehicle Maintenance",
                title: "No maintenance expenses logged",
                estimatedSavings: maintenanceSavings,
                explanation: "Using the actual expense method, oil changes, tires, and repairs are deductible. With \(String(Int(yearMileage))) miles, that's roughly \(CurrencyFormatter.format(maintenanceSavings)).",
                actionLabel: "Add Maintenance",
                priority: 2
            ))
        }

        // 6. Parking & Tolls — if delivery/rideshare but no parking
        if isDrivingGig && !categoriesUsed.contains(ExpenseCategory.parking.rawValue) && monthsActive >= 2 {
            let parkingSavings = 25.0 * Double(monthsActive) // $25/mo avg parking
            deductions.append(MissingDeduction(
                icon: "parkingsign",
                category: "Parking & Tolls",
                title: "No parking or toll expenses",
                estimatedSavings: parkingSavings,
                explanation: "Parking meters, garage fees, and tolls while working are 100% deductible. Even $25/month adds up to \(CurrencyFormatter.format(parkingSavings))/year.",
                actionLabel: "Add Parking/Tolls",
                priority: 3
            ))
        }

        // 7. Software & Apps — gig workers use tracking, navigation, and business apps
        if yearIncome > 3000 && !categoriesUsed.contains(ExpenseCategory.software.rawValue) {
            deductions.append(MissingDeduction(
                icon: "app.fill",
                category: "Software & Apps",
                title: "No app/software expenses",
                estimatedSavings: 300,
                explanation: "Navigation apps, mileage trackers, accounting software, and even GigWallet Pro are 100% deductible business expenses.",
                actionLabel: "Add Software",
                priority: 3
            ))
        }

        // 8. Health Insurance — self-employed premium deduction
        if yearIncome > 10000 && !categoriesUsed.contains(ExpenseCategory.healthInsurance.rawValue) {
            deductions.append(MissingDeduction(
                icon: "heart.fill",
                category: "Health Insurance",
                title: "Self-employed health insurance",
                estimatedSavings: 4800, // Avg $400/mo
                explanation: "Self-employed workers can deduct 100% of health insurance premiums — not just as an itemized deduction, but as an above-the-line deduction. Average savings: $4,800/year.",
                actionLabel: "Add Premiums",
                priority: 1
            ))
        }

        return deductions.sorted { $0.priority < $1.priority }
    }

    private var totalPotentialSavings: Double {
        missingDeductions.reduce(0) { $0 + $1.estimatedSavings }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Hero — total potential savings
                if totalPotentialSavings > 100 {
                    VStack(spacing: Spacing.md) {
                        Text("Potential Deductions Found")
                            .font(Typography.headline)
                            .foregroundStyle(.white)

                        Text(CurrencyFormatter.format(totalPotentialSavings))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("in deductions you may be missing")
                            .font(Typography.subheadline)
                            .foregroundStyle(.white.opacity(0.8))

                        let taxSavings = totalPotentialSavings * 0.27
                        Text("≈ \(CurrencyFormatter.format(taxSavings)) in tax savings")
                            .font(Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.xxl)
                    .background(
                        LinearGradient(
                            colors: [BrandColors.primary, BrandColors.primaryDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusXl))
                }

                // Deduction list
                if missingDeductions.isEmpty {
                    VStack(spacing: Spacing.lg) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(BrandColors.success)

                        Text("Great job!")
                            .font(Typography.title)

                        Text("You're tracking deductions across all common categories. Keep logging expenses as they happen.")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Spacing.xxl)
                } else {
                    ForEach(missingDeductions) { deduction in
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(BrandColors.warning.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: deduction.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(BrandColors.warning)
                            }

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(deduction.title)
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(BrandColors.textPrimary)

                                Text(deduction.explanation)
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textSecondary)
                                    .lineSpacing(2)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyFormatter.format(deduction.estimatedSavings))
                                    .font(Typography.moneyCaption)
                                    .foregroundStyle(BrandColors.warning)
                                Text("potential")
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                        }
                        .gwCard()
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BrandColors.groupedBackground)
        .gwNavigationTitle("Find ", accent: "Deductions", icon: "sparkle.magnifyingglass")
    }
}
