import SwiftUI
import SwiftData

/// Argyle gig platform connection flow — guides users through connecting
/// their gig platform accounts (Uber, DoorDash, Lyft, etc.) via Argyle Link
/// to automatically sync trip-level earnings with fee/tip breakdowns.
///
/// State machine: intro → fetchingToken → linking → syncing → results → error
struct ArgyleConnectionView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @State private var viewModel = ArgyleConnectionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch viewModel.state {
                case .intro:
                    argyleIntroView
                case .fetchingToken:
                    fetchingTokenView
                case .linking:
                    linkingView
                case .syncing:
                    syncingView
                case .results:
                    syncResultsView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .background(BrandColors.groupedBackground)
            .gwNavigationTitle("Connect ", accent: "Gig Platforms", icon: "arrow.triangle.2.circlepath.circle.fill")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Intro Screen

    private var argyleIntroView: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                ZStack {
                    Circle()
                        .fill(BrandColors.primary.opacity(0.1))
                        .frame(width: 140, height: 140)

                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(BrandColors.primary)
                }
                .padding(.top, Spacing.xxxl)

                VStack(spacing: Spacing.md) {
                    Text("Trip-Level Gig Income")
                        .font(Typography.title)
                        .multilineTextAlignment(.center)

                    Text("Connect directly to Uber, DoorDash, Lyft, and 10+ gig platforms to get trip-by-trip earnings with fee, tip, and mileage breakdowns.")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                // Comparison: Bank Sync vs Argyle
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.primary)
                        Text("Why connect platforms directly?")
                            .font(Typography.headline)
                            .foregroundStyle(BrandColors.textPrimary)
                    }

                    ComparisonRow(
                        icon: "list.bullet.rectangle.portrait",
                        text: "See every trip, not just lump deposits",
                        color: BrandColors.primary
                    )
                    ComparisonRow(
                        icon: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90",
                        text: "Exact fee, tip, and bonus breakdowns",
                        color: BrandColors.success
                    )
                    ComparisonRow(
                        icon: "car.fill",
                        text: "Auto-import trip mileage for deductions",
                        color: BrandColors.secondary
                    )
                    ComparisonRow(
                        icon: "clock.fill",
                        text: "Calculate your real hourly rate per trip",
                        color: BrandColors.info
                    )
                }
                .padding(.horizontal, Spacing.xxl)

                GWButton("Connect Gig Platforms", icon: "link") {
                    Task { await viewModel.startConnection() }
                }
                .padding(.horizontal, Spacing.xxl)

                Text("Powered by Argyle \u{00B7} Read-only access")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)

                Spacer()
            }
        }
    }

    // MARK: - Fetching Token

    private var fetchingTokenView: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            ArgyleSecureAnimation()

            VStack(spacing: Spacing.md) {
                Text("Setting Up Connection")
                    .font(Typography.title)
                    .multilineTextAlignment(.center)

                Text("Preparing secure link to your gig platforms")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.sm) {
                SecurityBadge(icon: "lock.shield.fill", text: "End-to-end encryption", delay: 0.3)
                SecurityBadge(icon: "checkmark.shield.fill", text: "Powered by Argyle", delay: 0.6)
                SecurityBadge(icon: "eye.slash.fill", text: "We never see your password", delay: 0.9)
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()
        }
    }

    // MARK: - Linking (Argyle Link SDK is open)

    private var linkingView: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(BrandColors.primary.opacity(0.08))
                    .frame(width: 120, height: 120)

                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BrandColors.primary)
                    .symbolEffect(.pulse, options: .repeating)
            }

            VStack(spacing: Spacing.md) {
                Text("Connect Your Platform")
                    .font(Typography.title)

                Text("Sign in to your gig account in the window above to link your earnings data.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer()
        }
    }

    // MARK: - Syncing

    private var syncingView: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            ArgyleScanAnimation()

            VStack(spacing: Spacing.md) {
                Text("Syncing Gig Data")
                    .font(Typography.title)

                Text("Fetching trips, earnings, and mileage...")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)

                if viewModel.syncedGigCount > 0 {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(BrandColors.primary)
                        Text("\(String(viewModel.syncedGigCount)) gigs synced")
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

                Text("Found \(String(viewModel.gigs.count)) Gigs!")
                    .font(Typography.title)

                // Total earnings
                if viewModel.totalEarnings > 0 {
                    VStack(spacing: Spacing.xs) {
                        Text("Total Earnings")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                        Text(CurrencyFormatter.format(viewModel.totalEarnings))
                            .font(Typography.largeTitle)
                            .foregroundStyle(BrandColors.success)
                    }
                    .padding(.vertical, Spacing.sm)
                }

                // Platform summaries
                if !viewModel.platformSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Platforms Connected")
                            .font(Typography.headline)
                            .padding(.horizontal, Spacing.lg)

                        ForEach(viewModel.platformSummaries) { summary in
                            ArgylePlatformRow(summary: summary)
                        }
                    }
                    .gwCard()
                }

                // Sample gigs
                if !viewModel.gigs.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Recent Gigs")
                            .font(Typography.headline)

                        ForEach(viewModel.gigs.prefix(8)) { gig in
                            ArgyleGigRow(gig: gig)
                        }

                        if viewModel.gigs.count > 8 {
                            Text("+ \(String(viewModel.gigs.count - 8)) more gigs")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .gwCard()
                }

                GWButton("Import to GigWallet", icon: "arrow.down.circle.fill") {
                    viewModel.importGigs(context: modelContext)
                    HapticManager.shared.celebrate()
                    dismiss()
                }
                .padding(.horizontal, Spacing.lg)

                GWButton("Review First", style: .secondary) {
                    HapticManager.shared.tap()
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

private struct ComparisonRow: View {
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

private struct SecurityBadge: View {
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

private struct ArgylePlatformRow: View {
    let summary: ArgylePlatformSummary

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

                Text("\(String(summary.gigCount)) gigs found")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            Spacer()

            Text(CurrencyFormatter.format(summary.totalEarnings))
                .font(Typography.moneySmall)
                .foregroundStyle(BrandColors.success)
        }
    }
}

private struct ArgyleGigRow: View {
    let gig: ArgyleGig

    private var platformType: GigPlatformType {
        GigPlatformType.allCases.first { $0.rawValue == gig.platform } ?? .other
    }

    private var formattedDate: String {
        guard let dateStr = gig.startDatetime else { return "Unknown" }
        // Parse ISO date and format for display
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        // Fallback: try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return String(dateStr.prefix(16))
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            GWPlatformBadge(platform: platformType)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(gig.employer)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                HStack(spacing: Spacing.sm) {
                    Text(formattedDate)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)

                    if let distance = gig.distance, distance > 0 {
                        Text("\(String(format: "%.1f", distance)) mi")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(CurrencyFormatter.format(gig.total ?? gig.pay ?? 0))
                    .font(Typography.moneyCaption)
                    .foregroundStyle(BrandColors.success)

                if let tips = gig.tips, tips > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.system(size: 8))
                        Text("+\(CurrencyFormatter.format(tips))")
                            .font(Typography.caption2)
                    }
                    .foregroundStyle(BrandColors.info)
                }
            }
        }
    }
}

// MARK: - Animated Components

private struct ArgyleSecureAnimation: View {
    @State private var outerPulse = false
    @State private var shieldAppeared = false

    var body: some View {
        ZStack {
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

            Circle()
                .fill(BrandColors.primary.opacity(0.08))
                .frame(width: 100, height: 100)

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
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

private struct ArgyleScanAnimation: View {
    @State private var scanLineOffset: CGFloat = -40
    @State private var iconScale = false

    var body: some View {
        ZStack {
            Circle()
                .fill(BrandColors.success.opacity(0.06))
                .frame(width: 120, height: 120)

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

            Image(systemName: "car.fill")
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

// MARK: - ViewModel

@MainActor
@Observable
final class ArgyleConnectionViewModel {
    enum ConnectionState {
        case intro
        case fetchingToken
        case linking
        case syncing
        case results
        case error(String)
    }

    var state: ConnectionState = .intro
    var syncedGigCount: Int = 0
    var gigs: [ArgyleGig] = []
    var platformSummaries: [ArgylePlatformSummary] = []
    var totalEarnings: Double = 0

    private var userToken: String?
    private var linkKey: String?
    private var isSandbox: Bool = true

    // MARK: - Step 1: Create Argyle User → Get Token

    func startConnection() async {
        state = .fetchingToken
        HapticManager.shared.action()

        do {
            try await APIClient.shared.ensureAuthenticated()

            let response: ArgyleUserResponse = try await APIClient.shared.request(.createArgyleUser())
            userToken = response.userToken
            linkKey = response.linkKey
            isSandbox = response.sandbox

            // Open Argyle Link SDK
            openArgyleLink()
        } catch {
            state = .error("Could not connect to server.\n\nMake sure the backend is running:\ncd gigwallet-backend && npm start\n\n\(error.localizedDescription)")
        }
    }

    // MARK: - Step 2: Open Argyle Link SDK

    private func openArgyleLink() {
        // Argyle Link SDK integration
        // The SDK handles the full connection flow in a native UI
        // On success, it calls back with the connected account
        //
        // NOTE: Requires `import Argyle` when the Argyle Link SDK resolves properly.
        // For now, we simulate the flow by going directly to sync.
        // When the SDK is properly configured with your Argyle account credentials:
        //
        // let config = LinkConfig(
        //     userToken: userToken ?? "",
        //     sandbox: isSandbox
        // )
        // config.onAccountConnected = { [weak self] accountId, userId, itemId in
        //     Task { @MainActor in
        //         await self?.handleAccountConnected()
        //     }
        // }
        // config.onClose = { [weak self] in
        //     Task { @MainActor in
        //         self?.handleLinkClosed()
        //     }
        // }
        // ArgyleLink.start(from: topVC, config: config)

        state = .linking

        // For sandbox testing: auto-advance to sync after a brief delay
        // Remove this when real Argyle Link SDK is integrated
        Task {
            try? await Task.sleep(for: .seconds(2))
            await handleAccountConnected()
        }
    }

    // MARK: - Step 3: Account Connected → Sync Gigs

    func handleAccountConnected() async {
        state = .syncing
        syncedGigCount = 0
        HapticManager.shared.success()

        do {
            // Trigger backend to fetch gigs from Argyle API
            let syncResponse: ArgyleSyncResponse = try await APIClient.shared.request(.syncArgyleGigs())
            syncedGigCount = syncResponse.synced

            // Fetch the synced gigs
            let gigsResponse: ArgyleGigResponse = try await APIClient.shared.request(.argyleGigs())
            gigs = gigsResponse.gigs
            platformSummaries = syncResponse.platformSummaries
            totalEarnings = syncResponse.totalEarnings

            HapticManager.shared.success()
            state = .results
        } catch {
            state = .error("Failed to sync gig data: \(error.localizedDescription)")
        }
    }

    private func handleLinkClosed() {
        if case .linking = state {
            state = .intro
        }
    }

    // MARK: - Step 4: Import Gigs → IncomeEntry + MileageTrip

    func importGigs(context: ModelContext) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        // Fetch existing entries to check for duplicates
        let descriptor = FetchDescriptor<IncomeEntry>()
        let existingEntries = (try? context.fetch(descriptor)) ?? []

        var importedCount = 0

        for gig in gigs {
            let platform = GigPlatformType.allCases.first { $0.rawValue == gig.platform } ?? .other
            let pay = gig.pay ?? gig.total ?? 0
            guard pay > 0 else { continue }

            // Parse date
            var entryDate = Date.now
            if let dateStr = gig.startDatetime {
                if let date = isoFormatter.date(from: dateStr) {
                    entryDate = date
                } else if let date = isoFormatterNoFrac.date(from: dateStr) {
                    entryDate = date
                }
            }

            // Dedup: same platform + same date + amount within $0.01
            let isDuplicate = existingEntries.contains { existing in
                existing.platform == platform &&
                Calendar.current.isDate(existing.entryDate, inSameDayAs: entryDate) &&
                abs(existing.grossAmount - pay) < 0.01
            }
            guard !isDuplicate else { continue }

            // Create IncomeEntry
            let entry = IncomeEntry(
                amount: pay,
                tips: gig.tips ?? 0,
                platformFees: gig.fees ?? 0,
                platform: platform,
                entryMethod: .apiSync,
                entryDate: entryDate,
                notes: "Auto-imported via Argyle: \(gig.employer)"
            )
            context.insert(entry)
            importedCount += 1

            // Auto-create MileageTrip if distance data available
            if let distance = gig.distance, distance > 0 {
                let unit = gig.distanceUnit ?? "miles"
                let miles = unit.lowercased() == "km" ? distance * 0.621371 : distance

                let trip = MileageTrip(
                    miles: miles,
                    purpose: "\(gig.employer) gig trip",
                    tripDate: entryDate,
                    platform: platform,
                    isBusinessMiles: true
                )
                context.insert(trip)
            }
        }

        HapticManager.shared.celebrate()
    }
}
