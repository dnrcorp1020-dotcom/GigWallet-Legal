import SwiftUI

/// Manages per-section card ordering with UserDefaults persistence.
/// Users can drag-to-reorder cards within each dashboard section.
/// Handles migration, progressive disclosure by experience level, and "Show All" override.
@MainActor
@Observable
final class DashboardCardOrderManager: @unchecked Sendable {
    static let shared = DashboardCardOrderManager()

    /// Current experience level — controls which cards are visible
    var experienceLevel: DashboardExperienceLevel {
        didSet {
            UserDefaults.standard.set(experienceLevel.rawValue, forKey: "dashboard_experience_level")
        }
    }

    /// Power user override — show all cards regardless of experience level
    var showAllCards: Bool {
        didSet {
            UserDefaults.standard.set(showAllCards, forKey: "dashboard_show_all_cards")
        }
    }

    init() {
        let savedLevel = UserDefaults.standard.integer(forKey: "dashboard_experience_level")
        experienceLevel = DashboardExperienceLevel(rawValue: savedLevel) ?? .newcomer
        showAllCards = UserDefaults.standard.bool(forKey: "dashboard_show_all_cards")
    }

    // MARK: - Storage Keys

    private func storageKey(for section: DashboardSection) -> String {
        "dashboard_card_order_\(section.rawValue)"
    }

    // MARK: - Public API

    /// Returns the user's custom card order for a section, filtered by experience level.
    func orderedCards(for section: DashboardSection) -> [DashboardCardID] {
        let allCards: [DashboardCardID]
        if let savedIDs = loadOrder(for: section) {
            allCards = migrate(savedIDs: savedIDs, section: section)
        } else {
            allCards = DashboardCardID.defaultOrder(for: section)
        }

        // Show all cards if override is enabled
        guard !showAllCards else { return allCards }

        // Filter by experience level
        return allCards.filter { $0.minimumLevel <= experienceLevel }
    }

    /// Returns ALL cards for a section (ignoring experience level) — used by CardReorderSheet.
    func allCards(for section: DashboardSection) -> [DashboardCardID] {
        if let savedIDs = loadOrder(for: section) {
            return migrate(savedIDs: savedIDs, section: section)
        }
        return DashboardCardID.defaultOrder(for: section)
    }

    /// Saves a new card order for a section.
    func updateOrder(for section: DashboardSection, cards: [DashboardCardID]) {
        let rawValues = cards.map { $0.rawValue }
        if let data = try? JSONEncoder().encode(rawValues) {
            UserDefaults.standard.set(data, forKey: storageKey(for: section))
        }
    }

    /// Resets a single section to default order.
    func resetOrder(for section: DashboardSection) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: section))
    }

    /// Resets all sections to default order.
    func resetAll() {
        for section in DashboardSection.allCases {
            resetOrder(for: section)
        }
    }

    /// Recalculates experience level from user engagement signals.
    func updateExperienceLevel(
        profileCreatedAt: Date,
        entryCount: Int,
        isPremium: Bool
    ) {
        let newLevel = DashboardExperienceLevel.calculate(
            profileCreatedAt: profileCreatedAt,
            entryCount: entryCount,
            isPremium: isPremium
        )
        if newLevel != experienceLevel {
            experienceLevel = newLevel
        }
    }

    // MARK: - Private Helpers

    /// Loads saved card order from UserDefaults.
    private func loadOrder(for section: DashboardSection) -> [DashboardCardID]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: section)),
              let rawValues = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        // Handle migration from old "taxReserve" → "taxVault" rename
        let migratedRawValues = rawValues.map { $0 == "taxReserve" ? "taxVault" : $0 }
        let cardIDs = migratedRawValues.compactMap { DashboardCardID(rawValue: $0) }
        return cardIDs.isEmpty ? nil : cardIDs
    }

    /// Handles migration: adds new cards that weren't in the saved list, removes deleted ones.
    /// New cards appear at the end of the section.
    private func migrate(savedIDs: [DashboardCardID], section: DashboardSection) -> [DashboardCardID] {
        let expectedIDs = Set(DashboardCardID.defaultOrder(for: section))

        // Keep only cards that still exist for this section
        var result = savedIDs.filter { expectedIDs.contains($0) }

        // Add any new cards that weren't in the saved list
        let savedSet = Set(result)
        let missing = DashboardCardID.defaultOrder(for: section).filter { !savedSet.contains($0) }
        result.append(contentsOf: missing)

        // Persist the migrated order if it changed
        if result != savedIDs {
            updateOrder(for: section, cards: result)
        }

        return result
    }
}
