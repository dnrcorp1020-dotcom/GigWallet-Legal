import SwiftUI

/// Final onboarding page — "You're All Set!" with quick-start actions.
/// Replaces bank sync (Pro feature) so free users get a clear manual-first experience.
///
/// Layout:
///  ┌────────────────────────────────────┐
///  │        ✅ (animated checkmark)     │
///  │        You're All Set!             │
///  │  Your financial command center     │
///  │  is ready.                         │
///  │                                    │
///  │  ┌─ Log Your First Gig ─────────┐ │
///  │  │  Add earnings to see your     │ │
///  │  │  dashboard come to life       │ │
///  │  └──────────────────────────────┘ │
///  │  ┌─ Track an Expense ───────────┐ │
///  │  │  Start building your         │ │
///  │  │  deduction portfolio         │ │
///  │  └──────────────────────────────┘ │
///  │  ┌─ Log a Trip ─────────────────┐ │
///  │  │  Mileage adds up — $0.70/mi  │ │
///  │  └──────────────────────────────┘ │
///  │                                    │
///  │  ┌─ Want it fully automated? ───┐ │
///  │  │  Upgrade to Pro →            │ │
///  │  └──────────────────────────────┘ │
///  │                                    │
///  │          [Get Started]             │
///  └────────────────────────────────────┘
struct OnboardingCompletionView: View {
    @Environment(AppState.self) private var appState
    let onComplete: () -> Void

    @State private var isAnimated = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Hero checkmark
            heroSection

            // Quick-start tips
            VStack(spacing: Spacing.md) {
                quickStartRow(
                    icon: "dollarsign.circle.fill",
                    title: L10n.onboardingTipLogGig,
                    subtitle: L10n.onboardingTipLogGigDetail,
                    color: BrandColors.success
                )

                quickStartRow(
                    icon: "creditcard.fill",
                    title: L10n.onboardingTipTrackExpense,
                    subtitle: L10n.onboardingTipTrackExpenseDetail,
                    color: BrandColors.destructive
                )

                quickStartRow(
                    icon: "car.fill",
                    title: L10n.onboardingTipLogTrip,
                    subtitle: L10n.onboardingTipLogTripDetail,
                    color: BrandColors.info
                )
            }
            .padding(.horizontal, Spacing.xxl)
            .opacity(isAnimated ? 1 : 0)
            .offset(y: isAnimated ? 0 : 20)
            .animation(AnimationConstants.smooth.delay(0.3), value: isAnimated)

            // Pro teaser
            proTeaser
                .padding(.horizontal, Spacing.xxl)
                .opacity(isAnimated ? 1 : 0)
                .animation(AnimationConstants.smooth.delay(0.5), value: isAnimated)

            Spacer()

            // Bottom CTA
            VStack(spacing: Spacing.md) {
                GWButton(L10n.onboardingGetStarted, icon: "arrow.right") {
                    onComplete()
                }
                .padding(.horizontal, Spacing.xxl)
            }
            .padding(.bottom, Spacing.xxxl)
        }
        .onAppear {
            withAnimation {
                isAnimated = true
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(BrandColors.success.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimated ? 1.0 : 0.5)

                Circle()
                    .fill(BrandColors.success.opacity(0.05))
                    .frame(width: 160, height: 160)
                    .scaleEffect(isAnimated ? 1.0 : 0.3)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(BrandColors.success)
                    .scaleEffect(isAnimated ? 1.0 : 0.4)
            }
            .animation(AnimationConstants.bouncy, value: isAnimated)

            Text(L10n.onboardingAllSet)
                .font(Typography.largeTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(BrandColors.textPrimary)

            Text(L10n.onboardingAllSetSubtitle)
                .font(Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.xxxl)
        }
        .opacity(isAnimated ? 1 : 0)
        .offset(y: isAnimated ? 0 : 20)
        .animation(AnimationConstants.smooth.delay(0.1), value: isAnimated)
    }

    // MARK: - Quick Start Row

    private func quickStartRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.textPrimary)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
    }

    // MARK: - Pro Teaser

    private var proTeaser: some View {
        Button {
            appState.showingPaywall = true
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(BrandColors.primary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.onboardingProTeaser)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(L10n.onboardingProCTA)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(BrandColors.primary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandColors.primary)
            }
            .padding(Spacing.md)
            .background(BrandColors.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
        }
    }
}
