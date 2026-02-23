import SwiftData
import Foundation

enum ModelContainerSetup {
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            IncomeEntry.self,
            ExpenseEntry.self,
            TaxEstimate.self,
            PlatformConnection.self,
            MileageTrip.self,
            TaxPayment.self,
            TaxVaultEntry.self,
            Invoice.self,
            BudgetItem.self,
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        return try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    static func createPreviewContainer() -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            IncomeEntry.self,
            ExpenseEntry.self,
            TaxEstimate.self,
            PlatformConnection.self,
            MileageTrip.self,
            TaxPayment.self,
            TaxVaultEntry.self,
            Invoice.self,
            BudgetItem.self,
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            DataSeeder.seedPreviewData(context: container.mainContext)
            return container
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}
