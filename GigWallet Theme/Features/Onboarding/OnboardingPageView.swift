import SwiftUI

struct OnboardingPageView: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color

    @State private var isAnimated = false

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .scaleEffect(isAnimated ? 1.0 : 0.5)

                Circle()
                    .fill(accentColor.opacity(0.05))
                    .frame(width: 220, height: 220)
                    .scaleEffect(isAnimated ? 1.0 : 0.3)

                Image(systemName: icon)
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(accentColor)
                    .scaleEffect(isAnimated ? 1.0 : 0.6)
            }
            .animation(AnimationConstants.bouncy, value: isAnimated)

            VStack(spacing: Spacing.md) {
                Text(title)
                    .font(Typography.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandColors.textPrimary)

                Text(subtitle)
                    .font(Typography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.horizontal, Spacing.xxxl)
            }
            .opacity(isAnimated ? 1 : 0)
            .offset(y: isAnimated ? 0 : 20)
            .animation(AnimationConstants.smooth.delay(0.1), value: isAnimated)

            Spacer()
            Spacer()
        }
        .onAppear { isAnimated = true }
        .onDisappear { isAnimated = false }
    }
}
