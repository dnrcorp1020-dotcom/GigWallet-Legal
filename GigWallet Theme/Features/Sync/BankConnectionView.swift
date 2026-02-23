import SwiftUI
import SwiftData
import LinkKit

/// The bank account connection flow - guides users through linking their bank
/// via Plaid to automatically detect gig income deposits.
/// Uses real Plaid Link SDK to present the native bank selection UI.
struct BankConnectionView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @State private var viewModel = BankConnectionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch viewModel.state {
                case .intro:
                    bankIntroView
                case .fetchingToken:
                    fetchingTokenView
                case .syncing:
                    syncingView
                case .results:
                    syncResultsView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .background(BrandColors.groupedBackground)
            .gwNavigationTitle("Connect ", accent: "Bank", icon: "building.columns.fill")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Intro Screen

    private var bankIntroView: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                ZStack {
                    Circle()
                        .fill(BrandColors.primary.opacity(0.1))
                        .frame(width: 140, height: 140)

                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(BrandColors.primary)
                }
                .padding(.top, Spacing.xxxl)

                VStack(spacing: Spacing.md) {
                    Text("Auto-Detect Your Gig Income")
                        .font(Typography.title)
                        .multilineTextAlignment(.center)

                    Text("Connect your bank account and we'll automatically find deposits from Uber, DoorDash, Instacart, and 10+ other gig platforms.")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                VStack(alignment: .leading, spacing: Spacing.lg) {
                    BenefitRow(icon: "sparkles", text: "Auto-categorize gig income by platform", color: BrandColors.primary)
                    BenefitRow(icon: "clock.fill", text: "Save 2+ hours/week on manual entry", color: BrandColors.success)
                    BenefitRow(icon: "lock.shield.fill", text: "Bank-level encryption via Plaid", color: BrandColors.secondary)
                    BenefitRow(icon: "eye.slash.fill", text: "We never see your bank password", color: BrandColors.info)
                }
                .padding(.horizontal, Spacing.xxl)

                GWButton("Connect Bank Account", icon: "link") {
                    Task { await viewModel.startConnection() }
                }
                .padding(.horizontal, Spacing.xxl)

                Text("Powered by Plaid • Read-only access")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)

                Spacer()
            }
        }
    }

    // MARK: - Fetching Link Token (Secure Connection Animation)

    private var fetchingTokenView: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            // Animated shield + bank icon
            SecureConnectionAnimation()

            VStack(spacing: Spacing.md) {
                Text("Establishing Secure Connection")
                    .font(Typography.title)
                    .multilineTextAlignment(.center)

                Text("Setting up encrypted link to your bank")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Security badges
            VStack(spacing: Spacing.sm) {
                SecurityBadgeRow(icon: "lock.shield.fill", text: "256-bit encryption", delay: 0.3)
                SecurityBadgeRow(icon: "checkmark.shield.fill", text: "Powered by Plaid", delay: 0.6)
                SecurityBadgeRow(icon: "eye.slash.fill", text: "We never see your credentials", delay: 0.9)
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()
        }
    }

    // MARK: - Syncing

    private var syncingView: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            // Scanning animation
            ScanningAnimation()

            VStack(spacing: Spacing.md) {
                Text("Scanning Transactions")
                    .font(Typography.title)

                Text("Looking for gig income deposits...")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)

                if viewModel.syncProgress > 0 {
                    // Animated counter
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(BrandColors.primary)
                        Text("\(String(viewModel.syncProgress)) transactions analyzed")
                            .font(Typography.moneyCaption)
                            .foregroundStyle(BrandColors.primary)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(BrandColors.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
            }

            Spacer()
        }
    }

    // MARK: - Results

    private var syncResultsView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(BrandColors.success.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(BrandColors.success)
                }
                .padding(.top, Spacing.lg)

                Text("Found \(String(viewModel.matchedTransactions.count)) gig deposits!")
                    .font(Typography.title)

                if !viewModel.platformSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Platforms Detected")
                            .font(Typography.headline)
                            .padding(.horizontal, Spacing.lg)

                        ForEach(viewModel.platformSummaries) { summary in
                            DiscoveredPlatformRow(summary: summary)
                        }
                    }
                    .gwCard()
                }

                if !viewModel.matchedTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Recent Matches")
                            .font(Typography.headline)

                        ForEach(viewModel.matchedTransactions.prefix(10)) { match in
                            MatchedTransactionRow(match: match)
                        }
                    }
                    .gwCard()
                }

                GWButton("Import to GigWallet", icon: "arrow.down.circle.fill") {
                    viewModel.importTransactions(context: modelContext)
                    dismiss()
                }
                .padding(.horizontal, Spacing.lg)

                GWButton("Review First", style: .secondary) {
                    HapticManager.shared.tap()
                    // Keep results on screen but don't import — user can review matches
                    // and return to tap "Import to GigWallet" when ready
                    dismiss()
                }
                .padding(.horizontal, Spacing.lg)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(BrandColors.warning)

            Text("Connection Failed")
                .font(Typography.title)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)

            GWButton("Try Again", icon: "arrow.clockwise") {
                viewModel.state = .intro
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()
        }
    }
}

// MARK: - Subviews

struct BenefitRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28)

            Text(text)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)

            Spacer()
        }
    }
}

struct DiscoveredPlatformRow: View {
    let summary: PlatformSummary

    private var platformType: GigPlatformType {
        GigPlatformType.allCases.first { $0.rawValue == summary.platform } ?? .other
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: platformType.sfSymbol)
                .font(.system(size: 18))
                .foregroundStyle(platformType.brandColor)
                .frame(width: 36, height: 36)
                .background(platformType.brandColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(summary.platform)
                    .font(Typography.bodyMedium)

                Text("\(String(summary.transactionCount)) deposits found")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            Spacer()

            Text(CurrencyFormatter.format(summary.totalAmount))
                .font(Typography.moneySmall)
                .foregroundStyle(BrandColors.success)
        }
    }
}

struct MatchedTransactionRow: View {
    let match: TransactionMatch

    private var platformType: GigPlatformType {
        GigPlatformType.allCases.first { $0.rawValue == match.platform } ?? .other
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            GWPlatformBadge(platform: platformType)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(match.merchantName ?? match.name ?? match.platform)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                Text(match.date)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(CurrencyFormatter.format(match.amount))
                    .font(Typography.moneyCaption)
                    .foregroundStyle(BrandColors.success)

                if match.confidence >= 0.9 {
                    GWBadge("High", color: BrandColors.success)
                } else if match.confidence >= 0.7 {
                    GWBadge("Med", color: BrandColors.warning)
                } else {
                    GWBadge("Low", color: BrandColors.destructive)
                }
            }
        }
    }
}

// MARK: - ViewModel (Real Plaid Link Integration)

@MainActor
@Observable
final class BankConnectionViewModel {
    enum ConnectionState {
        case intro
        case fetchingToken
        case syncing
        case results
        case error(String)
    }

    var state: ConnectionState = .intro
    var syncProgress: Int = 0
    var matchedTransactions: [TransactionMatch] = []
    var platformSummaries: [PlatformSummary] = []

    private var plaidHandler: (any Handler)?
    private var plaidItemId: String?

    // MARK: - Step 1: Get Link Token from Backend → Create Handler → Open Link

    func startConnection() async {
        state = .fetchingToken
        HapticManager.shared.action()

        do {
            // Ensure we have a backend auth token before calling Plaid
            try await APIClient.shared.ensureAuthenticated()

            let response: LinkTokenResponse = try await APIClient.shared.request(.createLinkToken())
            createAndOpenPlaidLink(token: response.linkToken)
        } catch {
            state = .error("Could not connect to server.\n\nMake sure the backend is running:\ncd gigwallet-backend && npm start\n\n\(error.localizedDescription)")
        }
    }

    // MARK: - Step 2: Create Plaid Link Handler and Open Immediately

    private func createAndOpenPlaidLink(token: String) {
        var config = LinkTokenConfiguration(token: token) { [weak self] success in
            guard let self else { return }
            Task { @MainActor in
                await self.handlePlaidSuccess(success)
            }
        }

        config.onExit = { [weak self] exit in
            guard let self else { return }
            Task { @MainActor in
                self.handlePlaidExit(exit)
            }
        }

        let result = Plaid.create(config)
        switch result {
        case .success(let handler):
            self.plaidHandler = handler
            // Register with OAuth manager so redirects resume this handler
            PlaidOAuthManager.shared.activeHandler = handler
            // Open Plaid Link UI from the top-most view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                state = .error("Could not find root view controller to present Plaid Link")
                return
            }
            // Walk the presentation chain to find the top-most VC
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            handler.open(presentUsing: .viewController(topVC))
        case .failure(let error):
            state = .error("Failed to initialize Plaid Link: \(error.localizedDescription)")
        }
    }

    // MARK: - Step 3: Handle Success — Exchange Token + Sync

    private func handlePlaidSuccess(_ success: LinkSuccess) async {
        state = .syncing
        syncProgress = 0
        HapticManager.shared.success()

        let publicToken = success.publicToken
        let institutionName: String? = success.metadata.institution.name
        let institutionId: String? = "\(success.metadata.institution.id)"

        do {
            let exchangeResponse: ExchangeTokenResponse = try await APIClient.shared.request(
                .exchangeToken(
                    publicToken: publicToken,
                    institutionId: institutionId,
                    institutionName: institutionName
                )
            )

            plaidItemId = exchangeResponse.plaidItemId
            await syncTransactions()
        } catch {
            state = .error("Token exchange failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Step 4: Sync Transactions via Backend

    private func syncTransactions() async {
        guard let itemId = plaidItemId else {
            state = .error("No bank connection found")
            return
        }

        do {
            let syncResponse: SyncTransactionsResponse = try await APIClient.shared.request(
                .syncTransactions(plaidItemId: itemId)
            )

            syncProgress = syncResponse.synced
            matchedTransactions = syncResponse.matches
            platformSummaries = syncResponse.platformSummary

            HapticManager.shared.success()
            state = .results
        } catch {
            state = .error("Transaction sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Exit

    private func handlePlaidExit(_ exit: LinkExit) {
        if let error = exit.error {
            state = .error("Plaid Link error: \(error.localizedDescription)")
        } else {
            state = .intro
        }
        plaidHandler = nil
        PlaidOAuthManager.shared.activeHandler = nil
    }

    // MARK: - Import Matched Transactions as IncomeEntry

    func importTransactions(context: ModelContext) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Fetch existing entries to check for duplicates
        let descriptor = FetchDescriptor<IncomeEntry>()
        let existingEntries = (try? context.fetch(descriptor)) ?? []

        var importedCount = 0

        for match in matchedTransactions {
            // Skip low-confidence matches (below 70%)
            guard match.confidence >= 0.7 else { continue }

            let platform = GigPlatformType.allCases.first { $0.rawValue == match.platform } ?? .other
            let entryDate = dateFormatter.date(from: match.date) ?? .now

            // Check for duplicate: same platform, same date, same amount
            let isDuplicate = existingEntries.contains { existing in
                existing.platform == platform &&
                Calendar.current.isDate(existing.entryDate, inSameDayAs: entryDate) &&
                abs(existing.grossAmount - match.amount) < 0.01
            }

            guard !isDuplicate else { continue }

            let entry = IncomeEntry(
                amount: match.amount,
                platform: platform,
                entryDate: entryDate,
                notes: "Auto-imported via Plaid: \(match.merchantName ?? match.name ?? match.platform)"
            )
            context.insert(entry)
            importedCount += 1
        }

        HapticManager.shared.celebrate()
    }
}

// MARK: - Animated Loading Components

/// Pulsing shield + bank icon for the secure connection state.
private struct SecureConnectionAnimation: View {
    @State private var outerPulse = false
    @State private var innerRotation = false
    @State private var shieldAppeared = false

    var body: some View {
        ZStack {
            // Outer pulse rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(BrandColors.primary.opacity(outerPulse ? 0 : 0.15), lineWidth: 2)
                    .frame(width: outerPulse ? 180 : 100, height: outerPulse ? 180 : 100)
                    .animation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.6),
                        value: outerPulse
                    )
            }

            // Glowing background circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BrandColors.primary.opacity(0.15), BrandColors.primary.opacity(0.02)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            // Inner circle
            Circle()
                .fill(BrandColors.primary.opacity(0.08))
                .frame(width: 100, height: 100)

            // Shield icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(BrandColors.primary)
                .symbolEffect(.pulse, options: .repeating)
                .scaleEffect(shieldAppeared ? 1.0 : 0.5)
                .opacity(shieldAppeared ? 1.0 : 0)
        }
        .onAppear {
            outerPulse = true
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                shieldAppeared = true
            }
        }
    }
}

/// Animated scanning visual for the transaction sync state.
private struct ScanningAnimation: View {
    @State private var scanLineOffset: CGFloat = -40
    @State private var iconScale = false

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(BrandColors.success.opacity(0.06))
                .frame(width: 120, height: 120)

            // Scan line
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [.clear, BrandColors.primary.opacity(0.5), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 80, height: 3)
                .offset(y: scanLineOffset)
                .clipShape(Circle().size(width: 120, height: 120).offset(x: -20, y: -20))

            // Icon
            Image(systemName: "building.columns.fill")
                .font(.system(size: 40))
                .foregroundStyle(BrandColors.primary)
                .scaleEffect(iconScale ? 1.05 : 0.95)
        }
        .frame(width: 120, height: 120)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                scanLineOffset = 40
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                iconScale = true
            }
        }
    }
}

/// Animated security badge row that fades in with a stagger delay.
private struct SecurityBadgeRow: View {
    let icon: String
    let text: String
    let delay: Double

    @State private var appeared = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(BrandColors.success)
                .frame(width: 24)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(BrandColors.success)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(BrandColors.success.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(delay)) {
                appeared = true
            }
        }
    }
}
