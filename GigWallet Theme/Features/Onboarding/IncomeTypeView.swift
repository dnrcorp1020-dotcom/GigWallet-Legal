import SwiftUI

/// Onboarding page that asks "How Do You Earn?" in plain language.
/// Maps user's answer to `GigWorkerType` enum and optionally collects
/// estimated W-2 withholding for side-gig workers.
struct IncomeTypeView: View {
    @Binding var gigWorkerType: GigWorkerType
    @Binding var estimatedW2Withholding: Double

    @State private var isAnimated = false

    private let withholdingPresets: [(label: String, value: Double)] = [
        ("$0", 0),
        ("$5K", 5_000),
        ("$10K", 10_000),
        ("$15K", 15_000),
        ("$20K", 20_000),
        ("$25K+", 25_000),
        ("Not sure", 8_000)
    ]

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
                .frame(height: Spacing.xl)

            // Header
            VStack(spacing: Spacing.md) {
                Text("How Do You\nEarn?")
                    .font(Typography.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("This helps us estimate your taxes more accurately")
                    .font(Typography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.horizontal, Spacing.xxxl)
            }
            .opacity(isAnimated ? 1 : 0)
            .offset(y: isAnimated ? 0 : 20)
            .animation(AnimationConstants.smooth.delay(0.1), value: isAnimated)

            // Two selection cards
            VStack(spacing: Spacing.md) {
                IncomeTypeCard(
                    icon: "briefcase.fill",
                    title: "This is my main gig",
                    subtitle: "Gig work is my primary income source",
                    isSelected: gigWorkerType == .fullTime,
                    accentColor: BrandColors.primary
                ) {
                    withAnimation(AnimationConstants.spring) {
                        gigWorkerType = .fullTime
                        estimatedW2Withholding = 0
                    }
                }

                IncomeTypeCard(
                    icon: "building.2.fill",
                    title: "I also have a regular job",
                    subtitle: "I gig on the side \u{2014} my employer withholds taxes",
                    isSelected: gigWorkerType == .sideGig,
                    accentColor: BrandColors.info
                ) {
                    withAnimation(AnimationConstants.spring) {
                        gigWorkerType = .sideGig
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .scaleEffect(isAnimated ? 1.0 : 0.95)
            .opacity(isAnimated ? 1 : 0)
            .animation(AnimationConstants.bouncy.delay(0.2), value: isAnimated)

            // W-2 withholding follow-up (only shows for side gig)
            if gigWorkerType == .sideGig {
                VStack(spacing: Spacing.md) {
                    Text("Roughly how much does your employer\ntake out for taxes each year?")
                        .font(Typography.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BrandColors.textSecondary)

                    witholdingPresetsGrid
                }
                .padding(.horizontal, Spacing.lg)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }

            Spacer()
            Spacer()
        }
        .onAppear { isAnimated = true }
        .onDisappear { isAnimated = false }
    }

    private var witholdingPresetsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)
            ],
            spacing: Spacing.sm
        ) {
            ForEach(withholdingPresets, id: \.label) { preset in
                Button {
                    withAnimation(AnimationConstants.quick) {
                        estimatedW2Withholding = preset.value
                    }
                } label: {
                    Text(preset.label)
                        .font(Typography.caption)
                        .foregroundStyle(
                            estimatedW2Withholding == preset.value
                                ? .white
                                : BrandColors.textPrimary
                        )
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(
                            estimatedW2Withholding == preset.value
                                ? BrandColors.info
                                : BrandColors.tertiaryBackground
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    estimatedW2Withholding == preset.value
                                        ? BrandColors.info
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
            }
        }
    }
}

// MARK: - Income Type Selection Card

private struct IncomeTypeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentColor : accentColor.opacity(0.1))
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? .white : accentColor)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? accentColor : BrandColors.textTertiary)
            }
            .padding(Spacing.lg)
            .background(isSelected ? accentColor.opacity(0.06) : BrandColors.tertiaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                    .stroke(isSelected ? accentColor : .clear, lineWidth: 2)
            )
        }
    }
}
