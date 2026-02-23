import StoreKit
import SwiftUI
import SwiftData

/// Manages StoreKit 2 subscription lifecycle: product loading, purchasing,
/// restoring, entitlement checking, and transaction listening.
///
/// This is the single source of truth for premium status at runtime.
/// On purchase/restore, it also syncs state to the SwiftData `UserProfile`
/// so that `profile.isPremium` works even before StoreKit finishes loading.
@MainActor
@Observable
final class SubscriptionManager: @unchecked Sendable {
    static let shared = SubscriptionManager()

    // MARK: - Product Identifiers

    static let monthlyProductID = "com.dnrcorp.gigwallet.pro.monthly"
    static let annualProductID = "com.dnrcorp.gigwallet.pro.annual"
    static let allProductIDs: Set<String> = [monthlyProductID, annualProductID]

    // MARK: - Published State

    /// Available subscription products fetched from the App Store
    var products: [Product] = []

    /// Currently active subscription product IDs
    var purchasedProductIDs: Set<String> = []

    /// Whether a purchase or restore is in progress
    var isLoading: Bool = false

    /// User-facing error message (auto-clears after display)
    var errorMessage: String?

    // MARK: - Computed Properties

    /// Whether the user has an active premium subscription
    var isPremium: Bool { !purchasedProductIDs.isEmpty }

    /// The monthly product, if loaded
    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    /// The annual product, if loaded
    var annualProduct: Product? {
        products.first { $0.id == Self.annualProductID }
    }

    // MARK: - Private

    /// Background task listening for transaction updates (renewals, cancellations, refunds)
    private var transactionListener: Task<Void, Error>?

    // MARK: - Init

    private init() {
        transactionListener = listenForTransactions()
    }

    // MARK: - Load Products

    /// Fetches subscription products from the App Store.
    /// Call this when the paywall appears. Use `forceReload: true` for retry.
    func loadProducts(forceReload: Bool = false) async {
        guard products.isEmpty || forceReload else { return }
        errorMessage = nil
        do {
            #if DEBUG
            print("[SubscriptionManager] Loading products for IDs: \(Self.allProductIDs)")
            #endif
            let storeProducts = try await Product.products(for: Self.allProductIDs)
            #if DEBUG
            print("[SubscriptionManager] Loaded \(storeProducts.count) products: \(storeProducts.map { "\($0.id) — \($0.displayPrice)" })")
            #endif
            products = storeProducts.sorted { $0.price > $1.price }
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Failed to load products: \(error)")
            #endif
            errorMessage = "Unable to load subscription options. Please check your connection."
        }
    }

    // MARK: - Purchase

    /// Initiates a purchase for the given product.
    /// Returns `true` if the purchase succeeded or was already owned.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // Update local state
                purchasedProductIDs.insert(transaction.productID)
                // Always finish the transaction
                await transaction.finish()
                isLoading = false
                return true

            case .userCancelled:
                // User tapped cancel — not an error
                isLoading = false
                return false

            case .pending:
                // Waiting for approval (Ask to Buy, SCA, etc.)
                errorMessage = "Purchase is pending approval."
                isLoading = false
                return false

            @unknown default:
                isLoading = false
                return false
            }
        } catch {
            isLoading = false
            #if DEBUG
            print("[SubscriptionManager] Purchase failed: \(error)")
            #endif
            errorMessage = "Purchase failed. Please try again."
            return false
        }
    }

    // MARK: - Restore Purchases

    /// Restores previously purchased subscriptions.
    /// Uses `Transaction.currentEntitlements` which checks with the App Store.
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        // Sync with App Store to get latest transaction state
        try? await AppStore.sync()

        var foundAny = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchasedProductIDs.insert(transaction.productID)
                foundAny = true
            }
        }

        isLoading = false

        if !foundAny {
            errorMessage = "No active subscriptions found."
        }
    }

    // MARK: - Check Entitlements (App Launch)

    /// Called on app launch to restore subscription state from the App Store.
    /// Does NOT show errors — silently checks for active entitlements.
    func checkEntitlements() async {
        var activeIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                activeIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = activeIDs
    }

    // MARK: - Sync to UserProfile

    /// Syncs the current subscription state to the SwiftData UserProfile.
    /// Call this after a purchase, restore, or entitlement check when a ModelContext is available.
    func syncToUserProfile(context: ModelContext) {
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(descriptor).first else { return }

        let wasPremium = profile.subscriptionTier == .premium
        let nowPremium = isPremium

        if nowPremium && !wasPremium {
            profile.subscriptionTier = .premium
            profile.updatedAt = .now
        } else if !nowPremium && wasPremium {
            profile.subscriptionTier = .free
            profile.updatedAt = .now
        }

        do {
            try context.save()
        } catch {
            // Premium status persistence is critical — retry once after a short delay.
            // If this fails, the user's premium status reverts on next launch until
            // checkEntitlements() runs again and re-syncs from StoreKit.
            #if DEBUG
            print("⚠️ SubscriptionManager: Failed to save premium status: \(error)")
            #endif
            // Retry save — SwiftData context errors are sometimes transient
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                try? context.save()
            }
        }
    }

    // MARK: - Transaction Listener

    /// Notification posted when subscription state changes via transaction listener.
    /// Observers (e.g., MainTabView) should call `syncToUserProfile(context:)` in response.
    static let subscriptionDidChangeNotification = Notification.Name("SubscriptionManager.subscriptionDidChange")

    /// Listens for StoreKit transaction updates in the background.
    /// Handles auto-renewals, cancellations, refunds, and revocations.
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? await self.checkVerified(result) {
                    // Check if this transaction is still active
                    if transaction.revocationDate != nil {
                        // Subscription was refunded/revoked
                        _ = await MainActor.run {
                            self.purchasedProductIDs.remove(transaction.productID)
                        }
                    } else if let expirationDate = transaction.expirationDate,
                              expirationDate < Date.now {
                        // Subscription expired
                        _ = await MainActor.run {
                            self.purchasedProductIDs.remove(transaction.productID)
                        }
                    } else {
                        // Active subscription (renewal or new)
                        _ = await MainActor.run {
                            self.purchasedProductIDs.insert(transaction.productID)
                        }
                    }
                    await transaction.finish()

                    // Notify the app to persist subscription state to SwiftData
                    await MainActor.run {
                        NotificationCenter.default.post(name: Self.subscriptionDidChangeNotification, object: nil)
                    }
                }
            }
        }
    }

    // MARK: - Verification

    /// Verifies a StoreKit transaction using local JWS verification.
    /// StoreKit 2 handles the cryptographic verification automatically.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
