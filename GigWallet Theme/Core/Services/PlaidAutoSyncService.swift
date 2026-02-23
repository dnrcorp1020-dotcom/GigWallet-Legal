import Foundation
import SwiftData

/// Automatic Plaid transaction sync service — fetches and imports new gig income
/// and business expenses from linked bank accounts without requiring manual user intervention.
///
/// **How it works:**
/// 1. On app launch, checks backend for linked Plaid items
/// 2. For each active item, triggers a cursor-based transaction sync
/// 3. Auto-imports gig income matches at ≥70% confidence
/// 4. Auto-detects and imports deductible expenses via BankExpenseDetectionService
/// 5. Skips duplicates by checking existing records
/// 6. Throttles to once per 4 hours to avoid hammering the backend
///
/// **Usage:**
/// Called from `MainTabView.task` on every app launch:
/// ```
/// await PlaidAutoSyncService.shared.syncIfNeeded(context: modelContext)
/// ```
@MainActor
@Observable
final class PlaidAutoSyncService: @unchecked Sendable {
    static let shared = PlaidAutoSyncService()

    /// Whether a sync is currently in progress
    var isSyncing: Bool = false

    /// Last sync result summary (for dashboard display)
    var lastSyncResult: SyncResult?

    /// Last successful sync date
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "plaid.lastSyncDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "plaid.lastSyncDate") }
    }

    /// Minimum interval between auto-syncs (4 hours)
    private let syncInterval: TimeInterval = 4 * 60 * 60

    struct SyncResult {
        let importedCount: Int
        let totalMatches: Int
        let platforms: [String]
        let expensesImported: Int
        let expensesAnalyzed: Int
        let syncedAt: Date
    }

    private init() {}

    // MARK: - Auto Sync

    /// Syncs bank transactions if enough time has passed since the last sync.
    /// Safe to call on every app launch — will no-op if synced recently.
    func syncIfNeeded(context: ModelContext) async {
        // Throttle: don't sync more than once per interval
        if let lastSync = lastSyncDate, Date.now.timeIntervalSince(lastSync) < syncInterval {
            return
        }

        await performSync(context: context)
    }

    /// Forces a sync regardless of the throttle interval.
    /// Use for manual "pull to refresh" or "Sync Now" button.
    func forceSync(context: ModelContext) async {
        await performSync(context: context)
    }

    // MARK: - Core Sync Logic

    private func performSync(context: ModelContext) async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Ensure we have a backend auth token
            try await APIClient.shared.ensureAuthenticated()

            // Step 1: Get all linked Plaid items from backend
            let itemsResponse: PlaidItemsResponse = try await APIClient.shared.request(.plaidItems)
            // Accept any non-error status — backend may use "active", "good", or just have items
            let errorStatuses: Set<String> = ["error", "disconnected", "revoked", "suspended"]
            let activeItems = itemsResponse.items.filter { !errorStatuses.contains($0.status.lowercased()) }

            guard !activeItems.isEmpty else {
                // No linked bank accounts — nothing to sync
                return
            }

            // Step 2: Sync transactions for each linked item
            var allMatches: [TransactionMatch] = []
            var allPlatforms: Set<String> = []

            for item in activeItems {
                do {
                    let syncResponse: SyncTransactionsResponse = try await APIClient.shared.request(
                        .syncTransactions(plaidItemId: item.id)
                    )
                    allMatches.append(contentsOf: syncResponse.matches)
                    for summary in syncResponse.platformSummary {
                        allPlatforms.insert(summary.platform)
                    }
                } catch {
                    // Individual item sync failure shouldn't stop others
                    continue
                }
            }

            // Step 3: Auto-import high-confidence gig income matches (≥70%)
            let importedCount = autoImportTransactions(matches: allMatches, context: context)

            // Step 4: Auto-detect and import business expenses from bank charges
            await BankExpenseDetectionService.shared.detectAndImportExpenses(context: context)
            let expenseResult = BankExpenseDetectionService.shared.lastDetectionResult

            // Step 5: Record sync result
            lastSyncDate = .now
            lastSyncResult = SyncResult(
                importedCount: importedCount,
                totalMatches: allMatches.count,
                platforms: Array(allPlatforms),
                expensesImported: expenseResult?.importedCount ?? 0,
                expensesAnalyzed: expenseResult?.candidatesAnalyzed ?? 0,
                syncedAt: .now
            )

        } catch {
            // Sync failed silently — don't crash the app or show alerts for background sync.
            // User can always manually sync from BankConnectionView.
        }
    }

    // MARK: - Auto Import

    /// Imports high-confidence transaction matches as IncomeEntry records.
    /// Returns the number of entries imported (excluding duplicates and low-confidence).
    private func autoImportTransactions(matches: [TransactionMatch], context: ModelContext) -> Int {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Fetch existing entries to check for duplicates
        let descriptor = FetchDescriptor<IncomeEntry>()
        let existingEntries = (try? context.fetch(descriptor)) ?? []

        var importedCount = 0

        for match in matches {
            // Only auto-import high-confidence matches (≥70%)
            guard match.confidence >= 0.7 else { continue }

            let platform = GigPlatformType.allCases.first { $0.rawValue == match.platform } ?? .other
            let entryDate = dateFormatter.date(from: match.date) ?? .now

            // Duplicate check: same platform + same date + same amount
            let isDuplicate = existingEntries.contains { existing in
                existing.platform == platform &&
                Calendar.current.isDate(existing.entryDate, inSameDayAs: entryDate) &&
                abs(existing.grossAmount - match.amount) < 0.01
            }

            guard !isDuplicate else { continue }

            let entry = IncomeEntry(
                amount: match.amount,
                platform: platform,
                entryMethod: .bankSync,
                entryDate: entryDate,
                notes: "Auto-synced: \(match.merchantName ?? match.name ?? match.platform)"
            )
            context.insert(entry)
            importedCount += 1
        }

        return importedCount
    }
}
