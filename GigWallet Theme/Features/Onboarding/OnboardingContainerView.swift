import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var currentPage = 0
    @State private var selectedPlatforms: Set<GigPlatformType> = []

    // Tax profile state (collected during onboarding, persisted on completion)
    @State private var gigWorkerType: GigWorkerType = GigWorkerType.fullTime
    @State private var estimatedW2Withholding: Double = 0
    @State private var filingStatus: FilingStatus = FilingStatus.single
    @State private var stateCode: String = "CA"

    // Pages: 0-2 = marketing, 3 = income type, 4 = tax profile, 5 = platform selection, 6 = completion
    private let totalPages = 7

    var body: some View {
        ZStack {
            BrandColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    // Page 0: "All Your Gigs, One View"
                    OnboardingPageView(
                        icon: "chart.bar.xaxis",
                        title: "All Your Gigs,\nOne View",
                        subtitle: "See earnings from every platform in a single dashboard. No more spreadsheets.",
                        accentColor: BrandColors.primary
                    )
                    .tag(0)

                    // Page 1: "Know What You Owe"
                    OnboardingPageView(
                        icon: "building.columns.fill",
                        title: "Know What\nYou Owe",
                        subtitle: "Real-time quarterly tax estimates. Never be surprised by a tax bill again.",
                        accentColor: BrandColors.secondary
                    )
                    .tag(1)

                    // Page 2: "Never Miss a Deduction"
                    OnboardingPageView(
                        icon: "dollarsign.arrow.circlepath",
                        title: "Never Miss\na Deduction",
                        subtitle: "Smart deduction finder saves the average gig worker $1,200+ per year.",
                        accentColor: BrandColors.success
                    )
                    .tag(2)

                    // Page 3: "How Do You Earn?" — plain-language income type
                    IncomeTypeView(
                        gigWorkerType: $gigWorkerType,
                        estimatedW2Withholding: $estimatedW2Withholding
                    )
                    .tag(3)

                    // Page 4: Quick Tax Profile — filing status + state
                    TaxProfileView(
                        filingStatus: $filingStatus,
                        stateCode: $stateCode
                    )
                    .tag(4)

                    // Page 5: Platform selection
                    PlatformSelectionView(selectedPlatforms: $selectedPlatforms)
                        .tag(5)

                    // Page 6: Completion — welcome + quick-start tips
                    OnboardingCompletionView(
                        onComplete: { completeOnboarding() }
                    )
                    .tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AnimationConstants.smooth, value: currentPage)

                // Bottom controls — hide on completion page (it has its own buttons)
                if currentPage < 6 {
                    VStack(spacing: Spacing.lg) {
                        // Page indicators
                        HStack(spacing: Spacing.sm) {
                            ForEach(0..<totalPages, id: \.self) { index in
                                Capsule()
                                    .fill(index == currentPage ? BrandColors.primary : BrandColors.primary.opacity(0.2))
                                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                                    .animation(AnimationConstants.spring, value: currentPage)
                            }
                        }

                        // Action button
                        GWButton(
                            L10n.onboardingContinue,
                            icon: nil
                        ) {
                            withAnimation(AnimationConstants.smooth) {
                                currentPage += 1
                            }
                        }
                        .padding(.horizontal, Spacing.xxl)

                        Button(L10n.skip) {
                            withAnimation(AnimationConstants.smooth) {
                                // Skip goes to completion page
                                currentPage = 6
                            }
                        }
                        .font(Typography.subheadline)
                        .foregroundStyle(BrandColors.textSecondary)
                    }
                    .padding(.bottom, Spacing.xxxl)
                }
            }
        }
    }

    private func completeOnboarding() {
        // Use existing profile from auth (if any) instead of creating a duplicate
        let profile: UserProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = UserProfile(filingStatus: filingStatus, stateCode: stateCode)
            modelContext.insert(profile)
        }

        // Persist all onboarding data
        profile.hasCompletedOnboarding = true
        profile.selectedPlatforms = selectedPlatforms.map(\.rawValue)
        profile.gigWorkerType = gigWorkerType
        profile.estimatedW2Withholding = estimatedW2Withholding
        profile.filingStatus = filingStatus
        profile.stateCode = stateCode

        appState.markOnboardingCompleted()
    }
}
