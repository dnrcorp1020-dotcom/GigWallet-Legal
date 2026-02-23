import Foundation
import SwiftData

/// Automatic deduction analysis service — proactively identifies missing tax deductions
/// so the user doesn't need to manually open DeductionFinderView.
///
/// **How it works:**
/// 1. Runs automatically when the dashboard loads (via DashboardView `.task`)
/// 2. Analyzes current income, expenses, and mileage to find missing deduction categories
/// 3. Exposes `missedDeductions` and `totalPotentialSavings` for dashboard display
/// 4. Throttled to refresh once per hour (deduction opportunities don't change rapidly)
///
/// This mirrors the logic in `DeductionFinderView` but decoupled from the view layer
/// so it can run proactively in the background.
@MainActor
@Observable
final class SmartDeductionService: @unchecked Sendable {
    static let shared = SmartDeductionService()

    /// Missing deductions identified during the last analysis
    var missedDeductions: [MissedDeduction] = []

    /// Total potential savings across all missed deductions
    var totalPotentialSavings: Double = 0

    /// Number of missing deduction categories found
    var missedCategoryCount: Int { missedDeductions.count }

    /// Whether an analysis has been performed this session
    var hasAnalyzed: Bool = false

    /// Last analysis timestamp
    private var lastAnalysisDate: Date?

    /// Minimum interval between analyses (1 hour)
    private let analysisInterval: TimeInterval = 60 * 60

    struct MissedDeduction: Identifiable {
        let id = UUID()
        let icon: String
        let category: String
        let title: String
        let estimatedSavings: Double
        let priority: Int // 1 = highest
    }

    private init() {}

    // MARK: - Auto Analysis

    /// Analyzes deductions if enough time has passed since last analysis.
    /// Safe to call from DashboardView `.task` on every appearance.
    func analyzeIfNeeded(context: ModelContext, profile: UserProfile?) {
        // Throttle: don't re-analyze more frequently than the interval
        if let lastAnalysis = lastAnalysisDate, Date.now.timeIntervalSince(lastAnalysis) < analysisInterval {
            return
        }

        performAnalysis(context: context, profile: profile)
    }

    /// Forces a fresh analysis regardless of throttle.
    func forceAnalyze(context: ModelContext, profile: UserProfile?) {
        performAnalysis(context: context, profile: profile)
    }

    // MARK: - Core Analysis

    private func performAnalysis(context: ModelContext, profile: UserProfile?) {
        let calendar = Calendar.current
        let currentTaxYear = DateHelper.currentTaxYear
        let monthsActive = max(calendar.component(.month, from: .now), 1)

        // Fetch data
        let incomeDescriptor = FetchDescriptor<IncomeEntry>()
        let expenseDescriptor = FetchDescriptor<ExpenseEntry>()
        let mileageDescriptor = FetchDescriptor<MileageTrip>()

        let allIncome = (try? context.fetch(incomeDescriptor)) ?? []
        let allExpenses = (try? context.fetch(expenseDescriptor)) ?? []
        let allMileage = (try? context.fetch(mileageDescriptor)) ?? []

        let yearIncome = allIncome.filter { $0.taxYear == currentTaxYear }.reduce(0) { $0 + $1.netAmount }
        let yearExpenses = allExpenses.filter { $0.taxYear == currentTaxYear }
        let yearMileage = allMileage.filter { $0.taxYear == currentTaxYear }.reduce(0) { $0 + $1.miles }

        let categoriesUsed = Set(yearExpenses.map { $0.category.rawValue })
        let usesStandardMileageRate = yearMileage > 0

        let isDrivingGig = allIncome.contains {
            [.uber, .lyft, .doordash, .grubhub, .ubereats, .instacart, .amazonFlex, .shipt].contains($0.platform)
        }

        var deductions: [MissedDeduction] = []

        // 1. Phone bill — almost every gig worker should have this
        if yearIncome > 1000 && !categoriesUsed.contains(ExpenseCategory.phoneAndInternet.rawValue) {
            let phoneSavings = 85.0 * 0.5 * Double(monthsActive)
            deductions.append(MissedDeduction(
                icon: "iphone",
                category: "Phone & Internet",
                title: "No phone bill logged",
                estimatedSavings: phoneSavings,
                priority: 1
            ))
        }

        // 2. Health Insurance — self-employed premium deduction
        if yearIncome > 10000 && !categoriesUsed.contains(ExpenseCategory.healthInsurance.rawValue) {
            deductions.append(MissedDeduction(
                icon: "heart.fill",
                category: "Health Insurance",
                title: "Self-employed health insurance",
                estimatedSavings: 4800,
                priority: 1
            ))
        }

        // 3. Gas/Fuel — only if NOT using standard mileage rate
        if !usesStandardMileageRate && !categoriesUsed.contains(ExpenseCategory.gas.rawValue) && yearIncome > 1000 {
            deductions.append(MissedDeduction(
                icon: "fuelpump.fill",
                category: "Gas & Fuel",
                title: "No gas expenses logged",
                estimatedSavings: 500,
                priority: 2
            ))
        }

        // 4. Home office
        let sqFt = profile?.homeOfficeSquareFeet ?? 0
        if sqFt > 0 && !categoriesUsed.contains(ExpenseCategory.homeOffice.rawValue) {
            let simplified = min(sqFt, 300) * 5
            deductions.append(MissedDeduction(
                icon: "house.fill",
                category: "Home Office",
                title: "Unclaimed home office deduction",
                estimatedSavings: simplified,
                priority: 2
            ))
        } else if sqFt == 0 && yearIncome > 5000 {
            deductions.append(MissedDeduction(
                icon: "house.fill",
                category: "Home Office",
                title: "Do you have a home office?",
                estimatedSavings: 750,
                priority: 3
            ))
        }

        // 5. Car insurance — only if NOT using standard mileage rate
        if isDrivingGig && !usesStandardMileageRate && !categoriesUsed.contains(ExpenseCategory.insurance.rawValue) {
            let insuranceSavings = 150.0 * 0.5 * Double(monthsActive)
            deductions.append(MissedDeduction(
                icon: "shield.checkered",
                category: "Car Insurance",
                title: "No car insurance logged",
                estimatedSavings: insuranceSavings,
                priority: 2
            ))
        }

        // 6. Vehicle maintenance — only if NOT using standard mileage rate
        if yearMileage > 3000 && !usesStandardMileageRate && !categoriesUsed.contains(ExpenseCategory.vehicleMaintenance.rawValue) {
            let maintenanceSavings = yearMileage * 0.05
            deductions.append(MissedDeduction(
                icon: "wrench.and.screwdriver.fill",
                category: "Vehicle Maintenance",
                title: "No maintenance expenses logged",
                estimatedSavings: maintenanceSavings,
                priority: 2
            ))
        }

        // 7. Parking & Tolls
        if isDrivingGig && !categoriesUsed.contains(ExpenseCategory.parking.rawValue) && monthsActive >= 2 {
            let parkingSavings = 25.0 * Double(monthsActive)
            deductions.append(MissedDeduction(
                icon: "parkingsign",
                category: "Parking & Tolls",
                title: "No parking or toll expenses",
                estimatedSavings: parkingSavings,
                priority: 3
            ))
        }

        // 8. Software & Apps
        if yearIncome > 3000 && !categoriesUsed.contains(ExpenseCategory.software.rawValue) {
            deductions.append(MissedDeduction(
                icon: "app.fill",
                category: "Software & Apps",
                title: "No app/software expenses",
                estimatedSavings: 300,
                priority: 3
            ))
        }

        // Sort by priority and update state
        missedDeductions = deductions.sorted { $0.priority < $1.priority }
        totalPotentialSavings = deductions.reduce(0) { $0 + $1.estimatedSavings }
        hasAnalyzed = true
        lastAnalysisDate = .now
    }
}
