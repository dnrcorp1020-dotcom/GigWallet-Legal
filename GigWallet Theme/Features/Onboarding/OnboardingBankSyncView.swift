import SwiftUI
import SwiftData

/// Bank sync page during onboarding — connects Plaid to auto-import gig income.
/// Simplified flow: value prop → connect → success inline → continue.
/// NO premium gate during onboarding.
struct OnboardingBankSyncView: View {
    @Environment(\.modelContext) private var modelContext

    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var viewModel = BankConnectionViewModel()
    @State private var hasImported = false

    /// Whether the view model is in a loading state (prevents showing skip button)
    private var isLoading: Bool {
        switch viewModel.state {
        case .fetchingToken, .syncing: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            switch viewModel.state {
            case .intro, .error:
                introContent

            case .fetchingToken:
                connectingContent

            case .syncing:
                syncingContent

            case .results:
                resultsContent
            }

            Spacer()

            // Bottom buttons
            VStack(spacing: Spacing.md) {
                switch viewModel.state {
                case .intro:
                    GWButton("Connect Bank Account", icon: "building.columns.fill") {
                        Task {
                            await viewModel.startConnection()
                        }
                    }
                    .padding(.horizontal, Spacing.xxl)

                case .error:
                    GWButton("Try Again", icon: "arrow.clockwise") {
                        Task {
                            await viewModel.startConnection()
                        }
                    }
                    .padding(.horizontal, Spacing.xxl)

                case .results:
                    GWButton(hasImported ? "Continue" : "Import & Continue", icon: "arrow.right") {
                        if !hasImported {
                            viewModel.importTransactions(context: modelContext)
                            hasImported = true
                        }
                        onComplete()
                    }
                    .padding(.horizontal, Spacing.xxl)

                default:
                    EmptyView()
                }

                if !isLoading {
                    Button("Connect Later") {
                        onSkip()
                    }
                    .font(Typography.subheadline)
                    .foregroundStyle(BrandColors.textSecondary)
                }
            }
            .padding(.bottom, Spacing.xxxl)
        }
    }

    // MARK: - Intro

    private var introContent: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(BrandColors.info.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "building.columns.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(BrandColors.info)
            }

            Text("Import Your\nEarnings")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColors.textPrimary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: Spacing.md) {
                benefitRow(icon: "bolt.fill", text: "Instantly import gig income", color: BrandColors.primary)
                benefitRow(icon: "shield.checkered", text: "Bank-level encryption via Plaid", color: BrandColors.success)
                benefitRow(icon: "sparkles", text: "Auto-detect platforms & amounts", color: BrandColors.secondary)
            }
            .padding(.horizontal, Spacing.xxxl)

            if case .error(let message) = viewModel.state {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }
        }
    }

    // MARK: - Connecting

    private var connectingContent: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(BrandColors.info)

            Text("Connecting...")
                .font(Typography.headline)
                .foregroundStyle(BrandColors.textPrimary)

            Text("Opening your bank's secure login")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    // MARK: - Syncing

    private var syncingContent: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(BrandColors.success)

            Text("Scanning Transactions...")
                .font(Typography.headline)
                .foregroundStyle(BrandColors.textPrimary)

            if viewModel.syncProgress > 0 {
                Text("\(viewModel.syncProgress) transactions scanned")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
    }

    // MARK: - Results

    private var resultsContent: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(BrandColors.success)

            Text("Income Found!")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColors.textPrimary)

            if !viewModel.platformSummaries.isEmpty {
                let totalAmount = viewModel.matchedTransactions.reduce(0.0) { $0 + $1.amount }
                let platformCount = viewModel.platformSummaries.count

                Text("We found \(CurrencyFormatter.format(totalAmount)) in gig income from \(platformCount) platform\(platformCount == 1 ? "" : "s")!")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)

                // Platform breakdown
                VStack(spacing: Spacing.sm) {
                    ForEach(viewModel.platformSummaries) { summary in
                        HStack(spacing: Spacing.sm) {
                            let platformType = GigPlatformType.allCases.first { $0.rawValue == summary.platform } ?? .other

                            Image(systemName: platformType.sfSymbol)
                                .font(.system(size: 14))
                                .foregroundStyle(platformType.brandColor)
                                .frame(width: 24)

                            Text(summary.platform)
                                .font(Typography.body)
                                .foregroundStyle(BrandColors.textPrimary)

                            Spacer()

                            Text("\(summary.transactionCount) entries")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    }
                }
                .padding(Spacing.lg)
                .background(BrandColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                .padding(.horizontal, Spacing.xxl)
            } else {
                Text("\(viewModel.matchedTransactions.count) gig transactions found and ready to import!")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }
        }
    }

    // MARK: - Helpers

    private func benefitRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            Text(text)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)

            Spacer()
        }
    }
}
