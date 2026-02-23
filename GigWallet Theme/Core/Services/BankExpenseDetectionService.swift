import Foundation
import SwiftData

/// Automatic bank expense detection service — fetches non-gig transactions from the
/// backend and auto-categorizes them as potential business expense deductions.
///
/// **How it works:**
/// 1. Fetches expense candidate transactions from the backend (charges/debits that
///    aren't matched as gig income)
/// 2. Runs each through `ExpenseCategorizationEngine.categorize()` for on-device
///    keyword + NLEmbedding categorization
/// 3. Auto-imports high-confidence matches (≥60%) as `ExpenseEntry` records
/// 4. Skips duplicates by checking existing expenses (same vendor + date + amount)
/// 5. Only imports deductible categories — skips "Other" to avoid noise
///
/// **Usage:**
/// Called automatically by `PlaidAutoSyncService` after income sync completes:
/// ```
/// await BankExpenseDetectionService.shared.detectAndImportExpenses(context: modelContext)
/// ```
@MainActor
@Observable
final class BankExpenseDetectionService: @unchecked Sendable {
    static let shared = BankExpenseDetectionService()

    /// Whether detection is currently in progress
    var isDetecting: Bool = false

    /// Last detection result summary
    var lastDetectionResult: DetectionResult?

    /// Last successful detection date
    var lastDetectionDate: Date? {
        get { UserDefaults.standard.object(forKey: "bankExpense.lastDetectionDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "bankExpense.lastDetectionDate") }
    }

    /// Minimum confidence to auto-import as an expense (60%)
    private let importConfidenceThreshold: Double = 0.60

    /// Maximum transactions to fetch per detection run
    private let fetchLimit: Int = 200

    struct DetectionResult {
        let importedCount: Int
        let candidatesAnalyzed: Int
        let categoriesFound: [String: Int]
        let totalDeductibleAmount: Double
        let detectedAt: Date
    }

    private init() {}

    // MARK: - Detect and Import

    /// Fetches bank expense candidates from the backend and auto-imports deductible
    /// expenses into SwiftData. Safe to call from PlaidAutoSyncService after income sync.
    func detectAndImportExpenses(context: ModelContext) async {
        guard !isDetecting else { return }

        isDetecting = true
        defer { isDetecting = false }

        do {
            // Ensure we have a backend auth token
            try await APIClient.shared.ensureAuthenticated()

            // Determine date range — sync from start of current tax year
            let currentYear = Calendar.current.component(.year, from: .now)
            let fromDate = "\(currentYear)-01-01"
            let toDate = ISO8601DateFormatter().string(from: .now).prefix(10)

            // Step 1: Fetch expense candidate transactions from the backend
            let response: ExpenseCandidatesResponse = try await APIClient.shared.request(
                .expenseCandidates(from: fromDate, to: String(toDate), limit: fetchLimit)
            )

            guard !response.transactions.isEmpty else {
                // No expense candidates — nothing to process
                lastDetectionResult = DetectionResult(
                    importedCount: 0,
                    candidatesAnalyzed: 0,
                    categoriesFound: [:],
                    totalDeductibleAmount: 0,
                    detectedAt: .now
                )
                lastDetectionDate = .now
                return
            }

            // Step 2: Fetch existing expenses to check for duplicates
            let existingExpenses = fetchExistingExpenses(context: context)

            // Step 3: Categorize each transaction and import high-confidence matches
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            var importedCount = 0
            var categoriesFound: [String: Int] = [:]
            var totalDeductibleAmount: Double = 0

            for tx in response.transactions {
                let description = tx.name ?? ""
                let merchant = tx.merchantName

                // Run through the on-device categorization engine
                let prediction = ExpenseCategorizationEngine.categorize(
                    description: description,
                    merchantName: merchant,
                    amount: tx.amount
                )

                // Only import if:
                // 1. Confidence meets threshold (≥60%)
                // 2. Category is NOT "Other" (too vague to auto-import)
                // 3. Expense is deductible
                guard prediction.confidence >= importConfidenceThreshold,
                      prediction.category != ExpenseCategory.other.rawValue,
                      prediction.isDeductible else {
                    continue
                }

                // Parse the transaction date
                let expenseDate = dateFormatter.date(from: tx.date) ?? .now

                // Duplicate check: same vendor + same date + same amount (within $0.01)
                let vendorName = merchant ?? description
                let isDuplicate = existingExpenses.contains { existing in
                    existing.vendor.lowercased() == vendorName.lowercased() &&
                    Calendar.current.isDate(existing.expenseDate, inSameDayAs: expenseDate) &&
                    abs(existing.amount - tx.amount) < 0.01
                }

                guard !isDuplicate else { continue }

                // Map the predicted category string to ExpenseCategory enum
                let category = ExpenseCategory.allCases.first { $0.rawValue == prediction.category } ?? .other

                // Skip if it mapped back to .other (shouldn't happen but be safe)
                guard category != .other else { continue }

                // Create the expense entry
                let expense = ExpenseEntry(
                    amount: tx.amount,
                    category: category,
                    vendor: vendorName,
                    description: "Bank sync: \(prediction.reasoning)",
                    expenseDate: expenseDate,
                    isDeductible: prediction.isDeductible,
                    deductionPercentage: prediction.deductionPercentage * 100
                )
                context.insert(expense)

                importedCount += 1
                totalDeductibleAmount += expense.deductibleAmount
                categoriesFound[category.rawValue, default: 0] += 1
            }

            // Step 4: Record detection result
            lastDetectionDate = .now
            lastDetectionResult = DetectionResult(
                importedCount: importedCount,
                candidatesAnalyzed: response.transactions.count,
                categoriesFound: categoriesFound,
                totalDeductibleAmount: totalDeductibleAmount,
                detectedAt: .now
            )

        } catch {
            // Detection failed silently — don't crash the app for background processing.
            // User can always manually add expenses.
        }
    }

    // MARK: - Helpers

    /// Fetches all existing ExpenseEntry records for duplicate detection.
    private func fetchExistingExpenses(context: ModelContext) -> [ExpenseEntry] {
        let descriptor = FetchDescriptor<ExpenseEntry>()
        return (try? context.fetch(descriptor)) ?? []
    }
}
