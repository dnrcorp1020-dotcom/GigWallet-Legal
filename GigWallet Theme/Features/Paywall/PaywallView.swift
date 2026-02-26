import SwiftUI
import StoreKit
import SwiftData

// MARK: - PaywallView

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var selectedPlan: PaywallPlan = .annual
    @State private var isPurchasing = false
    @State private var hasAttemptedLoad = false

    private let subscriptionManager = SubscriptionManager.shared

    enum PaywallPlan {
        case monthly, annual
    }

    // MARK: - Computed State

    private var loadState: PaywallLoadState {
        if !hasAttemptedLoad { return .loading }
        if !subscriptionManager.products.isEmpty { return .loaded }
        return .fallback
    }

    private var selectedProduct: Product? {
        selectedPlan == .annual
            ? subscriptionManager.annualProduct
            : subscriptionManager.monthlyProduct
    }

    private var annualPrice: String {
        subscriptionManager.annualProduct?.displayPrice ?? "$103.99"
    }

    private var monthlyPrice: String {
        subscriptionManager.monthlyProduct?.displayPrice ?? "$12.99"
    }

    private var annualMonthlyEquivalent: String {
        if let product = subscriptionManager.annualProduct {
            let monthly = NSDecimalNumber(decimal: product.price / 12).doubleValue
            return "$\(String(format: "%.2f", monthly))"
        }
        return "$8.67"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.xxl) {

                    // Header
                    ProHeaderSection()
                        .padding(.top, Spacing.lg)

                    // Benefits
                    ProBenefitsList()

                    // ROI / "Pays for Itself"
                    PaysForItselfSection(annualMonthly: annualMonthlyEquivalent)

                    // Plan picker
                    ProPlanPicker(
                        selectedPlan: $selectedPlan,
                        annualPrice: annualPrice,
                        monthlyPrice: monthlyPrice,
                        annualMonthly: annualMonthlyEquivalent
                    )

                    // CTA + error
                    ProCTASection(
                        loadState: loadState,
                        selectedPlan: selectedPlan,
                        selectedProduct: selectedProduct,
                        annualPrice: annualPrice,
                        monthlyPrice: monthlyPrice,
                        isPurchasing: isPurchasing,
                        isAlreadyPremium: subscriptionManager.isPremium,
                        errorMessage: subscriptionManager.errorMessage,
                        onPurchase: { Task { await handlePurchase() } },
                        onRetry: { Task { await retryLoad() } }
                    )

                    // Footer
                    ProFooter(
                        isPurchasing: isPurchasing,
                        isAlreadyPremium: subscriptionManager.isPremium,
                        onRestore: { Task { await handleRestore() } }
                    )
                }
                .padding(.bottom, Spacing.xxxl)
            }
            .background(BrandColors.groupedBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Not now")
                            .font(Typography.subheadline)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }
            .task {
                await subscriptionManager.loadProducts(forceReload: true)
                hasAttemptedLoad = true
            }
        }
    }

    // MARK: - Actions

    private func handlePurchase() async {
        guard !isPurchasing else { return }

        if let product = selectedProduct {
            isPurchasing = true
            let success = await subscriptionManager.purchase(product)
            if success {
                subscriptionManager.syncToUserProfile(context: modelContext)
                HapticManager.shared.celebrate()
                try? await Task.sleep(for: .milliseconds(600))
                dismiss()
            }
            isPurchasing = false
        } else {
            // Products not loaded — try once more
            await subscriptionManager.loadProducts(forceReload: true)
            hasAttemptedLoad = true

            if let product = selectedProduct {
                isPurchasing = true
                let success = await subscriptionManager.purchase(product)
                if success {
                    subscriptionManager.syncToUserProfile(context: modelContext)
                    HapticManager.shared.celebrate()
                    try? await Task.sleep(for: .milliseconds(600))
                    dismiss()
                }
                isPurchasing = false
            } else {
                subscriptionManager.errorMessage = "Unable to connect to the App Store. Please check your connection and try again."
                HapticManager.shared.warning()
            }
        }
    }

    private func retryLoad() async {
        hasAttemptedLoad = false
        await subscriptionManager.loadProducts(forceReload: true)
        hasAttemptedLoad = true
    }

    private func handleRestore() async {
        isPurchasing = true
        await subscriptionManager.restorePurchases()
        if subscriptionManager.isPremium {
            subscriptionManager.syncToUserProfile(context: modelContext)
            HapticManager.shared.success()
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        }
        isPurchasing = false
    }
}

// MARK: - Load State

private enum PaywallLoadState {
    case loading, loaded, fallback
}

// MARK: - Header

private struct ProHeaderSection: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(BrandColors.primary.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(BrandColors.primary)
            }

            VStack(spacing: Spacing.sm) {
                Text("GigWallet Pro")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(BrandColors.textPrimary)

                Text("Your complete financial toolkit for gig work")
                    .font(Typography.subheadline)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Spacing.xxl)
    }
}

// MARK: - Benefits List

private struct ProBenefitsList: View {
    private let benefits: [(icon: String, title: String, subtitle: String)] = [
        ("chart.pie.fill", "Financial Planner", "See your full monthly picture — income, expenses, and what's left"),
        ("brain.head.profile.fill", "AI Work Advisor", "Know when and where to work for the best hourly rate"),
        ("magnifyingglass", "Deduction Finder", "Uncover write-offs you're missing at tax time"),
        ("chart.xyaxis.line", "Earnings Analytics", "Charts, heatmaps, and trends across all your platforms"),
        ("building.columns.fill", "Bank Auto-Sync", "Connect your bank to import earnings automatically"),
        ("doc.text.fill", "Tax Export", "One-tap CSV, TurboTax, and Schedule C reports"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
                HStack(alignment: .top, spacing: Spacing.lg) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(BrandColors.primary)
                        .frame(width: 24, height: 24)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(benefit.title)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.textPrimary)

                        Text(benefit.subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Spacing.md)
                .padding(.horizontal, Spacing.lg)

                if benefit.title != benefits.last?.title {
                    Divider()
                        .padding(.leading, Spacing.lg + 24 + Spacing.lg)
                }
            }
        }
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Pays for Itself

private struct PaysForItselfSection: View {
    let annualMonthly: String

    private let stats: [(value: String, label: String)] = [
        ("$5,000+", "Avg missed deductions/yr"),
        ("$0.22", "Cost per day (annual)"),
        ("1", "Found deduction pays for a year"),
    ]

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(BrandColors.success)

                Text("Pays for Itself")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()
            }

            // Stat pills row
            HStack(spacing: Spacing.sm) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    VStack(spacing: Spacing.xxs) {
                        Text(stat.value)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(BrandColors.success)

                        Text(stat.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BrandColors.textTertiary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(BrandColors.success.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                }
            }

            // Persuasion copy
            VStack(spacing: Spacing.sm) {
                Text("The average gig worker misses thousands in deductions every year. GigWallet's AI deduction finder, mileage tracking, and tax export tools help you keep more of what you earn.")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColors.success)
                    Text("Most users save more than the subscription in their first month")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandColors.success)
                }
            }
        }
        .padding(Spacing.lg)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                .stroke(BrandColors.success.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Plan Picker

private struct ProPlanPicker: View {
    @Binding var selectedPlan: PaywallView.PaywallPlan
    let annualPrice: String
    let monthlyPrice: String
    let annualMonthly: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Choose your plan")
                .font(Typography.headline)
                .foregroundStyle(BrandColors.textPrimary)

            VStack(spacing: Spacing.sm) {
                // Annual
                planCard(
                    isSelected: selectedPlan == .annual,
                    title: "Annual",
                    price: annualPrice,
                    period: "/year",
                    detail: "\(annualMonthly)/mo",
                    recommended: true
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = .annual }
                    HapticManager.shared.select()
                }

                // Monthly
                planCard(
                    isSelected: selectedPlan == .monthly,
                    title: "Monthly",
                    price: monthlyPrice,
                    period: "/month",
                    detail: nil,
                    recommended: false
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = .monthly }
                    HapticManager.shared.select()
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    @ViewBuilder
    private func planCard(
        isSelected: Bool,
        title: String,
        price: String,
        period: String,
        detail: String?,
        recommended: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                // Radio indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? BrandColors.primary : BrandColors.textTertiary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(BrandColors.primary)
                            .frame(width: 14, height: 14)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.sm) {
                        Text(title)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.textPrimary)

                        if recommended {
                            Text("Best Value")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BrandColors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(BrandColors.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    if let detail {
                        Text(detail)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(Typography.moneySmall)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(period)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                    .stroke(
                        isSelected ? BrandColors.primary : BrandColors.textTertiary.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CTA Section

private struct ProCTASection: View {
    let loadState: PaywallLoadState
    let selectedPlan: PaywallView.PaywallPlan
    let selectedProduct: Product?
    let annualPrice: String
    let monthlyPrice: String
    let isPurchasing: Bool
    let isAlreadyPremium: Bool
    let errorMessage: String?
    let onPurchase: () -> Void
    let onRetry: () -> Void

    /// Whether the currently selected product has a free trial introductory offer.
    private var hasFreeTrial: Bool {
        guard let product = selectedProduct,
              let intro = product.subscription?.introductoryOffer,
              intro.paymentMode == .freeTrial else { return false }
        return true
    }

    private var buttonLabel: String {
        if isPurchasing { return "Processing..." }
        if loadState == .loading { return "Loading..." }
        if isAlreadyPremium { return "You're Already Pro!" }
        return hasFreeTrial ? "Start Free Trial" : "Subscribe Now"
    }

    private var priceDisclosure: String {
        let price = selectedPlan == .annual ? annualPrice : monthlyPrice
        let period = selectedPlan == .annual ? "year" : "month"
        if hasFreeTrial {
            return "After 7-day free trial, \(price)/\(period). Cancel anytime."
        } else {
            return "\(price)/\(period). Cancel anytime."
        }
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // CTA Button
            Button {
                onPurchase()
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isPurchasing || loadState == .loading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    }
                    Text(buttonLabel)
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isAlreadyPremium ? BrandColors.success : BrandColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            }
            .disabled(isPurchasing || loadState == .loading || isAlreadyPremium)
            .opacity(isPurchasing || isAlreadyPremium ? 0.7 : 1.0)
            .padding(.horizontal, Spacing.lg)

            // Price disclosure
            Text(priceDisclosure)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)

            // Apple-required auto-renewal disclosure
            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions by going to your App Store account settings after purchase.")
                .font(.system(size: 10))
                .foregroundStyle(BrandColors.textTertiary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)

            // Error
            if let error = errorMessage {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                    Text(error)
                        .font(Typography.caption)
                }
                .foregroundStyle(BrandColors.warning)
                .padding(.horizontal, Spacing.lg)

                Button {
                    onRetry()
                } label: {
                    Text("Try again")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(BrandColors.primary)
                }
            }
        }
    }
}

// MARK: - Footer

private struct ProFooter: View {
    let isPurchasing: Bool
    let isAlreadyPremium: Bool
    let onRestore: () -> Void

    private static let termsURL = URL(string: "https://dnrcorp1020-dotcom.github.io/GigWallet-Legal/terms-of-service.html")
    private static let privacyURL = URL(string: "https://dnrcorp1020-dotcom.github.io/GigWallet-Legal/privacy-policy.html")

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Manage Subscription — only for existing subscribers
            if isAlreadyPremium {
                Button("Manage Subscription") {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        Task {
                            try? await AppStore.showManageSubscriptions(in: scene)
                        }
                    }
                }
                .font(Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(BrandColors.primary)
            }

            Button("Restore Purchases") {
                onRestore()
            }
            .font(Typography.caption)
            .fontWeight(.medium)
            .foregroundStyle(BrandColors.textSecondary)
            .disabled(isPurchasing)

            HStack(spacing: Spacing.lg) {
                if let termsURL = Self.termsURL {
                    Link("Terms of Service", destination: termsURL)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                Text("|")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary.opacity(0.5))

                if let privacyURL = Self.privacyURL {
                    Link("Privacy Policy", destination: privacyURL)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
        }
        .padding(.top, Spacing.md)
    }
}
